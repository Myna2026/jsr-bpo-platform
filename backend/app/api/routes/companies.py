"""
Companies API — Filter, Paginierung, CRUD, Scoring
"""
from uuid import UUID
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, or_, and_
from pydantic import BaseModel, Field
from datetime import datetime

from app.db.session import get_db
from app.models.models import (
    Company, Contact, CrmActivity,
    CompanyCategory, CompanySize, CountryCode, LeadPriority, LeadStatus
)

router = APIRouter()


# ── Pydantic Schemas ────────────────────────────────────────

class CompanyCreate(BaseModel):
    name: str
    category: CompanyCategory
    country: CountryCode
    legal_form: Optional[str] = None
    brand_names: Optional[List[str]] = None
    tags: Optional[List[str]] = None
    subcategory: Optional[str] = None
    state: Optional[str] = None
    city: Optional[str] = None
    postal_code: Optional[str] = None
    street: Optional[str] = None
    address_full: Optional[str] = None
    website: Optional[str] = None
    email_general: Optional[str] = None
    email_sales: Optional[str] = None
    phone_main: Optional[str] = None
    phone_sales: Optional[str] = None
    linkedin_url: Optional[str] = None
    xing_url: Optional[str] = None
    size: Optional[CompanySize] = None
    employees_approx: Optional[int] = None
    revenue_approx_eur: Optional[int] = None
    revenue_year: Optional[int] = None
    revenue_source: Optional[str] = None
    founded_year: Optional[int] = None
    hrb_number: Optional[str] = None
    priority: LeadPriority = LeadPriority.medium
    status: LeadStatus = LeadStatus.neu
    score: int = Field(default=50, ge=0, le=100)
    notes: Optional[str] = None
    data_source: Optional[str] = None


class CompanyUpdate(BaseModel):
    name: Optional[str] = None
    category: Optional[CompanyCategory] = None
    subcategory: Optional[str] = None
    tags: Optional[List[str]] = None
    city: Optional[str] = None
    website: Optional[str] = None
    email_general: Optional[str] = None
    email_sales: Optional[str] = None
    phone_main: Optional[str] = None
    phone_sales: Optional[str] = None
    size: Optional[CompanySize] = None
    employees_approx: Optional[int] = None
    revenue_approx_eur: Optional[int] = None
    priority: Optional[LeadPriority] = None
    status: Optional[LeadStatus] = None
    score: Optional[int] = Field(default=None, ge=0, le=100)
    notes: Optional[str] = None


class CompanyOut(BaseModel):
    id: UUID
    name: str
    category: CompanyCategory
    subcategory: Optional[str]
    country: CountryCode
    city: Optional[str]
    size: Optional[CompanySize]
    employees_approx: Optional[int]
    revenue_approx_eur: Optional[int]
    priority: LeadPriority
    status: LeadStatus
    score: int
    website: Optional[str]
    email_general: Optional[str]
    phone_main: Optional[str]
    has_open_jobs: bool
    open_jobs_count: int
    tags: Optional[List[str]]
    contacts_count: Optional[int] = 0
    jobs_prio1: Optional[int] = 0
    jobs_prio2: Optional[int] = 0
    jobs_prio3: Optional[int] = 0
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class CompanyDetail(CompanyOut):
    legal_form: Optional[str]
    brand_names: Optional[List[str]]
    state: Optional[str]
    postal_code: Optional[str]
    street: Optional[str]
    address_full: Optional[str]
    email_sales: Optional[str]
    phone_sales: Optional[str]
    linkedin_url: Optional[str]
    xing_url: Optional[str]
    revenue_year: Optional[int]
    revenue_source: Optional[str]
    founded_year: Optional[int]
    hrb_number: Optional[str]
    notes: Optional[str]
    news_signal: Optional[str]
    data_source: Optional[str]
    data_quality: int
    last_crawled_at: Optional[datetime]
    last_job_signal_at: Optional[datetime]
    contacts_count: int = 0
    activities_count: int = 0


class PaginatedCompanies(BaseModel):
    total: int
    page: int
    page_size: int
    pages: int
    items: List[CompanyOut]


# ── Endpoints ───────────────────────────────────────────────

