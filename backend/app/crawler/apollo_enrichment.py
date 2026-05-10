"""
Apollo Contact Enrichment
Nutzt die people/match API um volle Kontaktdaten zu laden.
Braucht die Apollo Person-ID die wir beim Import gespeichert haben.

Problem: Wir haben die Apollo IDs nicht gespeichert beim Import.
Lösung: Wir suchen jeden Kontakt neu per Name + Firma und holen dann die vollen Daten.
"""
import asyncio
import httpx
from datetime import datetime
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.models import Company, Contact, CrawlerRun
from app.core.config import settings


async def enrich_contact(client: httpx.AsyncClient, contact: Contact, company: Company) -> dict:
    """Holt volle Kontaktdaten für einen Kontakt via Apollo people/match"""
    if not settings.APOLLO_API_KEY:
        return {}

    # Schritt 1: Person-ID finden via Search
    search_payload = {
        "q_organization_name": company.name,
        "q_person_name": contact.first_name or "",
        "per_page": 5,
    }

    try:
        resp = await client.post(
            "https://api.apollo.io/api/v1/mixed_people/api_search",
            json=search_payload,
            headers={"Content-Type": "application/json", "X-Api-Key": settings.APOLLO_API_KEY},
            timeout=15,
        )
        if resp.status_code != 200:
            return {}

        people = resp.json().get("people", [])
        
        # Passenden Eintrag finden
        person_id = None
        for p in people:
            if (p.get("first_name", "").lower() == (contact.first_name or "").lower() and
                (p.get("title") or "").lower() == (contact.job_title or "").lower()):
                person_id = p.get("id")
                break
        
        # Fallback: ersten nehmen wenn Vorname passt
        if not person_id:
            for p in people:
                if p.get("first_name", "").lower() == (contact.first_name or "").lower():
                    person_id = p.get("id")
                    break

        if not person_id:
            return {}

        await asyncio.sleep(0.5)

        # Schritt 2: Volle Daten via people/match holen
        match_resp = await client.post(
            "https://api.apollo.io/api/v1/people/match",
            json={"id": person_id, "reveal_personal_emails": True},
            headers={"Content-Type": "application/json", "X-Api-Key": settings.APOLLO_API_KEY},
            timeout=15,
        )
        if match_resp.status_code != 200:
            return {}

        person = match_resp.json().get("person", {})
        if not person:
            return {}

        # Telefon extrahieren
        phone = None
        phone_numbers = person.get("phone_numbers", [])
        if phone_numbers:
            phone = phone_numbers[0].get("sanitized_number")
        if not phone:
            org = person.get("organization", {})
            primary = org.get("primary_phone", {})
            phone = primary.get("sanitized_number") if primary else None

        return {
            "first_name": person.get("first_name"),
            "last_name": person.get("last_name"),
            "email": person.get("email"),
            "email_verified": person.get("email_status") == "verified",
            "phone_direct": phone,
            "linkedin_url": person.get("linkedin_url"),
        }

    except Exception as e:
        print(f"[Enrichment] Fehler bei {contact.first_name}: {e}")
        return {}


async def run_contact_enrichment(db: AsyncSession) -> dict:
    """Reichert alle Kontakte ohne E-Mail an"""
    run = CrawlerRun(crawler_name="apollo_contact_enrichment", status="running")
    db.add(run)
    await db.commit()

    # Alle Kontakte ohne E-Mail
    contacts = (await db.execute(
        select(Contact).where(
            Contact.email.is_(None),
            Contact.is_current_employee == True,
            Contact.source == "apollo",
        ).limit(200)  # Max 200 pro Lauf (Credits schonen)
    )).scalars().all()

    # Firmen-Index
    company_ids = list(set(c.company_id for c in contacts))
    companies_result = await db.execute(
        select(Company).where(Company.id.in_(company_ids))
    )
    companies = {c.id: c for c in companies_result.scalars().all()}

    enriched = 0
    errors = 0

    async with httpx.AsyncClient() as client:
        for contact in contacts:
            company = companies.get(contact.company_id)
            if not company:
                continue

            try:
                data = await enrich_contact(client, contact, company)
                if data:
                    if data.get("last_name"):
                        contact.last_name = data["last_name"]
                    if data.get("email"):
                        contact.email = data["email"]
                        contact.email_verified = data.get("email_verified", False)
                    if data.get("phone_direct"):
                        contact.phone_direct = data["phone_direct"]
                    if data.get("linkedin_url"):
                        contact.linkedin_url = data["linkedin_url"]
                    contact.last_crawled_at = datetime.utcnow()
                    enriched += 1
                    print(f"[Enrichment] {contact.first_name} {contact.last_name}: E-Mail={data.get('email')}")
                
                await db.commit()
                await asyncio.sleep(1)  # Rate-Limit

            except Exception as e:
                errors += 1
                print(f"[Enrichment] Fehler: {e}")

    run.status = "success" if errors == 0 else "partial"
    run.records_found = len(contacts)
    run.records_updated = enriched
    run.finished_at = datetime.utcnow()
    run.meta = {"errors": errors, "enriched": enriched}
    await db.commit()

    return {"total": len(contacts), "enriched": enriched, "errors": errors}
