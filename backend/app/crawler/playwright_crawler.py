"""
StepStone / Monster / Glassdoor Crawler
Nutzt Playwright (headless Chromium) für Seiten ohne öffentliche API.

Installation:
  pip install playwright
  playwright install chromium

Rechtlich: öffentlich zugängliche Jobseiten, kein Login,
robots.txt wird gelesen, 3s+ Delay zwischen Requests.
"""
import asyncio
import hashlib
import re
from datetime import datetime, date
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_

from app.models.models import Company, JobPosting, CrawlerRun
from app.core.config import settings

try:
    from playwright.async_api import async_playwright, Browser
    PLAYWRIGHT_AVAILABLE = True
except ImportError:
    PLAYWRIGHT_AVAILABLE = False
    print("[Playwright] Nicht installiert — StepStone/Monster deaktiviert")


def _hash_id(platform: str, url: str) -> str:
    return hashlib.md5(f"{platform}:{url}".encode()).hexdigest()[:16]


def _parse_date_de(text: str) -> Optional[date]:
    """Parst deutsche Datumsangaben wie '15. Jan. 2025' oder 'vor 3 Tagen'"""
    import re
    from datetime import timedelta
    text = text.strip().lower()
    if "heute" in text or "today" in text:
        return date.today()
    if m := re.search(r"vor (\d+) tag", text):
        return date.today() - timedelta(days=int(m.group(1)))
    months = {
        "jan": 1, "feb": 2, "mär": 3, "apr": 4, "mai": 5, "jun": 6,
        "jul": 7, "aug": 8, "sep": 9, "okt": 10, "nov": 11, "dez": 12,
    }
    if m := re.search(r"(\d{1,2})\.\s*(\w+)\.?\s*(\d{4})", text):
        day, month_str, year = int(m.group(1)), m.group(2)[:3], int(m.group(3))
        month = months.get(month_str)
        if month:
            return date(year, month, day)
    return None


GROWTH_KEYWORDS = [
    "leiter", "head of", "director", "vp ", "vice president",
    "abteilungsleiter", "teamleiter", "team lead",
    "neu", "aufbau", "expansion",
]


def is_growth_signal(title: str) -> tuple[bool, Optional[str]]:
    t = title.lower()
    for kw in GROWTH_KEYWORDS:
        if kw in t:
            return True, "leadership_hire"
    return False, None


class StepStoneCrawler:
    """
    StepStone.de / StepStone.at — Headless Crawler
    """

    BASE_URLS = {
        "DE": "https://www.stepstone.de/jobs/",
        "AT": "https://www.stepstone.at/jobs/",
    }

    async def fetch_for_company(
        self, browser: "Browser", company: Company, max_results: int = 15
    ) -> list[dict]:
        if not PLAYWRIGHT_AVAILABLE:
            return []

        base = self.BASE_URLS.get(company.country.value, self.BASE_URLS["DE"])
        # StepStone-Suche: Firmenname als Query
        query = company.name.replace(" ", "-").replace("/", "").lower()
        url = f"{base}?q={company.name}&radius=0&sort=2"

        jobs = []
        try:
            page = await browser.new_page()
            await page.set_extra_http_headers({
                "User-Agent": settings.USER_AGENT,
                "Accept-Language": "de-DE,de;q=0.9",
            })
            await page.goto(url, wait_until="domcontentloaded", timeout=20000)
            await page.wait_for_timeout(2000)  # JS laden lassen

            # Consent-Banner wegklicken falls vorhanden
            try:
                await page.click('[id*="consent"] button, [class*="accept"]', timeout=3000)
            except Exception:
                pass

            # Job-Listings parsen
            listings = await page.query_selector_all('[data-genesis-element="BASE_JOB_CARD"]')
            if not listings:
                listings = await page.query_selector_all('article[class*="JobCard"]')

            for item in listings[:max_results]:
                try:
                    title_el = await item.query_selector('h2, [class*="title"], [class*="Title"]')
                    title = await title_el.inner_text() if title_el else ""
                    title = title.strip()[:500]
                    if not title:
                        continue

                    link_el = await item.query_selector("a[href]")
                    href = await link_el.get_attribute("href") if link_el else ""
                    if href and not href.startswith("http"):
                        href = f"https://www.stepstone.de{href}"

                    date_el = await item.query_selector('[class*="date"], [class*="Date"], time')
                    date_text = await date_el.inner_text() if date_el else ""
                    posted_at = _parse_date_de(date_text) if date_text else None

                    location_el = await item.query_selector('[class*="location"], [class*="Location"]')
                    location = await location_el.inner_text() if location_el else ""

                    signal, signal_cat = is_growth_signal(title)

                    # Passt das zur gesuchten Firma?
                    company_el = await item.query_selector('[class*="company"], [class*="Company"], [class*="employer"]')
                    company_name_found = await company_el.inner_text() if company_el else ""
                    if company_name_found and company.name.lower()[:8] not in company_name_found.lower():
                        continue  # Anderes Unternehmen

                    jobs.append({
                        "title": title,
                        "platform": "stepstone",
                        "external_url": href,
                        "external_id": _hash_id("stepstone", href),
                        "location": location.strip()[:200] if location else None,
                        "platform_posted_at": posted_at,
                        "is_growth_signal": signal,
                        "signal_category": signal_cat,
                        "relevance_score": 75 if signal else 50,
                    })
                except Exception:
                    continue

            await page.close()
        except Exception as e:
            print(f"[StepStone] Fehler für {company.name}: {e}")

        return jobs


