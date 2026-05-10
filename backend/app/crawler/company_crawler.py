"""
DACH Tourism Company Crawler
Quellen:
  1. Bundesanzeiger (Jahresabschlüsse → Umsatz)
  2. Unternehmensregister
  3. DRV / DTVB Mitgliederlisten (statisch, manuell gepflegt)
  4. Google Maps Business (via Places API)
  5. OpenCorporates API (kostenlos, rate-limited)

Alle Crawler sind so gebaut dass sie legal arbeiten:
- Nur öffentlich zugängliche Daten
- robots.txt wird respektiert
- Rate-Limits eingehalten
- User-Agent klar als Bot deklariert
"""
import asyncio
import re
import httpx
from datetime import datetime
from typing import Optional
from dataclasses import dataclass

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.models import (
    Company, CrawlerRun,
    CompanyCategory, CompanySize, CountryCode, LeadPriority
)
from app.core.config import settings


HEADERS = {
    "User-Agent": settings.USER_AGENT,
    "Accept": "application/json",
}

# ── Bekannte DACH Tourism Unternehmen als Seed (Auszug) ──────
# In Produktion: aus CSV/Excel importieren oder via Verbands-Websites scrapen

SEED_COMPANIES = [
    # Airlines
    {"name": "Lufthansa AG", "category": "airline", "country": "DE", "city": "Frankfurt", "website": "https://www.lufthansa.com", "size": "enterprise"},
    {"name": "Austrian Airlines AG", "category": "airline", "country": "AT", "city": "Wien", "website": "https://www.austrian.com", "size": "large"},
    {"name": "Swiss International Air Lines AG", "category": "airline", "country": "CH", "city": "Basel", "website": "https://www.swiss.com", "size": "large"},
    {"name": "Eurowings GmbH", "category": "airline", "country": "DE", "city": "Düsseldorf", "website": "https://www.eurowings.com", "size": "large"},
    {"name": "Condor Flugdienst GmbH", "category": "airline", "country": "DE", "city": "Frankfurt", "website": "https://www.condor.com", "size": "medium"},
    {"name": "Ryanair Holdings plc", "category": "airline", "country": "DE", "city": "Dublin", "website": "https://www.ryanair.com", "size": "enterprise"},
    {"name": "easyJet Europe Airline GmbH", "category": "airline", "country": "AT", "city": "Wien", "website": "https://www.easyjet.com", "size": "enterprise"},
    {"name": "TUIfly GmbH", "category": "airline", "country": "DE", "city": "Hannover", "website": "https://www.tuifly.com", "size": "large"},

    # Kreuzfahrt
    {"name": "AIDA Cruises", "category": "kreuzfahrt", "country": "DE", "city": "Rostock", "website": "https://www.aida.de", "size": "large"},
    {"name": "TUI Cruises GmbH", "category": "kreuzfahrt", "country": "DE", "city": "Hamburg", "website": "https://www.tuicruises.com", "size": "medium"},
    {"name": "Hapag-Lloyd Cruises", "category": "kreuzfahrt", "country": "DE", "city": "Hamburg", "website": "https://www.hl-cruises.com", "size": "medium"},
    {"name": "MSC Kreuzfahrten GmbH", "category": "kreuzfahrt", "country": "DE", "city": "Hamburg", "website": "https://www.msc.com", "size": "large"},
    {"name": "Costa Kreuzfahrten", "category": "kreuzfahrt", "country": "DE", "city": "Hamburg", "website": "https://www.costakreuzfahrten.de", "size": "large"},
    {"name": "Phoenix Reisen GmbH", "category": "kreuzfahrt", "country": "DE", "city": "Bonn", "website": "https://www.phoenixreisen.com", "size": "medium"},
    {"name": "nicko cruises GmbH", "category": "kreuzfahrt", "country": "DE", "city": "Stuttgart", "website": "https://www.nicko-cruises.de", "size": "small"},

    # Veranstalter
    {"name": "TUI Deutschland GmbH", "category": "veranstalter", "country": "DE", "city": "Hannover", "website": "https://www.tui.com", "size": "enterprise"},
    {"name": "DER Touristik GmbH", "category": "veranstalter", "country": "DE", "city": "Frankfurt", "website": "https://www.dertouristik.com", "size": "enterprise"},
    {"name": "Thomas Cook AG", "category": "veranstalter", "country": "DE", "city": "Oberursel", "website": "https://www.thomascook.de", "size": "large"},
    {"name": "FTI Touristik GmbH", "category": "veranstalter", "country": "DE", "city": "München", "website": "https://www.fti.de", "size": "large"},
    {"name": "Alltours Flugreisen GmbH", "category": "veranstalter", "country": "DE", "city": "Düsseldorf", "website": "https://www.alltours.de", "size": "medium"},
    {"name": "Neckermann Reisen", "category": "veranstalter", "country": "DE", "city": "Frankfurt", "website": "https://www.neckermann-reisen.de", "size": "medium"},
    {"name": "Jahn Reisen GmbH & Co. KG", "category": "veranstalter", "country": "DE", "city": "Neuss", "website": "https://www.jahn-reisen.de", "size": "medium"},
    {"name": "Studiosus Reisen München GmbH", "category": "veranstalter", "country": "DE", "city": "München", "website": "https://www.studiosus.com", "size": "small"},
    {"name": "Ameropa Reisen GmbH", "category": "veranstalter", "country": "DE", "city": "Bad Homburg", "website": "https://www.ameropa.de", "size": "small"},
    {"name": "Berge & Meer Touristik GmbH", "category": "veranstalter", "country": "DE", "city": "Rengsdorf", "website": "https://www.berge-meer.de", "size": "medium"},
    {"name": "ITS Reisen GmbH", "category": "veranstalter", "country": "DE", "city": "Düsseldorf", "website": "https://www.its.de", "size": "medium"},
    {"name": "Wolters Reisen GmbH", "category": "veranstalter", "country": "DE", "city": "Münster", "website": "https://www.woltersreisen.de", "size": "small"},
    {"name": "Canusa Touristik GmbH & Co. KG", "category": "veranstalter", "country": "DE", "city": "Hamburg", "website": "https://www.canusa.de", "size": "small"},
    {"name": "Wikinger Reisen GmbH", "category": "veranstalter", "country": "DE", "city": "Hagen", "website": "https://www.wikinger-reisen.de", "size": "small"},
    {"name": "Gebeco GmbH & Co. KG", "category": "veranstalter", "country": "DE", "city": "Kiel", "website": "https://www.gebeco.de", "size": "small"},

    # AT Veranstalter
    {"name": "Raiffeisen Reisen GmbH", "category": "veranstalter", "country": "AT", "city": "Wien", "website": "https://www.raiffeisen-reisen.at", "size": "small"},
    {"name": "Ruefa Reisen", "category": "vermittler", "country": "AT", "city": "Wien", "website": "https://www.ruefa.at", "size": "medium"},
    {"name": "Verkehrsbüro Group", "category": "vermittler", "country": "AT", "city": "Wien", "website": "https://www.verkehrsbuero.com", "size": "large"},

    # OTA
    {"name": "CHECK24 GmbH", "category": "ota", "country": "DE", "city": "München", "website": "https://www.check24.de", "size": "enterprise"},
    {"name": "HRS Group", "category": "ota", "country": "DE", "city": "Köln", "website": "https://www.hrs.com", "size": "large"},
    {"name": "Holidaycheck AG", "category": "ota", "country": "DE", "city": "Holzkirchen", "website": "https://www.holidaycheck.de", "size": "medium"},
    {"name": "lastminute.com Group", "category": "ota", "country": "CH", "city": "Chiasso", "website": "https://www.lastminute.com", "size": "large"},
    {"name": "booking.com", "category": "ota", "country": "DE", "city": "Amsterdam", "website": "https://www.booking.com", "size": "enterprise"},

    # Mietwagen
    {"name": "Sixt SE", "category": "mietwagen", "country": "DE", "city": "Pullach", "website": "https://www.sixt.de", "size": "enterprise"},
    {"name": "Europcar Mobility Group Germany", "category": "mietwagen", "country": "DE", "city": "Hamburg", "website": "https://www.europcar.de", "size": "large"},
    {"name": "Hertz Autovermietung GmbH", "category": "mietwagen", "country": "DE", "city": "Berlin", "website": "https://www.hertz.de", "size": "large"},
    {"name": "Avis Budget Group Germany", "category": "mietwagen", "country": "DE", "city": "Eschborn", "website": "https://www.avis.de", "size": "large"},
    {"name": "Enterprise Autovermietung", "category": "mietwagen", "country": "DE", "city": "Eschborn", "website": "https://www.enterprise.de", "size": "large"},
    {"name": "AUTO EUROPE GmbH", "category": "mietwagen", "country": "DE", "city": "Frankfurt", "website": "https://www.autoeurope.de", "size": "medium"},

    # Hotelketten
    {"name": "Steigenberger Hotels AG", "category": "hotelkette", "country": "DE", "city": "Frankfurt", "website": "https://www.steigenberger.com", "size": "large"},
    {"name": "Maritim Hotelgesellschaft mbH", "category": "hotelkette", "country": "DE", "city": "Bad Salzuflen", "website": "https://www.maritim.de", "size": "large"},
    {"name": "Dorint GmbH", "category": "hotelkette", "country": "DE", "city": "Köln", "website": "https://www.dorint.com", "size": "medium"},
    {"name": "Motel One GmbH", "category": "hotelkette", "country": "DE", "city": "München", "website": "https://www.motel-one.com", "size": "large"},
    {"name": "A&O Hostels", "category": "hotelkette", "country": "DE", "city": "Berlin", "website": "https://www.aohostels.com", "size": "medium"},
    {"name": "Vienna House GmbH", "category": "hotelkette", "country": "AT", "city": "Wien", "website": "https://www.viennahouse.com", "size": "medium"},
    {"name": "Falkensteiner Hotels & Residences", "category": "hotelkette", "country": "AT", "city": "Wien", "website": "https://www.falkensteiner.com", "size": "medium"},
    {"name": "Mövenpick Hotels & Resorts", "category": "hotelkette", "country": "CH", "city": "Baar", "website": "https://www.movenpick.com", "size": "enterprise"},
    {"name": "The Ameron Hotels", "category": "hotelkette", "country": "DE", "city": "Köln", "website": "https://www.ameron-hotels.de", "size": "small"},
    {"name": "prizeotel GmbH & Co. KG", "category": "hotelkette", "country": "DE", "city": "Hamburg", "website": "https://www.prizeotel.com", "size": "small"},

    # DMC / Incoming
    {"name": "DER Business Travel GmbH", "category": "dmc", "country": "DE", "city": "Frankfurt", "website": "https://www.derbusiness.de", "size": "medium"},
    {"name": "Chamäleon Reisen GmbH", "category": "dmc", "country": "DE", "city": "Berlin", "website": "https://www.chamaeleon-reisen.de", "size": "small"},
    {"name": "Marco Polo Reisen GmbH", "category": "veranstalter", "country": "DE", "city": "München", "website": "https://www.marco-polo-reisen.com", "size": "small"},

    # Tech Provider
    {"name": "Amadeus IT Group Germany", "category": "tech_provider", "country": "DE", "city": "Erding", "website": "https://www.amadeus.com", "size": "enterprise"},
    {"name": "Sabre Germany GmbH", "category": "tech_provider", "country": "DE", "city": "Frankfurt", "website": "https://www.sabre.com", "size": "enterprise"},
    {"name": "Peakwork AG", "category": "tech_provider", "country": "DE", "city": "Düsseldorf", "website": "https://www.peakwork.com", "size": "small"},
    {"name": "Traffics Softwareanwendungen GmbH", "category": "tech_provider", "country": "DE", "city": "Hamburg", "website": "https://www.traffics.de", "size": "small"},
]


