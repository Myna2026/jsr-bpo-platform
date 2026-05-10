"""
Export API — CSV und Excel Export für Lead-Listen
"""
import io
import csv
from typing import Optional, List
from fastapi import APIRouter, Depends, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.db.session import get_db
from app.models.models import Company, Contact, CompanyCategory, CountryCode, LeadPriority, LeadStatus

router = APIRouter()


def format_revenue(val: Optional[int]) -> str:
    if not val:
        return ""
    if val >= 1_000_000_000:
        return f"{val/1_000_000_000:.1f} Mrd €"
    if val >= 1_000_000:
        return f"{val/1_000_000:.1f} Mio €"
    return f"{val:,} €"


@router.get("/companies/csv")
async def export_companies_csv(
    country: Optional[List[CountryCode]] = Query(None),
    category: Optional[List[CompanyCategory]] = Query(None),
    priority: Optional[List[LeadPriority]] = Query(None),
    status: Optional[List[LeadStatus]] = Query(None),
    include_contacts: bool = Query(False),
    db: AsyncSession = Depends(get_db),
):
    """Exportiert Lead-Liste als CSV — filterbar"""
    query = select(Company).where(Company.is_active == True)
    if country:
        query = query.where(Company.country.in_(country))
    if category:
        query = query.where(Company.category.in_(category))
    if priority:
        query = query.where(Company.priority.in_(priority))
    if status:
        query = query.where(Company.status.in_(status))

    companies = (await db.execute(query.order_by(Company.score.desc()))).scalars().all()

    output = io.StringIO()
    writer = csv.writer(output, delimiter=";", quoting=csv.QUOTE_ALL)

    # Header
    headers = [
        "Name", "Kategorie", "Land", "Stadt", "PLZ", "Adresse",
        "Größe", "Mitarbeiter ca.", "Umsatz ca.", "Umsatzquelle",
        "Website", "E-Mail allgemein", "E-Mail Sales", "Telefon", "Telefon Sales",
        "LinkedIn", "Xing", "Priorität", "Status", "Score",
        "Offene Stellen", "Anzahl Stellen", "Tags", "Notizen",
        "Gegründet", "Rechtsform", "HRB-Nr",
    ]
    if include_contacts:
        headers += ["Kontakt Name", "Kontakt Funktion", "Kontakt E-Mail", "Kontakt Telefon", "Kontakt LinkedIn"]

    writer.writerow(headers)

    for c in companies:
        row = [
            c.name,
            c.category.value,
            c.country.value,
            c.city or "",
            c.postal_code or "",
            c.address_full or "",
            c.size.value if c.size else "",
            c.employees_approx or "",
            format_revenue(c.revenue_approx_eur),
            c.revenue_source or "",
            c.website or "",
            c.email_general or "",
            c.email_sales or "",
            c.phone_main or "",
            c.phone_sales or "",
            c.linkedin_url or "",
            c.xing_url or "",
            c.priority.value,
            c.status.value,
            c.score,
            "Ja" if c.has_open_jobs else "Nein",
            c.open_jobs_count or 0,
            ", ".join(c.tags) if c.tags else "",
            c.notes or "",
            c.founded_year or "",
            c.legal_form or "",
            c.hrb_number or "",
        ]

        if include_contacts:
            # Alle Entscheider des Unternehmens anhängen
            contacts = (await db.execute(
                select(Contact).where(
                    Contact.company_id == c.id,
                    Contact.is_current_employee == True,
                    Contact.do_not_contact == False,
                )
            )).scalars().all()

            if contacts:
                for contact in contacts:
                    writer.writerow(row + [
                        contact.full_name,
                        contact.job_title or "",
                        contact.email or "",
                        contact.phone_direct or contact.phone_mobile or "",
                        contact.linkedin_url or "",
                    ])
            else:
                writer.writerow(row + ["", "", "", "", ""])
        else:
            writer.writerow(row)

    output.seek(0)
    filename = f"tourism_leads_{len(companies)}_unternehmen.csv"

    return StreamingResponse(
        iter([output.getvalue()]),
        media_type="text/csv; charset=utf-8-sig",  # utf-8-sig für Excel-Kompatibilität
        headers={"Content-Disposition": f"attachment; filename={filename}"},
    )
