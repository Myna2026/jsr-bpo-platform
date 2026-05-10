"""
RFP / Ausschreibungs-Crawler für Call Center & Service Center
Quellen:
  1. TED (Tenders Electronic Daily) — EU-weit, offiziell kostenlos
  2. DTVP — Deutsches Vergabeportal (RSS)
  3. Vergabe24.de (RSS)
  4. Bund.de Ausschreibungen
  5. Auftragsboerse.de

Kaufsignal: Unternehmen sucht Call Center / Contact Center Dienstleister
→ Automatisch Priorität erhöhen + Benachrichtigung
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

from app.models.models import Company, CrawlerRun
from app.core.config import settings

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
    "Accept-Language": "de-DE,de;q=0.9",
    "Accept": "application/xml,text/xml,application/rss+xml,*/*",
}

# Keywords für Call Center / Service Center Ausschreibungen
CC_KEYWORDS = [
    "call center", "callcenter", "contact center", "contactcenter",
    "customer service outsourcing", "kundendienst dienstleister",
    "telefonservice", "telefondienstleistung", "buchungshotline",
    "reservierungsservice", "inbound telefonie", "outbound telefonie",
    "telefonischer kundendienst", "servicecenter", "service center",
    "helpdesk outsourcing", "kundenkommunikation", "dialogmarketing",
    "telemarketing", "kundenhotline", "beschwerdemanagement telefon",
    "customer care outsourcing", "bpo", "business process outsourcing",
]

# Tourismus-spezifische Keywords
TOURISM_CC_KEYWORDS = [
    "reisebüro hotline", "buchungsservice reise", "touristik callcenter",
    "hotel reservierung service", "airline customer service",
    "travel contact center", "reisehotline", "tourismushotline",
]

ALL_KEYWORDS = CC_KEYWORDS + TOURISM_CC_KEYWORDS


def compute_id(source: str, url: str) -> str:
    return hashlib.md5(f"{source}:{url}".encode()).hexdigest()[:20]


def contains_cc_keyword(text: str) -> tuple[bool, str]:
    text_lower = text.lower()
    for kw in ALL_KEYWORDS:
        if kw in text_lower:
            return True, kw
    return False, ""


def parse_date_safe(text: str) -> Optional[date]:
    if not text:
        return None
    try:
        return parsedate_to_datetime(text).date()
    except Exception:
        try:
            return date.fromisoformat(text[:10])
        except Exception:
            return None


# ── TED Crawler (EU Tenders) ──────────────────────────────────

class TEDCrawler:
    """
    TED = Tenders Electronic Daily
    Offizielle EU-Ausschreibungsdatenbank
    API: https://ted.europa.eu/api/v3.0/
    Kostenlos, offiziell, DACH-Filter
    """
    API_URL = "https://ted.europa.eu/api/v3.0/notices/search"

    async def search(self, client: httpx.AsyncClient) -> list[dict]:
        results = []
        
        # Suche nach Call Center relevanten Ausschreibungen in DACH
        for keyword in ["call center", "contact center", "customer service", "Kundendienst Outsourcing"]:
            try:
                payload = {
                    "query": f'("{keyword}") AND (ND=[DE] OR ND=[AT] OR ND=[CH])',
                    "fields": ["ND", "TI", "PC", "AC", "DT", "CY", "OC", "AU"],
                    "page": {"number": 1, "size": 10},
                    "sort": [{"field": "ND", "order": "desc"}],
                    "scope": "ACTIVE",
                }
                resp = await client.post(
                    self.API_URL,
                    json=payload,
                    headers={**HEADERS, "Accept": "application/json", "Content-Type": "application/json"},
                    timeout=15,
                )
                if resp.status_code == 200:
                    data = resp.json()
                    notices = data.get("notices", [])
                    for n in notices:
                        title = n.get("TI", [{}])[0].get("value", "") if n.get("TI") else ""
                        url = f"https://ted.europa.eu/udl?uri=TED:NOTICE:{n.get('ND', '')}:TEXT:DE:HTML"
                        is_relevant, matched_kw = contains_cc_keyword(title)
                        if is_relevant or keyword.lower() in title.lower():
                            results.append({
                                "title": title[:500],
                                "source": "TED",
                                "url": url,
                                "external_id": compute_id("ted", n.get("ND", url)),
                                "country": n.get("CY", [{}])[0].get("value", "") if n.get("CY") else "",
                                "published_at": None,
                                "deadline": None,
                                "keyword_matched": matched_kw or keyword,
                                "contracting_authority": n.get("AU", [{}])[0].get("value", "") if n.get("AU") else "",
                                "description": "",
                            })
                await asyncio.sleep(1.5)
            except Exception as e:
                print(f"[TED] Fehler bei '{keyword}': {e}")

        return results


class DVTRSSCrawler:
    """
    DTVP und ähnliche Vergabeportale via RSS
    """
    RSS_FEEDS = [
        ("vergabe24", "https://www.vergabe24.de/ausschreibungen/rss.xml"),
        ("auftragsboerse", "https://www.auftragsboerse.de/rss/ausschreibungen.xml"),
    ]

    async def search(self, client: httpx.AsyncClient) -> list[dict]:
        results = []
        for source_name, feed_url in self.RSS_FEEDS:
            try:
                resp = await client.get(feed_url, headers=HEADERS, timeout=10)
                if resp.status_code == 200:
                    items = self._parse_rss(resp.text, source_name)
                    results.extend(items)
                await asyncio.sleep(1)
            except Exception as e:
                print(f"[{source_name}] RSS Fehler: {e}")
        return results

    def _parse_rss(self, xml_text: str, source: str) -> list[dict]:
        items = []
        try:
            root = ET.fromstring(xml_text)
            for item in root.findall(".//item"):
                title = item.findtext("title", "").strip()
                url = item.findtext("link", "").strip()
                desc = item.findtext("description", "").strip()
                pub_date = item.findtext("pubDate", "")

                combined_text = title + " " + desc
                is_relevant, matched_kw = contains_cc_keyword(combined_text)

                if not is_relevant:
                    continue

                items.append({
                    "title": title[:500],
                    "source": source.upper(),
                    "url": url,
                    "external_id": compute_id(source, url),
                    "country": "DE",
                    "published_at": parse_date_safe(pub_date),
                    "deadline": None,
                    "keyword_matched": matched_kw,
                    "contracting_authority": "",
                    "description": desc[:1000] if desc else "",
                })
        except ET.ParseError:
            pass
        return items


class GoogleNewsRFPCrawler:
    """
    Google News RSS für RFP/Ausschreibungs-Nachrichten
    Sucht nach aktuellen Meldungen über Call Center Ausschreibungen
    """
    BASE_URL = "https://news.google.com/rss/search"

    async def search(self, client: httpx.AsyncClient) -> list[dict]:
        results = []
        search_terms = [
            "Ausschreibung Call Center Tourismus",
            "RFP Contact Center Reisen",
            "Vergabe Kundendienst Outsourcing Deutschland",
            "Ausschreibung Buchungshotline",
        ]

        for term in search_terms:
            try:
                params = {
                    "q": term,
                    "hl": "de",
                    "gl": "DE",
                    "ceid": "DE:de",
                }
                resp = await client.get(self.BASE_URL, params=params, headers=HEADERS, timeout=10)
                if resp.status_code == 200:
                    items = self._parse_rss(resp.text)
                    results.extend(items)
                await asyncio.sleep(1.5)
            except Exception as e:
                print(f"[GoogleNews] Fehler '{term}': {e}")

        return results

    def _parse_rss(self, xml_text: str) -> list[dict]:
        items = []
        try:
            root = ET.fromstring(xml_text)
            for item in root.findall(".//item"):
                title = item.findtext("title", "").strip()
                url = item.findtext("link", "").strip()
                pub_date = item.findtext("pubDate", "")

                is_relevant, matched_kw = contains_cc_keyword(title)
                if not is_relevant:
                    continue

                items.append({
                    "title": title[:500],
                    "source": "Google News",
                    "url": url,
                    "external_id": compute_id("gnews", url),
                    "country": "DE",
                    "published_at": parse_date_safe(pub_date),
                    "deadline": None,
                    "keyword_matched": matched_kw,
                    "contracting_authority": "",
                    "description": "",
                })
        except ET.ParseError:
            pass
        return items


# ── RFP Model (in DB als JSON gespeichert) ───────────────────

class RFPStore:
    """
    Speichert RFPs in einer einfachen JSON-Tabelle.
    Wir nutzen crawler_runs.meta als temporären Store
    bis wir eine eigene rfp_opportunities Tabelle haben.
    """

    async def save_rfps(self, db: AsyncSession, rfps: list[dict]) -> int:
        if not rfps:
            return 0

        run = CrawlerRun(
            crawler_name="rfp_scan",
            status="success",
            records_found=len(rfps),
            records_new=len(rfps),
            finished_at=datetime.utcnow(),
            meta={
                "rfps": rfps,
                "scan_date": datetime.utcnow().isoformat(),
                "total": len(rfps),
            }
        )
        db.add(run)
        await db.commit()
        return len(rfps)

    async def get_latest_rfps(self, db: AsyncSession, limit: int = 50) -> list[dict]:
        result = (await db.execute(
            select(CrawlerRun)
            .where(CrawlerRun.crawler_name == "rfp_scan")
            .order_by(CrawlerRun.started_at.desc())
            .limit(5)
        )).scalars().all()

        all_rfps = []
        seen_ids = set()
        for run in result:
            if run.meta and "rfps" in run.meta:
                for rfp in run.meta["rfps"]:
                    if rfp.get("external_id") not in seen_ids:
                        seen_ids.add(rfp.get("external_id"))
                        all_rfps.append(rfp)
        return all_rfps[:limit]


# ── Orchestrator ─────────────────────────────────────────────

class RFPOrchestrator:

    def __init__(self):
        self.ted = TEDCrawler()
        self.rss = DVTRSSCrawler()
        self.news = GoogleNewsRFPCrawler()
        self.store = RFPStore()

    async def run_scan(self, db: AsyncSession) -> dict:
        print("[RFP] Starte Ausschreibungs-Scan...")
        all_rfps = []

        async with httpx.AsyncClient() as client:
            # TED EU Ausschreibungen
            print("[RFP] TED wird abgefragt...")
            ted_rfps = await self.ted.search(client)
            all_rfps.extend(ted_rfps)
            print(f"[RFP] TED: {len(ted_rfps)} Ausschreibungen")

            await asyncio.sleep(2)

            # RSS Feeds
            print("[RFP] RSS Vergabe-Feeds werden abgefragt...")
            rss_rfps = await self.rss.search(client)
            all_rfps.extend(rss_rfps)
            print(f"[RFP] RSS: {len(rss_rfps)} Ausschreibungen")

            await asyncio.sleep(2)

            # Google News
            print("[RFP] Google News wird abgefragt...")
            news_rfps = await self.news.search(client)
            all_rfps.extend(news_rfps)
            print(f"[RFP] News: {len(news_rfps)} Ausschreibungen")

        # Dedup
        seen = set()
        unique_rfps = []
        for rfp in all_rfps:
            if rfp["external_id"] not in seen:
                seen.add(rfp["external_id"])
                unique_rfps.append(rfp)

        # Speichern
        saved = await self.store.save_rfps(db, unique_rfps)
        print(f"[RFP] {saved} einzigartige Ausschreibungen gespeichert")

        return {
            "total_found": len(all_rfps),
            "unique": len(unique_rfps),
            "saved": saved,
            "sources": {
                "ted": len(ted_rfps),
                "rss": len(rss_rfps),
                "news": len(news_rfps),
            }
        }


rfp_orchestrator = RFPOrchestrator()