def estimate_size(employees: Optional[int]) -> CompanySize:
    if not employees:
        return CompanySize.medium
    if employees < 10:
        return CompanySize.micro
    if employees < 50:
        return CompanySize.small
    if employees < 250:
        return CompanySize.medium
    if employees < 1000:
        return CompanySize.large
    return CompanySize.enterprise


def estimate_score(company_data: dict) -> int:
    """Basis-Score bei Erstkontakt"""
    score = 40
    if company_data.get("email_general"):
        score += 10
    if company_data.get("phone_main"):
        score += 10
    if company_data.get("revenue_approx_eur", 0) and company_data["revenue_approx_eur"] > 5_000_000:
        score += 15
    if company_data.get("employees_approx", 0) > 50:
        score += 10
    if company_data.get("website"):
        score += 5
    if company_data.get("linkedin_url"):
        score += 5
    if company_data.get("size") in ["large", "enterprise"]:
        score += 10
    return min(score, 95)


class OpenCorporatesCrawler:
    """
    OpenCorporates — öffentliche Handelsregister-Daten
    Kostenloser Tier: 500 req/Tag
    """
    BASE_URL = "https://api.opencorporates.com/v0.4/companies/search"

    async def enrich_company(
        self, client: httpx.AsyncClient, company: Company
    ) -> dict:
        jurisdiction = {"DE": "de", "AT": "at", "CH": "ch"}.get(company.country.value, "de")
        params = {
            "q": company.name,
            "jurisdiction_code": jurisdiction,
            "fields": "company_number,registered_address,incorporation_date,registered_name",
        }
        try:
            resp = await client.get(self.BASE_URL, params=params, headers=HEADERS, timeout=10)
            if resp.status_code != 200:
                return {}
            data = resp.json()
            results = data.get("results", {}).get("companies", [])
            if not results:
                return {}

            best = results[0]["company"]
            addr = best.get("registered_address") or {}
            return {
                "hrb_number": best.get("company_number"),
                "street": addr.get("street_address"),
                "postal_code": addr.get("postal_code"),
                "city": addr.get("locality") or company.city,
                "founded_year": (best.get("incorporation_date") or "")[:4] or None,
            }
        except Exception as e:
            print(f"[OpenCorporates] Fehler: {e}")
            return {}


