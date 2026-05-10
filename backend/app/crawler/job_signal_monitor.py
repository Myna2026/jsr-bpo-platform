"""
Job Signal Monitor v2
Sucht nach Tourismus-Jobs per Keyword, matched mit DB-Firmen.
"""
import asyncio
import hashlib
import httpx
import re
import xml.etree.ElementTree as ET
from datetime import datetime, date
from typing import Optional
from email.utils import parsedate_to_datetime

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_

from app.models.models import Company, JobPosting, CrawlerRun
from app.core.config import settings

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
    "Accept-Language": "de-DE,de;q=0.9",
}

GROWTH_KEYWORDS = ["leiter", "leiterin", "head of", "director", "vp ", "manager", "aufbau", "expansion"]
SEARCH_TERMS = ["Reiseveranstalter", "Touristik", "Hotel Manager", "Revenue Manager", "Customer Service Reisen", "Sales Manager Tourismus"]

def compute_id(platform, url, title):
    return hashlib.md5(f"{platform}:{url}:{title}".encode()).hexdigest()[:16]

def is_growth_signal(title):
    t = title.lower()
    for kw in GROWTH_KEYWORDS:
        if kw in t:
            return True, "leadership_hire"
    return False, None

def parse_date(text):
    if not text:
        return None
    try:
        return parsedate_to_datetime(text).date()
    except Exception:
        try:
            return date.fromisoformat(text[:10])
        except Exception:
            return None

def parse_rss(xml_text, platform):
    jobs = []
    try:
        root = ET.fromstring(xml_text)
        for item in root.findall(".//item"):
            title = item.findtext("title", "").strip()
            url = item.findtext("link", "").strip()
            if not title or not url:
                continue
            company_hint = ""
            if " - " in title and platform == "indeed":
                parts = title.rsplit(" - ", 1)
                title = parts[0].strip()
                company_hint = parts[1].strip()
            signal, signal_cat = is_growth_signal(title)
            jobs.append({
                "title": title[:500],
                "platform": platform,
                "external_url": url,
                "external_id": compute_id(platform, url, title),
                "location": None,
                "platform_posted_at": parse_date(item.findtext("pubDate", "")),
                "is_growth_signal": signal,
                "signal_category": signal_cat,
                "relevance_score": 75 if signal else 50,
                "_hint": company_hint,
            })
    except ET.ParseError:
        pass
    return jobs


class JobOrchestrator:

    async def run_full_scan(self, db: AsyncSession) -> dict:
        run = CrawlerRun(crawler_name="job_signal_monitor_v2", status="running")
        db.add(run)
        await db.commit()

        companies = (await db.execute(select(Company).where(Company.is_active == True))).scalars().all()
        
        # Firmen-Index für Matching
        idx = {}
        for c in companies:
            for key in [c.name.lower(), re.sub(r'\s+(gmbh|ag|se|kg|co\.?\s*kg|gmbh\s*&\s*co\.?\s*kg).*$', '', c.name.lower()).strip()]:
                if key:
                    idx[key] = c

        all_jobs = []
        async with httpx.AsyncClient() as client:
            for term in SEARCH_TERMS:
                for location in ["Deutschland", "Österreich", "Schweiz"]:
                    try:
                        resp = await client.get(
                            "https://de.indeed.com/rss",
                            params={"q": term, "l": location, "limit": 20, "fromage": 30},
                            headers=HEADERS, timeout=10,
                        )
                        if resp.status_code == 200:
                            jobs = parse_rss(resp.text, "indeed")
                            all_jobs.extend(jobs)
                            print(f"[Indeed] {term}/{location}: {len(jobs)} Jobs")
                        await asyncio.sleep(2)
                    except Exception as e:
                        print(f"[Indeed] Fehler {term}: {e}")

        # Jobs speichern
        new_count = 0
        for job_data in all_jobs:
            hint = job_data.pop("_hint", "")
            company = None

            # Match versuchen
            if hint:
                hint_clean = re.sub(r'\s+(gmbh|ag|se|kg).*$', '', hint.lower()).strip()
                company = idx.get(hint_clean) or idx.get(hint.lower())

            if not company:
                title_lower = job_data["title"].lower()
                for key, c in idx.items():
                    if len(key) > 5 and key in title_lower:
                        company = c
                        break

            if not company:
                continue

            existing = (await db.execute(
                select(JobPosting).where(and_(
                    JobPosting.company_id == company.id,
                    JobPosting.external_id == job_data["external_id"],
                ))
            )).scalar_one_or_none()

            if existing:
                existing.last_seen_at = datetime.utcnow()
            else:
                db.add(JobPosting(company_id=company.id, **job_data))
                company.has_open_jobs = True
                company.open_jobs_count = (company.open_jobs_count or 0) + 1
                company.last_job_signal_at = datetime.utcnow()
                new_count += 1

        await db.commit()

        run.status = "success"
        run.records_found = len(all_jobs)
        run.records_new = new_count
        run.finished_at = datetime.utcnow()
        await db.commit()

        return {"total_found": len(all_jobs), "saved": new_count}

    async def run_for_company(self, db, company):
        return 0


job_monitor = JobOrchestrator()
