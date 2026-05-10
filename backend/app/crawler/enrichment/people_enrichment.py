"""
People Enrichment Service
Kombiniert Apollo.io, Hunter.io und Proxycurl für Mitarbeiter-Daten.

Rechtlich korrekt: alle drei APIs sammeln nur Business-Kontext-Daten
(Firmen-E-Mail, Berufsbezeichnung, LinkedIn Business-Profil).
Kein Scraping privater Profile.

Kosten ca.:
  Apollo.io Basic: $49/mo → 10.000 Kontakte/mo
  Hunter.io Starter: $49/mo → 500 Verifikationen/mo
  Proxycurl: pay-as-you-go ~$0.01/Profil
"""
import asyncio
import httpx
from typing import Optional
from datetime import datetime

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_

from app.models.models import Company, Contact, ContactDepartment, CrawlerRun
from app.core.config import settings


DEPARTMENT_MAPPING = {
    # Apollo department strings → unsere ContactDepartment Enum
    "executive": ContactDepartment.geschaeftsfuehrung,
    "c_suite": ContactDepartment.geschaeftsfuehrung,
    "founder": ContactDepartment.geschaeftsfuehrung,
    "sales": ContactDepartment.sales,
    "business_development": ContactDepartment.sales,
    "marketing": ContactDepartment.marketing,
    "operations": ContactDepartment.operations,
    "customer_success": ContactDepartment.customer_service,
    "customer_service": ContactDepartment.customer_service,
    "support": ContactDepartment.customer_service,
    "finance": ContactDepartment.finance,
    "human_resources": ContactDepartment.hr,
    "engineering": ContactDepartment.it,
    "information_technology": ContactDepartment.it,
    "purchasing": ContactDepartment.procurement,
}

SENIORITY_DECISION_MAKERS = {
    "c_suite", "vp", "director", "partner", "manager", "owner", "founder"
}

# Abteilungen die für unser Call Center relevant sind
RELEVANT_DEPARTMENTS = {
    "executive", "c_suite", "founder", "sales", "business_development",
    "marketing", "operations", "customer_success", "customer_service",
}


class ApolloEnrichment:
    """
    Apollo.io People Search API
    Docs: https://apolloio.github.io/apollo-api-docs/
    """
    BASE_URL = "https://api.apollo.io/v1"

    def __init__(self):
        self.api_key = settings.APOLLO_API_KEY

    async def search_people(
        self,
        client: httpx.AsyncClient,
        company_name: str,
        company_domain: Optional[str] = None,
        max_results: int = 25,
    ) -> list[dict]:
        """Sucht Mitarbeiter eines Unternehmens"""
        if not self.api_key:
            print("[Apollo] Kein API-Key konfiguriert — übersprungen")
            return []

        payload = {
            "api_key": self.api_key,
            "q_organization_name": company_name,
            "page": 1,
            "per_page": max_results,
            "person_titles": [
                "CEO", "COO", "CMO", "CSO", "CTO",
                "Managing Director", "Geschäftsführer",
                "Head of Sales", "VP Sales", "Sales Director",
                "Head of Operations", "Operations Manager",
                "Head of Customer Service", "Customer Service Manager",
                "Director", "Leiter", "Head of",
            ],
            # Nur DACH
            "person_locations": ["Germany", "Austria", "Switzerland"],
        }

        if company_domain:
            payload["q_organization_domains"] = [company_domain]

        try:
            resp = await client.post(
                f"{self.BASE_URL}/mixed_people/search",
                json=payload,
                headers={"Content-Type": "application/json"},
                timeout=15,
            )
            if resp.status_code == 402:
                print("[Apollo] Rate Limit / Credits erschöpft")
                return []
            resp.raise_for_status()
            data = resp.json()
            return self._parse_people(data.get("people", []))
        except Exception as e:
            print(f"[Apollo] Fehler: {e}")
            return []

    def _parse_people(self, people: list) -> list[dict]:
        results = []
        for p in people:
            department_raw = (p.get("departments") or ["sonstiges"])[0].lower()
            department = DEPARTMENT_MAPPING.get(department_raw, ContactDepartment.sonstiges)

            seniority = (p.get("seniority") or "").lower()
            is_decision_maker = seniority in SENIORITY_DECISION_MAKERS

            # Nur relevante Abteilungen
            if department_raw not in RELEVANT_DEPARTMENTS and not is_decision_maker:
                continue

            # E-Mail extrahieren
            email = None
            for ec in p.get("email_statuses", []):
                if ec.get("email") and ec.get("deliverability") != "undeliverable":
                    email = ec["email"]
                    break
            if not email and p.get("email"):
                email = p["email"]

            results.append({
                "first_name": p.get("first_name"),
                "last_name": p.get("last_name") or "Unbekannt",
                "job_title": (p.get("title") or "")[:255],
                "department": department,
                "seniority": seniority,
                "is_decision_maker": is_decision_maker,
                "email": email,
                "email_verified": bool(email),
                "linkedin_url": p.get("linkedin_url"),
                "phone_direct": p.get("phone_numbers", [{}])[0].get("sanitized_number") if p.get("phone_numbers") else None,
                "source": "apollo",
            })
        return results