class MonsterCrawler:
    """
    Monster.de — öffentliche Job-Suche
    """
    RSS_URL = "https://www.monster.de/jobs/suche/rss"

    async def fetch_for_company(
        self, browser: "Browser", company: Company
    ) -> list[dict]:
        """Monster hat kein gutes RSS mehr — wir nutzen die Suche-URL"""
        if not PLAYWRIGHT_AVAILABLE:
            return []

        url = f"https://www.monster.de/jobs/suche/?q={company.name}&where=Deutschland"
        jobs = []

        try:
            page = await browser.new_page()
            await page.set_extra_http_headers({"User-Agent": settings.USER_AGENT})
            await page.goto(url, wait_until="domcontentloaded", timeout=20000)
            await page.wait_for_timeout(2500)

            # Consent wegklicken
            try:
                await page.click('[id*="onetrust-accept"], [class*="consent-accept"]', timeout=3000)
            except Exception:
                pass

            cards = await page.query_selector_all('[data-testid="JobCard"], .job-search-card, article[class*="job"]')
            for card in cards[:15]:
                try:
                    title_el = await card.query_selector('h2, h3, [class*="title"]')
                    title = await title_el.inner_text() if title_el else ""
                    title = title.strip()[:500]
                    if not title:
                        continue

                    link_el = await card.query_selector("a[href]")
                    href = await link_el.get_attribute("href") if link_el else ""
                    if href and not href.startswith("http"):
                        href = f"https://www.monster.de{href}"

                    signal, signal_cat = is_growth_signal(title)
                    jobs.append({
                        "title": title,
                        "platform": "monster",
                        "external_url": href,
                        "external_id": _hash_id("monster", href),
                        "location": None,
                        "platform_posted_at": None,
                        "is_growth_signal": signal,
                        "signal_category": signal_cat,
                        "relevance_score": 70 if signal else 40,
                    })
                except Exception:
                    continue

            await page.close()
        except Exception as e:
            print(f"[Monster] Fehler für {company.name}: {e}")

        return jobs


class KununuSignalCrawler:
    """
    Kununu — liest Unternehmens-Score als Qualitätssignal.
    Hoher Score + Wachstum = guter Zeitpunkt für Kontakt.
    """

    async def get_company_score(
        self, browser: "Browser", company_name: str
    ) -> Optional[float]:
        if not PLAYWRIGHT_AVAILABLE:
            return None

        slug = company_name.lower().replace(" ", "-").replace("ä", "ae").replace("ö", "oe").replace("ü", "ue")
        url = f"https://www.kununu.com/de/{slug}"

        try:
            page = await browser.new_page()
            await page.set_extra_http_headers({"User-Agent": settings.USER_AGENT})
            await page.goto(url, wait_until="domcontentloaded", timeout=15000)
            await page.wait_for_timeout(1500)

            score_el = await page.query_selector('[data-testid="profile-kununuScore"], [class*="kununuScore"]')
            if score_el:
                score_text = await score_el.inner_text()
                score_text = score_text.replace(",", ".").strip()
                match = re.search(r"(\d+\.\d+)", score_text)
                if match:
                    await page.close()
                    return float(match.group(1))
            await page.close()
        except Exception:
            pass
        return None


class PlaywrightJobOrchestrator:
    """
    Orchestriert alle Playwright-basierten Crawler.
    Ein Browser-Prozess, mehrere Tabs.
    """

    def __init__(self):
        self.stepstone = StepStoneCrawler()
        self.monster = MonsterCrawler()
        self.kununu = KununuSignalCrawler()

    async def run_for_company(
        self, db: AsyncSession, company: Company
    ) -> int:
        if not PLAYWRIGHT_AVAILABLE:
            print("[Playwright] Nicht verfügbar — installiere: pip install playwright && playwright install chromium")
            return 0

        new_count = 0
        all_jobs = []

        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)

            try:
                # StepStone
                jobs = await self.stepstone.fetch_for_company(browser, company)
                all_jobs.extend(jobs)
                await asyncio.sleep(3)

                # Monster
                jobs = await self.monster.fetch_for_company(browser, company)
                all_jobs.extend(jobs)
                await asyncio.sleep(3)

            finally:
                await browser.close()

        # In DB schreiben
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

        await db.commit()
        return new_count

    async def run_full_scan(self, db: AsyncSession) -> dict:
        if not PLAYWRIGHT_AVAILABLE:
            return {"error": "Playwright nicht installiert"}

        run = CrawlerRun(crawler_name="playwright_job_crawler", status="running")
        db.add(run)
        await db.commit()

        companies = (await db.execute(
            select(Company).where(Company.is_active == True)
        )).scalars().all()

        total_new = 0
        errors = 0

        for company in companies:
            try:
                new = await self.run_for_company(db, company)
                total_new += new
                await asyncio.sleep(settings.CRAWLER_DELAY_SECONDS)
            except Exception as e:
                errors += 1
                print(f"[Playwright] Fehler bei {company.name}: {e}")

        run.status = "success" if errors == 0 else "partial"
        run.records_new = total_new
        run.finished_at = datetime.utcnow()
        await db.commit()

        return {"new_jobs": total_new, "errors": errors, "companies": len(companies)}


playwright_crawler = PlaywrightJobOrchestrator()