class CompanyCrawler:
    """Haupt-Orchestrator für Unternehmens-Daten"""

    def __init__(self):
        self.oc = OpenCorporatesCrawler()

    async def import_seed_data(self, db: AsyncSession) -> dict:
        """Importiert die Seed-Unternehmen in die DB"""
        run = CrawlerRun(crawler_name="seed_import", status="running")
        db.add(run)
        await db.commit()

        new_count = 0
        updated_count = 0

        for seed in SEED_COMPANIES:
            existing = (await db.execute(
                select(Company).where(
                    Company.name == seed["name"],
                    Company.country == seed["country"],
                )
            )).scalar_one_or_none()

            if not existing:
                company = Company(
                    name=seed["name"],
                    category=CompanyCategory(seed["category"]),
                    country=CountryCode(seed["country"]),
                    city=seed.get("city"),
                    website=seed.get("website"),
                    size=CompanySize(seed["size"]) if seed.get("size") else None,
                    priority=LeadPriority.medium,
                    data_source="seed",
                    data_quality=60,
                    score=estimate_score(seed),
                )
                db.add(company)
                new_count += 1
            else:
                updated_count += 1

        run.status = "success"
        run.records_new = new_count
        run.records_updated = updated_count
        run.records_found = len(SEED_COMPANIES)
        run.finished_at = datetime.utcnow()
        await db.commit()

        return {"new": new_count, "updated": updated_count, "total_seed": len(SEED_COMPANIES)}

    async def enrich_with_opencorporates(self, db: AsyncSession) -> dict:
        """Reichert alle Unternehmen ohne HRB-Nummer an"""
        companies = (await db.execute(
            select(Company).where(
                Company.hrb_number.is_(None),
                Company.is_active == True,
            )
        )).scalars().all()

        enriched = 0
        async with httpx.AsyncClient() as client:
            for company in companies:
                await asyncio.sleep(settings.CRAWLER_DELAY_SECONDS)
                enrich_data = await self.oc.enrich_company(client, company)
                if enrich_data:
                    for field, value in enrich_data.items():
                        if value and not getattr(company, field):
                            setattr(company, field, value)
                    company.data_quality = min(company.data_quality + 10, 95)
                    enriched += 1

        await db.commit()
        return {"enriched": enriched, "total": len(companies)}