class HunterEnrichment:
    """
    Hunter.io Domain Search + Email Verifier
    Findet Firmen-E-Mails und verifiziert sie.
    """
    BASE_URL = "https://api.hunter.io/v2"

    def __init__(self):
        self.api_key = settings.HUNTER_API_KEY

    async def find_company_emails(
        self,
        client: httpx.AsyncClient,
        domain: str,
        limit: int = 10,
    ) -> list[dict]:
        if not self.api_key or not domain:
            return []

        # Domain aus URL extrahieren
        domain = domain.replace("https://", "").replace("http://", "").replace("www.", "").split("/")[0]

        try:
            resp = await client.get(
                f"{self.BASE_URL}/domain-search",
                params={
                    "domain": domain,
                    "api_key": self.api_key,
                    "limit": limit,
                    "type": "personal",
                },
                timeout=10,
            )
            if resp.status_code != 200:
                return []
            data = resp.json()
            return self._parse(data.get("data", {}).get("emails", []))
        except Exception as e:
            print(f"[Hunter] Fehler für {domain}: {e}")
            return []

    def _parse(self, emails: list) -> list[dict]:
        results = []
        for e in emails:
            confidence = e.get("confidence", 0)
            if confidence < 70:
                continue
            first = e.get("first_name", "")
            last = e.get("last_name", "")
            position = e.get("position", "")
            seniority = e.get("seniority", "").lower()

            # Abteilung raten aus Positionsbezeichnung
            dept = ContactDepartment.sonstiges
            pos_lower = position.lower()
            if any(k in pos_lower for k in ["geschäftsführ", "ceo", "managing", "director general"]):
                dept = ContactDepartment.geschaeftsfuehrung
            elif any(k in pos_lower for k in ["sales", "vertrieb", "account"]):
                dept = ContactDepartment.sales
            elif any(k in pos_lower for k in ["marketing", "kommunikation"]):
                dept = ContactDepartment.marketing
            elif any(k in pos_lower for k in ["operation", "betrieb"]):
                dept = ContactDepartment.operations
            elif any(k in pos_lower for k in ["customer", "service", "support"]):
                dept = ContactDepartment.customer_service

            results.append({
                "first_name": first or None,
                "last_name": last or "Unbekannt",
                "job_title": position[:255] if position else None,
                "department": dept,
                "seniority": seniority,
                "is_decision_maker": seniority in {"senior", "executive", "director"},
                "email": e.get("value"),
                "email_verified": confidence >= 85,
                "source": "hunter",
                "linkedin_url": e.get("linkedin", None),
                "phone_direct": None,
            })
        return results

    async def verify_email(self, client: httpx.AsyncClient, email: str) -> bool:
        if not self.api_key:
            return False
        try:
            resp = await client.get(
                f"{self.BASE_URL}/email-verifier",
                params={"email": email, "api_key": self.api_key},
                timeout=10,
            )
            data = resp.json()
            return data.get("data", {}).get("result") == "deliverable"
        except Exception:
            return False


class ProxycurlEnrichment:
    """
    Proxycurl — LinkedIn Profile Enrichment (legal, über offizielle API)
    Kosten: ~$0.01 pro Profil
    Docs: https://nubela.co/proxycurl/docs
    """
    BASE_URL = "https://nubela.co/proxycurl/api"

    def __init__(self):
        self.api_key = settings.PROXYCURL_API_KEY

    async def get_company_employees(
        self,
        client: httpx.AsyncClient,
        linkedin_company_url: str,
        max_results: int = 20,
    ) -> list[dict]:
        if not self.api_key or not linkedin_company_url:
            return []

        try:
            resp = await client.get(
                f"{self.BASE_URL}/linkedin/company/employees/",
                params={
                    "linkedin_company_profile_url": linkedin_company_url,
                    "type": "personal",
                    "enrich_profiles": "enrich",
                    "role_search": "manager OR director OR head OR leiter OR VP OR CEO OR COO",
                    "page_size": max_results,
                },
                headers={"Authorization": f"Bearer {self.api_key}"},
                timeout=30,
            )
            if resp.status_code != 200:
                return []
            data = resp.json()
            return self._parse(data.get("employees", []))
        except Exception as e:
            print(f"[Proxycurl] Fehler: {e}")
            return []

    def _parse(self, employees: list) -> list[dict]:
        results = []
        for emp in employees:
            profile = emp.get("profile", {})
            experiences = profile.get("experiences", [])
            current_exp = next(
                (e for e in experiences if not e.get("ends_at")), {}
            )

            title = current_exp.get("title", profile.get("headline", ""))
            dept = self._infer_department(title)

            results.append({
                "first_name": profile.get("first_name"),
                "last_name": profile.get("last_name") or "Unbekannt",
                "job_title": title[:255] if title else None,
                "department": dept,
                "seniority": None,
                "is_decision_maker": any(
                    kw in title.lower() for kw in
                    ["ceo", "coo", "cmo", "cso", "head", "director", "leiter", "vp", "geschäftsführer"]
                ) if title else False,
                "email": None,  # Proxycurl gibt keine E-Mails direkt
                "email_verified": False,
                "linkedin_url": f"https://linkedin.com/in/{profile.get('public_identifier', '')}",
                "phone_direct": None,
                "source": "proxycurl",
            })
        return results

    def _infer_department(self, title: str) -> ContactDepartment:
        if not title:
            return ContactDepartment.sonstiges
        t = title.lower()
        if any(k in t for k in ["ceo", "coo", "geschäftsführ", "managing director", "vorstand"]):
            return ContactDepartment.geschaeftsfuehrung
        if any(k in t for k in ["sales", "vertrieb", "account manager", "business development"]):
            return ContactDepartment.sales
        if any(k in t for k in ["marketing", "brand", "communications"]):
            return ContactDepartment.marketing
        if any(k in t for k in ["operation", "yield", "revenue management"]):
            return ContactDepartment.operations
        if any(k in t for k in ["customer", "service", "support", "kundendienst"]):
            return ContactDepartment.customer_service
        if any(k in t for k in ["finance", "controlling", "cfo", "finanzen"]):
            return ContactDepartment.finance
        return ContactDepartment.sonstiges


