"""
Karriereseiten-Crawler
Geht direkt auf die Karriere/Jobs Seite jeder Firma.
Keine API nötig, nicht blockierbar.

Zusätzlich: 
- StepStone Firmen-Suche
- LinkedIn Jobs (öffentliche Suche)
- Xing Jobs
"""
import asyncio
import hashlib
import httpx
import re
from datetime import datetime, date
from typing import Optional
from bs4 import BeautifulSoup

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, func

from app.models.models import Company, JobPosting, CrawlerRun
from app.core.config import settings

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "de-DE,de;q=0.9,en;q=0.8",
}

# Mögliche Karriere-URL Pfade
CAREER_PATHS = [
    "/karriere", "/jobs", "/career", "/careers", "/stellenangebote",
    "/arbeiten-bei-uns", "/stellenausschreibungen", "/offene-stellen",
    "/ueber-uns/karriere", "/unternehmen/karriere", "/de/karriere",
    "/de/jobs", "/jobs/", "/karriere/", "/career/offene-stellen",
]

GROWTH_KEYWORDS = [
    "leiter", "leiterin", "head of", "director", "vp ", "manager",
    "aufbau", "expansion", "teamleiter",
]


def compute_id(company_id, url, title):
    return hashlib.md5(f"{company_id}:{url}:{title}".encode()).hexdigest()[:16]


def is_growth_signal(title):
    t = title.lower()
    for kw in GROWTH_KEYWORDS:
        if kw in t:
            return True, "leadership_hire"
    return False, None


async def find_career_page(client: httpx.AsyncClient, company: Company) -> Optional[str]:
    """Findet die Karriereseite einer Firma"""
    if not company.website:
        return None

    base = company.website.rstrip("/")
    if not base.startswith("http"):
        base = "https://" + base

    for path in CAREER_PATHS:
        url = base + path
        try:
            resp = await client.get(url, headers=HEADERS, timeout=8, follow_redirects=True)
            if resp.status_code == 200 and len(resp.text) > 500:
                # Prüfen ob es wirklich eine Jobs-Seite ist
                text_lower = resp.text.lower()
                if any(kw in text_lower for kw in ["stelle", "job", "career", "bewerbung", "position"]):
                    return url
        except Exception:
            pass
        await asyncio.sleep(0.3)

    return None


async def scrape_jobs_from_page(client: httpx.AsyncClient, url: str, company: Company) -> list[dict]:
    """Scrapt Jobs von einer Karriereseite"""
    jobs = []
    try:
        resp = await client.get(url, headers=HEADERS, timeout=10, follow_redirects=True)
        if resp.status_code != 200:
            return []

        soup = BeautifulSoup(resp.text, "lxml")

        # Alle Links die nach Jobs aussehen
        job_links = []
        for a in soup.find_all("a", href=True):
            href = a.get("href", "")
            text = a.get_text(strip=True)

            if not text or len(text) < 5 or len(text) > 200:
                continue

            # Ist es ein Job-Link?
            href_lower = href.lower()
            if any(kw in href_lower for kw in ["job", "stelle", "career", "position", "vacancy"]):
                if not href.startswith("http"):
                    base = "/".join(url.split("/")[:3])
                    href = base + href if href.startswith("/") else url + "/" + href
                job_links.append((text, href))

        # Auch direkte Texte in Listen/Tabellen
        for elem in soup.find_all(["li", "h2", "h3", "h4", "td"], class_=re.compile(r"job|stelle|position|vacancy|career", re.I)):
            text = elem.get_text(strip=True)
            if text and 10 < len(text) < 150:
                signal, signal_cat = is_growth_signal(text)
                jobs.append({
                    "title": text[:500],
                    "platform": "karriereseite",
                    "external_url": url,
                    "external_id": compute_id(str(company.id), url, text),
                    "location": company.city,
                    "platform_posted_at": date.today(),
                    "is_growth_signal": signal,
                    "signal_category": signal_cat,
                    "relevance_score": 80 if signal else 60,
                })

        # Job-Links verarbeiten
        seen_titles = set()
        for title, href in job_links[:20]:  # Max 20 Jobs pro Firma
            if title in seen_titles:
                continue
            seen_titles.add(title)
            signal, signal_cat = is_growth_signal(title)
            jobs.append({
                "title": title[:500],
                "platform": "karriereseite",
                "external_url": href,
                "external_id": compute_id(str(company.id), href, title),
                "location": company.city,
                "platform_posted_at": date.today(),
                "is_growth_signal": signal,
                "signal_category": signal_cat,
                "relevance_score": 85 if signal else 65,
            })

    except Exception as e:
        print(f"[Karriere] Scrape-Fehler {url}: {e}")

    # Dedup
    seen = set()
    unique = []
    for j in jobs:
        if j["external_id"] not in seen:
            seen.add(j["external_id"])
            unique.append(j)

    return unique[:25]  # Max 25 Jobs pro Firma


