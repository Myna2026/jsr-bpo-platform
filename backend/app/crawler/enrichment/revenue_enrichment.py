"""
Bundesanzeiger Jahresabschluss-Crawler
Extrahiert Umsatz, Mitarbeiterzahl und weitere Kennzahlen
aus dem elektronischen Bundesanzeiger (bundesanzeiger.de).

Öffentlich zugänglich — Jahresabschlüsse sind gesetzlich
zur Veröffentlichung verpflichtet (§ 325 HGB).
"""
import asyncio
import re
import httpx
from typing import Optional
from datetime import datetime

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.models import Company, CrawlerRun
from app.core.config import settings

try:
    from playwright.async_api import async_playwright
    PLAYWRIGHT_AVAILABLE = True
except ImportError:
    PLAYWRIGHT_AVAILABLE = False


def _parse_euro_amount(text: str) -> Optional[int]:
    """Konvertiert deutsche Zahlendarstellung → int in Euro"""
    if not text:
        return None
    text = text.strip()
    # Entferne EUR, T€, Tsd., Mio. etc.
    multiplier = 1
    if re.search(r"mio|million", text, re.IGNORECASE):
        multiplier = 1_000_000
    elif re.search(r"tsd|tausend|t€|t eur", text, re.IGNORECASE):
        multiplier = 1_000

    # Zahlen extrahieren (deutsches Format: 1.234.567,89)
    text = re.sub(r"[^\d,.]", "", text)
    text = text.replace(".", "").replace(",", ".")  # → 1234567.89
    try:
        return int(float(text) * multiplier)
    except (ValueError, OverflowError):
        return None


def _extract_revenue_from_text(text: str) -> Optional[int]:
    """
    Sucht nach Umsatz-Kennzahlen in Jahresabschluss-Texten.
    Verschiedene Bezeichnungen je nach Unternehmensform.
    """
    patterns = [
        # Vollständige Bezeichnungen
        r"Umsatzerlöse\s+(\d[\d.,]+)\s*(T€|Tsd|Mio|EUR|€)?",
        r"Gesamtumsatz\s+(\d[\d.,]+)\s*(T€|Tsd|Mio|EUR|€)?",
        r"Umsatz\s+(\d[\d.,]+)\s*(T€|Tsd|Mio|EUR|€)?",
        r"Net\s+revenues?\s+(\d[\d.,]+)",
        r"Revenue\s+(\d[\d.,]+)",
        # Aus Bilanz-Tabellen
        r"1\.\s+Umsatzerlöse\s+(\d[\d.,]+)",
    ]
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE | re.MULTILINE)
        if match:
            amount_str = match.group(1)
            # Einheit aus dem Match oder Kontext
            unit = match.group(2) if match.lastindex >= 2 and match.group(2) else ""
            full_str = amount_str + " " + unit
            result = _parse_euro_amount(full_str)
            if result and result > 10_000:  # Plausibilitätscheck
                return result
    return None


def _extract_employees_from_text(text: str) -> Optional[int]:
    patterns = [
        r"(?:Mitarbeiter|Arbeitnehmer|Beschäftigte)[\s:]+(\d[\d.]+)",
        r"durchschnittlich\s+(\d[\d.]+)\s+(?:Mitarbeiter|Beschäftigte)",
        r"(\d[\d.]+)\s+(?:Mitarbeiter|Beschäftigte|Arbeitnehmer)",
    ]
    for pattern in patterns:
        match = re.search(pattern, text, re.IGNORECASE)
        if match:
            try:
                return int(match.group(1).replace(".", ""))
            except ValueError:
                continue
    return None