# ── Orchestrator ─────────────────────────────────────────────

class PeopleEnrichmentService:
    """
    Kombiniert alle drei APIs für maximale Abdeckung.
    Strategie: Apollo zuerst (breiteste Abdeckung), dann Hunter für E-Mails,
    Proxycurl für LinkedIn-verifizierte Kontakte.
    Dedup via Nachname + Vorname.
    """

    def __init__(self):
        self.apollo = ApolloEnrichment()
        self.hunter = HunterEnrichment()
        self.proxycurl = ProxycurlEnrichment()

    async def enrich_company(self, db: AsyncSession, company: Company) -> dict:
        """Reichert ein Unternehmen mit Mitarbeiter-Daten an"""
        new_count = 0
        updated_count = 0

        async with httpx.AsyncClient() as client:
            people = []

            # 1. Apollo.io — bester Startpunkt
            domain = self._extract_domain(company.website)
            apollo_people = await self.apollo.search_people(
                client, company.name, domain
            )
            people.extend(apollo_people)
            await asyncio.sleep(1)

            # 2. Hunter.io — zusätzliche E-Mails
            if domain:
                hunter_people = await self.hunter.find_company_emails(client, domain)
                people.extend(hunter_people)
                await asyncio.sleep(1)

            # 3. Proxycurl — wenn LinkedIn-URL vorhanden
            if company.linkedin_url:
                px_people = await self.proxycurl.get_company_employees(
                    client, company.linkedin_url
                )
                people.extend(px_people)

            # Dedup + in DB schreiben
            seen_names = set()
            for person in people:
                key = f"{(person.get('first_name') or '').lower()}:{person['last_name'].lower()}"
                if key in seen_names:
                    continue
                seen_names.add(key)

                # Bereits in DB?
                existing = (await db.execute(
                    select(Contact).where(
                        and_(
                            Contact.company_id == company.id,
                            Contact.last_name == person["last_name"],
                        )
                    )
                )).scalar_one_or_none()

                if existing:
                    # Update wenn neue Daten vorhanden
                    if person.get("email") and not existing.email:
                        existing.email = person["email"]
                        existing.email_verified = person["email_verified"]
                    if person.get("linkedin_url") and not existing.linkedin_url:
                        existing.linkedin_url = person["linkedin_url"]
                    existing.last_crawled_at = datetime.utcnow()
                    updated_count += 1
                else:
                    contact = Contact(
                        company_id=company.id,
                        last_crawled_at=datetime.utcnow(),
                        **{k: v for k, v in person.items() if v is not None},
                    )
                    db.add(contact)
                    new_count += 1

        await db.commit()
        return {"new": new_count, "updated": updated_count}

    async def enrich_all_companies(self, db: AsyncSession) -> dict:
        """Reichert alle Unternehmen an — für Celery Weekly Task"""
        run = CrawlerRun(crawler_name="people_enrichment", status="running")
        db.add(run)
        await db.commit()

        companies = (await db.execute(
            select(Company).where(Company.is_active == True)
        )).scalars().all()

        total_new = 0
        total_updated = 0
        errors = 0

        for company in companies:
            try:
                result = await self.enrich_company(db, company)
                total_new += result["new"]
                total_updated += result["updated"]
                run.records_found += 1
                await asyncio.sleep(2)  # Rate-Limit respektieren
            except Exception as e:
                errors += 1
                print(f"[PeopleEnrichment] Fehler bei {company.name}: {e}")

        run.status = "success" if errors == 0 else "partial"
        run.records_new = total_new
        run.records_updated = total_updated
        run.finished_at = datetime.utcnow()
        run.meta = {"errors": errors}
        await db.commit()

        return {"new": total_new, "updated": total_updated, "errors": errors}

    def _extract_domain(self, website: Optional[str]) -> Optional[str]:
        if not website:
            return None
        return (website
                .replace("https://", "")
                .replace("http://", "")
                .replace("www.", "")
                .split("/")[0])


# Singleton
people_enrichment = PeopleEnrichmentService()
