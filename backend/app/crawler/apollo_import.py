"""
Apollo.io People Import v2
Speichert Vorname + Funktion + LinkedIn auch ohne volle Nachnamen.
"""
import asyncio
import httpx
from datetime import datetime
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, and_

from app.models.models import Company, Contact, ContactDepartment, CrawlerRun
from app.core.config import settings

TARGET_TITLES = [
    "CEO", "COO", "CMO", "CSO", "Geschäftsführer", "Managing Director",
    "Head of Sales", "VP Sales", "Sales Director", "Vertriebsleiter",
    "Head of Operations", "Operations Manager",
    "Head of Customer Service", "Customer Service Manager",
    "Director", "General Manager",
]

DEPT_MAP = {
    "executive": ContactDepartment.geschaeftsfuehrung,
    "sales": ContactDepartment.sales,
    "operations": ContactDepartment.operations,
    "customer_success": ContactDepartment.customer_service,
    "customer_service": ContactDepartment.customer_service,
    "marketing": ContactDepartment.marketing,
    "human_resources": ContactDepartment.hr,
    "finance": ContactDepartment.finance,
}


def infer_dept(title: str) -> ContactDepartment:
    t = title.lower()
    if any(k in t for k in ["ceo","coo","geschäftsführ","managing director","vorstand","general manager"]):
        return ContactDepartment.geschaeftsfuehrung
    if any(k in t for k in ["sales","vertrieb","account manager","business development"]):
        return ContactDepartment.sales
    if any(k in t for k in ["operation","yield","revenue management"]):
        return ContactDepartment.operations
    if any(k in t for k in ["customer","service","support","kundendienst"]):
        return ContactDepartment.customer_service
    if any(k in t for k in ["marketing","brand","kommunikation"]):
        return ContactDepartment.marketing
    return ContactDepartment.management


def is_decision_maker(title: str, seniority: str) -> bool:
    t = title.lower()
    s = seniority.lower()
    if s in {"c_suite", "vp", "director", "owner", "founder", "partner"}:
        return True
    if any(k in t for k in ["ceo","coo","cmo","head of","director","leiter","vp ","vice president","geschäftsführ"]):
        return True
    return False


async def fetch_people_for_company(client, company, max_people=5):
    if not settings.APOLLO_API_KEY:
        return []

    domain = None
    if company.website:
        domain = (company.website
                  .replace("https://","").replace("http://","")
                  .replace("www.","").split("/")[0])

    payload = {
        "q_organization_name": company.name,
        "page": 1,
        "per_page": max_people,
    }
    # Domain-Filter deaktiviert — verringert Treffer zu stark

    try:
        resp = await client.post(
            "https://api.apollo.io/api/v1/mixed_people/api_search",
            json=payload,
            headers={
                "Content-Type": "application/json",
                "X-Api-Key": settings.APOLLO_API_KEY,
            },
            timeout=15,
        )
        if resp.status_code != 200:
            print(f"[Apollo] {resp.status_code} für {company.name}: {resp.text[:100]}")
            return []

        data = resp.json()
        people = data.get("people", [])
        result = []

        for p in people:
            title = (p.get("title") or "")

            # Nachname: voll oder obfuskiert
            last_name = p.get("last_name") or p.get("last_name_obfuscated") or "—"

            # Department
            dept_raw = (p.get("departments") or [""])[0].lower()
            dept = DEPT_MAP.get(dept_raw, infer_dept(title))
            seniority = (p.get("seniority") or "")
            is_dm = is_decision_maker(title, seniority)

            # Email
            email = p.get("email")
            if not email:
                for ec in p.get("email_statuses", []):
                    if ec.get("email") and ec.get("deliverability") != "undeliverable":
                        email = ec["email"]
                        break

            result.append({
                "first_name": p.get("first_name"),
                "last_name": last_name,
                "job_title": title[:255],
                "department": dept,
                "seniority": seniority,
                "is_decision_maker": is_dm,
                "email": email,
                "email_verified": bool(email and "*" not in email),
                "linkedin_url": p.get("linkedin_url"),
                "phone_direct": (p.get("phone_numbers") or [{}])[0].get("sanitized_number"),
                "source": "apollo",
                "is_current_employee": True,
            })

        print(f"[Apollo] {company.name}: {len(result)} Personen gefunden")
        return result

    except Exception as e:
        print(f"[Apollo] Fehler bei {company.name}: {e}")
        return []


async def run_people_import(db: AsyncSession) -> dict:
    run = CrawlerRun(crawler_name="apollo_people_import", status="running")
    db.add(run)
    await db.commit()

    companies = (await db.execute(
        select(Company).where(Company.is_active == True)
        .order_by(Company.score.desc())
    )).scalars().all()

    total_new = 0
    total_companies = 0
    errors = 0

    async with httpx.AsyncClient() as client:
        for company in companies:
            try:
                existing_count = (await db.execute(
                    select(func.count()).where(Contact.company_id == company.id)
                )).scalar_one()

                if existing_count >= 3:
                    continue

                people = await fetch_people_for_company(client, company, max_people=5)

                for person in people:
                    existing = (await db.execute(
                        select(Contact).where(and_(
                            Contact.company_id == company.id,
                            Contact.first_name == person["first_name"],
                            Contact.job_title == person["job_title"],
                        ))
                    )).scalar_one_or_none()

                    if not existing:
                        db.add(Contact(
                            company_id=company.id,
                            last_crawled_at=datetime.utcnow(),
                            **person,
                        ))
                        total_new += 1

                if people:
                    total_companies += 1
                    await db.commit()

                await asyncio.sleep(1)

            except Exception as e:
                errors += 1
                print(f"[Apollo] Fehler {company.name}: {e}")

    run.status = "success" if errors == 0 else "partial"
    run.records_new = total_new
    run.records_found = total_companies
    run.finished_at = datetime.utcnow()
    run.meta = {"errors": errors}
    await db.commit()

    return {"companies_enriched": total_companies, "contacts_added": total_new, "errors": errors}