async def scrape_stepstone_company(client: httpx.AsyncClient, company: Company) -> list[dict]:
    """Sucht auf StepStone nach Jobs dieser Firma"""
    jobs = []
    company_name_encoded = company.name.split(" ")[0]  # Erstes Wort reicht meist
    url = f"https://www.stepstone.de/jobs/{company_name_encoded}/"

    try:
        resp = await client.get(url, headers=HEADERS, timeout=10, follow_redirects=True)
        if resp.status_code != 200:
            return []

        soup = BeautifulSoup(resp.text, "lxml")

        # StepStone Job-Karten
        for card in soup.find_all(["article", "div"], class_=re.compile(r"job|result|listing", re.I))[:15]:
            title_el = card.find(["h2", "h3", "a"], class_=re.compile(r"title|heading|name", re.I))
            if not title_el:
                title_el = card.find("a")
            if not title_el:
                continue

            title = title_el.get_text(strip=True)
            if not title or len(title) < 5:
                continue

            href = title_el.get("href", "")
            if href and not href.startswith("http"):
                href = "https://www.stepstone.de" + href

            signal, signal_cat = is_growth_signal(title)
            jobs.append({
                "title": title[:500],
                "platform": "stepstone",
                "external_url": href or url,
                "external_id": compute_id(str(company.id), href, title),
                "location": company.city,
                "platform_posted_at": date.today(),
                "is_growth_signal": signal,
                "signal_category": signal_cat,
                "relevance_score": 75 if signal else 55,
            })

    except Exception as e:
        print(f"[StepStone] Fehler {company.name}: {e}")

    return jobs


class CareerCrawlerOrchestrator:

    async def crawl_company(self, db: AsyncSession, company: Company) -> int:
        """Crawlt Karriereseite + StepStone für eine Firma"""
        all_jobs = []

        async with httpx.AsyncClient() as client:
            # 1. Karriereseite direkt
            career_url = await find_career_page(client, company)
            if career_url:
                print(f"[Karriere] {company.name}: Karriereseite gefunden → {career_url}")
                jobs = await scrape_jobs_from_page(client, career_url, company)
                all_jobs.extend(jobs)
                print(f"[Karriere] {company.name}: {len(jobs)} Jobs")
            else:
                print(f"[Karriere] {company.name}: Keine Karriereseite gefunden")

            await asyncio.sleep(2)

            # 2. StepStone
            ss_jobs = await scrape_stepstone_company(client, company)
            all_jobs.extend(ss_jobs)

        # In DB speichern
        new_count = 0
        for job_data in all_jobs:
            existing = (await db.execute(
                select(JobPosting).where(
                    and_(
                        JobPosting.company_id == company.id,
                        JobPosting.external_id == job_data["external_id"],
                    )
                )
            )).scalar_one_or_none()

            if existing:
                existing.last_seen_at = datetime.utcnow()
                existing.is_active = True
            else:
                db.add(JobPosting(company_id=company.id, **job_data))
                new_count += 1

        if new_count > 0:
            company.has_open_jobs = True
            company.open_jobs_count = (company.open_jobs_count or 0) + new_count
            company.last_job_signal_at = datetime.utcnow()

        await db.commit()
        return new_count

    async def run_full_scan(self, db: AsyncSession) -> dict:
        """Crawlt alle Firmen"""
        run = CrawlerRun(crawler_name="career_crawler", status="running")
        db.add(run)
        await db.commit()

        companies = (await db.execute(
            select(Company).where(Company.is_active == True)
            .order_by(Company.score.desc())
        )).scalars().all()

        total_new = 0
        errors = 0

        for company in companies:
            try:
                new = await self.crawl_company(db, company)
                total_new += new
                await asyncio.sleep(settings.CRAWLER_DELAY_SECONDS)
            except Exception as e:
                errors += 1
                print(f"[CareerCrawler] Fehler {company.name}: {e}")

        run.status = "success" if errors == 0 else "partial"
        run.records_new = total_new
        run.records_found = len(companies)
        run.finished_at = datetime.utcnow()
        await db.commit()

        return {"companies": len(companies), "new_jobs": total_new, "errors": errors}


career_crawler = CareerCrawlerOrchestrator()