class BundesanzeigerCrawler:
    """
    Crawlt den Bundesanzeiger für Jahresabschluss-Daten.
    Nutzt die öffentliche Suche unter bundesanzeiger.de.
    """

    SEARCH_URL = "https://www.bundesanzeiger.de/pub/de/suchergebnis"

    async def fetch_financial_data(
        self, company: Company
    ) -> dict:
        """Gibt Umsatz, Mitarbeiter und Jahr zurück"""
        if not PLAYWRIGHT_AVAILABLE:
            return await self._fallback_opencorporates(company)

        result = {}
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            try:
                result = await self._scrape_bundesanzeiger(browser, company)
            finally:
                await browser.close()

        return result

    async def _scrape_bundesanzeiger(self, browser, company: Company) -> dict:
        """Eigentlicher Scrape-Vorgang"""
        page = await browser.new_page()
        await page.set_extra_http_headers({"User-Agent": settings.USER_AGENT})

        try:
            # Suche nach Firmenname
            await page.goto(
                f"https://www.bundesanzeiger.de/pub/de/suchergebnis?0-1.IFormSubmitListener-form&"
                f"fulltext={company.name.replace(' ', '+')}&category=EB",
                wait_until="domcontentloaded",
                timeout=20000,
            )
            await page.wait_for_timeout(2000)

            # Ersten Treffer öffnen
            result_links = await page.query_selector_all('table.result a[href*="bekanntmachung"]')
            if not result_links:
                return {}

            href = await result_links[0].get_attribute("href")
            if not href:
                return {}

            if not href.startswith("http"):
                href = f"https://www.bundesanzeiger.de{href}"

            await page.goto(href, wait_until="domcontentloaded", timeout=20000)
            await page.wait_for_timeout(1500)

            # Text extrahieren
            content = await page.inner_text("body")
            await page.close()

            revenue = _extract_revenue_from_text(content)
            employees = _extract_employees_from_text(content)

            # Berichtsjahr aus URL oder Seite extrahieren
            year_match = re.search(r"20\d{2}", href)
            year = int(year_match.group()) if year_match else datetime.now().year - 1

            return {
                "revenue_approx_eur": revenue,
                "employees_approx": employees,
                "revenue_year": year,
                "revenue_source": "Bundesanzeiger",
            }

        except Exception as e:
            print(f"[Bundesanzeiger] Fehler für {company.name}: {e}")
            await page.close()
            return {}

    async def _fallback_opencorporates(self, company: Company) -> dict:
        """Fallback wenn Playwright nicht verfügbar: OpenCorporates Financials"""
        # OpenCorporates bietet keine Finanzdaten im Free-Tier
        # Als Fallback: Schätzung basierend auf Mitarbeiterzahl
        return {}


class RevenueEnrichmentService:
    """
    Orchestriert die Umsatz-Anreicherung für alle Unternehmen.
    Priorisiert große Unternehmen und solche ohne Umsatzdaten.
    """

    def __init__(self):
        self.bundesanzeiger = BundesanzeigerCrawler()

    async def enrich_company(self, db: AsyncSession, company: Company) -> bool:
        """Reichert ein Unternehmen mit Finanzdaten an"""
        data = await self.bundesanzeiger.fetch_financial_data(company)
        if not data:
            return False

        if data.get("revenue_approx_eur") and not company.revenue_approx_eur:
            company.revenue_approx_eur = data["revenue_approx_eur"]
            company.revenue_year = data.get("revenue_year")
            company.revenue_source = data.get("revenue_source", "Bundesanzeiger")

        if data.get("employees_approx") and not company.employees_approx:
            company.employees_approx = data["employees_approx"]
            # Größe neu berechnen
            from app.crawler.company_crawler import estimate_size
            company.size = estimate_size(company.employees_approx)

        # Score anpassen
        if company.revenue_approx_eur:
            bonus = 0
            if company.revenue_approx_eur > 100_000_000:
                bonus = 15
            elif company.revenue_approx_eur > 10_000_000:
                bonus = 10
            elif company.revenue_approx_eur > 1_000_000:
                bonus = 5
            company.score = min(company.score + bonus, 98)
            company.data_quality = min(company.data_quality + 15, 98)

        company.last_crawled_at = datetime.utcnow()
        await db.commit()
        return True

    async def enrich_all(self, db: AsyncSession) -> dict:
        """Alle DE-Unternehmen ohne Umsatzdaten anreichern"""
        run = CrawlerRun(crawler_name="bundesanzeiger_revenue", status="running")
        db.add(run)
        await db.commit()

        from app.models.models import CountryCode
        companies = (await db.execute(
            select(Company).where(
                Company.is_active == True,
                Company.country == CountryCode.DE,  # Nur DE — BA ist nur für DE
                Company.revenue_approx_eur.is_(None),
            ).order_by(Company.score.desc())
        )).scalars().all()

        enriched = 0
        errors = 0

        for company in companies:
            try:
                success = await self.enrich_company(db, company)
                if success:
                    enriched += 1
                await asyncio.sleep(settings.CRAWLER_DELAY_SECONDS + 1)
            except Exception as e:
                errors += 1
                print(f"[RevenueEnrichment] Fehler bei {company.name}: {e}")

        run.status = "success" if errors == 0 else "partial"
        run.records_found = len(companies)
        run.records_updated = enriched
        run.finished_at = datetime.utcnow()
        await db.commit()

        return {"enriched": enriched, "total": len(companies), "errors": errors}


revenue_enrichment = RevenueEnrichmentService()