@router.get("", response_model=PaginatedCompanies)
async def list_companies(
    # Filter
    search: Optional[str] = Query(None, description="Suche in Name, Stadt, Tags"),
    category: Optional[List[CompanyCategory]] = Query(None),
    country: Optional[List[CountryCode]] = Query(None),
    size: Optional[List[CompanySize]] = Query(None),
    priority: Optional[List[LeadPriority]] = Query(None),
    status: Optional[List[LeadStatus]] = Query(None),
    has_open_jobs: Optional[bool] = Query(None),
    has_contacts: Optional[bool] = Query(None),
    has_prio1_jobs: Optional[bool] = Query(None),
    has_prio2_jobs: Optional[bool] = Query(None),
    has_prio3_jobs: Optional[bool] = Query(None),
    min_score: Optional[int] = Query(None, ge=0, le=100),
    max_score: Optional[int] = Query(None, ge=0, le=100),
    min_revenue: Optional[int] = Query(None),
    max_revenue: Optional[int] = Query(None),
    tags: Optional[List[str]] = Query(None),
    # Sortierung
    sort_by: str = Query("score", enum=["score", "name", "updated_at", "created_at", "revenue_approx_eur", "employees_approx"]),
    sort_dir: str = Query("desc", enum=["asc", "desc"]),
    # Paginierung
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
):
    query = select(Company).where(Company.is_active == True)

    # Filter anwenden
    if search:
        q = f"%{search.lower()}%"
        query = query.where(
            or_(
                func.lower(Company.name).like(q),
                func.lower(Company.city).like(q),
            )
        )
    if category:
        query = query.where(Company.category.in_(category))
    if country:
        query = query.where(Company.country.in_(country))
    if size:
        query = query.where(Company.size.in_(size))
    if priority:
        query = query.where(Company.priority.in_(priority))
    if status:
        query = query.where(Company.status.in_(status))
    if has_open_jobs is not None:
        query = query.where(Company.has_open_jobs == has_open_jobs)
    if has_contacts is not None:
        from sqlalchemy import exists
        from app.models.models import Contact
        contacts_exist = exists().where(Contact.company_id == Company.id)
        if has_contacts:
            query = query.where(contacts_exist)
        else:
            query = query.where(~contacts_exist)
    if has_prio1_jobs:
        query = query.where(Company.jobs_prio1 > 0)
    if has_prio2_jobs:
        query = query.where(Company.jobs_prio2 > 0)
    if has_prio3_jobs:
        query = query.where(Company.jobs_prio3 > 0)
    if min_score is not None:
        query = query.where(Company.score >= min_score)
    if max_score is not None:
        query = query.where(Company.score <= max_score)
    if min_revenue is not None:
        query = query.where(Company.revenue_approx_eur >= min_revenue)
    if max_revenue is not None:
        query = query.where(Company.revenue_approx_eur <= max_revenue)
    if tags:
        query = query.where(Company.tags.overlap(tags))

    # Total Count
    count_q = select(func.count()).select_from(query.subquery())
    total = (await db.execute(count_q)).scalar_one()

    # Sortierung
    sort_col = getattr(Company, sort_by)
    if sort_dir == "desc":
        query = query.order_by(sort_col.desc().nulls_last())
    else:
        query = query.order_by(sort_col.asc().nulls_last())

    # Paginierung
    offset = (page - 1) * page_size
    query = query.offset(offset).limit(page_size)

    result = await db.execute(query)
    companies = result.scalars().all()

    # Contacts count per company
    from app.models.models import Contact
    company_ids = [c.id for c in companies]
    contacts_counts = {}
    if company_ids:
        counts_result = await db.execute(
            select(Contact.company_id, func.count(Contact.id).label('cnt'))
            .where(Contact.company_id.in_(company_ids))
            .group_by(Contact.company_id)
        )
        contacts_counts = {row.company_id: row.cnt for row in counts_result}

    items = []
    for c in companies:
        out = CompanyOut.model_validate(c)
        out.contacts_count = contacts_counts.get(c.id, 0)
        out.jobs_prio1 = getattr(c, 'jobs_prio1', 0) or 0
        out.jobs_prio2 = getattr(c, 'jobs_prio2', 0) or 0
        out.jobs_prio3 = getattr(c, 'jobs_prio3', 0) or 0
        items.append(out)

    return PaginatedCompanies(
        total=total,
        page=page,
        page_size=page_size,
        pages=-(-total // page_size),
        items=items,
    )


@router.get("/{company_id}", response_model=CompanyDetail)
async def get_company(company_id: UUID, db: AsyncSession = Depends(get_db)):
    company = await db.get(Company, company_id)
    if not company:
        raise HTTPException(status_code=404, detail="Unternehmen nicht gefunden")

    # Zähler berechnen
    contacts_count = (await db.execute(
        select(func.count()).where(Contact.company_id == company_id)
    )).scalar_one()

    activities_count = (await db.execute(
        select(func.count()).where(CrmActivity.company_id == company_id)
    )).scalar_one()

    data = CompanyDetail.model_validate(company)
    data.contacts_count = contacts_count
    data.activities_count = activities_count
    return data


@router.post("", response_model=CompanyOut, status_code=201)
async def create_company(payload: CompanyCreate, db: AsyncSession = Depends(get_db)):
    company = Company(**payload.model_dump())
    db.add(company)
    await db.commit()
    await db.refresh(company)
    return company


@router.patch("/{company_id}", response_model=CompanyOut)
async def update_company(company_id: UUID, payload: CompanyUpdate, db: AsyncSession = Depends(get_db)):
    company = await db.get(Company, company_id)
    if not company:
        raise HTTPException(status_code=404, detail="Unternehmen nicht gefunden")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(company, field, value)

    await db.commit()
    await db.refresh(company)
    return company


@router.patch("/{company_id}/priority", response_model=CompanyOut)
async def set_priority(company_id: UUID, priority: LeadPriority, db: AsyncSession = Depends(get_db)):
    """Schnell-Priorisierung aus dem Grid heraus"""
    company = await db.get(Company, company_id)
    if not company:
        raise HTTPException(status_code=404, detail="Unternehmen nicht gefunden")
    company.priority = priority
    await db.commit()
    await db.refresh(company)
    return company


@router.patch("/{company_id}/status", response_model=CompanyOut)
async def set_status(company_id: UUID, status: LeadStatus, db: AsyncSession = Depends(get_db)):
    """Status-Update aus dem Call Center View"""
    company = await db.get(Company, company_id)
    if not company:
        raise HTTPException(status_code=404, detail="Unternehmen nicht gefunden")
    company.status = status
    await db.commit()
    await db.refresh(company)
    return company


@router.delete("/{company_id}", status_code=204)
async def delete_company(company_id: UUID, db: AsyncSession = Depends(get_db)):
    company = await db.get(Company, company_id)
    if not company:
        raise HTTPException(status_code=404, detail="Unternehmen nicht gefunden")
    company.is_active = False  # Soft-Delete
    await db.commit()