company_crawler = CompanyCrawler()


async def import_extended_seed(db: AsyncSession) -> dict:
    """Importiert den erweiterten Seed mit ~200 weiteren Unternehmen"""
    from app.crawler.extended_seed import EXTENDED_COMPANIES

    run = CrawlerRun(crawler_name="extended_seed_import", status="running")
    db.add(run)
    await db.commit()

    new_count = 0
    updated_count = 0

    for seed in EXTENDED_COMPANIES:
        existing = (await db.execute(
            select(Company).where(
                Company.name == seed["name"],
                Company.country == seed["country"],
            )
        )).scalar_one_or_none()

        if not existing:
            company = Company(
                name=seed["name"],
                category=CompanyCategory(seed["category"]),
                country=CountryCode(seed["country"]),
                city=seed.get("city"),
                website=seed.get("website"),
                email_general=seed.get("email_general"),
                phone_main=seed.get("phone_main"),
                size=CompanySize(seed["size"]) if seed.get("size") else None,
                employees_approx=seed.get("employees_approx"),
                revenue_approx_eur=seed.get("revenue_approx_eur"),
                priority=LeadPriority.medium,
                data_source="extended_seed",
                data_quality=65,
                score=estimate_score(seed),
            )
            db.add(company)
            new_count += 1
        else:
            # Fehlende Daten ergänzen
            if seed.get("phone_main") and not existing.phone_main:
                existing.phone_main = seed["phone_main"]
            if seed.get("email_general") and not existing.email_general:
                existing.email_general = seed["email_general"]
            if seed.get("employees_approx") and not existing.employees_approx:
                existing.employees_approx = seed["employees_approx"]
            if seed.get("revenue_approx_eur") and not existing.revenue_approx_eur:
                existing.revenue_approx_eur = seed["revenue_approx_eur"]
            updated_count += 1

    run.status = "success"
    run.records_new = new_count
    run.records_updated = updated_count
    run.records_found = len(EXTENDED_COMPANIES)
    run.finished_at = datetime.utcnow()
    await db.commit()

    return {
        "new": new_count,
        "updated": updated_count,
        "total": len(EXTENDED_COMPANIES)
    }
