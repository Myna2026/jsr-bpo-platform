"""Job Postings Route"""
from uuid import UUID
from typing import Optional, List
from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from datetime import datetime, date

from app.db.session import get_db
from app.models.models import JobPosting, JobPlatform

router = APIRouter()

class JobOut(BaseModel):
    id: UUID
    company_id: UUID
    title: str
    department: Optional[str]
    location: Optional[str]
    platform: JobPlatform
    external_url: Optional[str]
    platform_posted_at: Optional[date]
    is_growth_signal: bool
    signal_category: Optional[str]
    relevance_score: int
    is_active: bool
    first_seen_at: datetime
    class Config:
        from_attributes = True

@router.get("/company/{company_id}", response_model=List[JobOut])
async def get_jobs_for_company(
    company_id: UUID,
    active_only: bool = True,
    db: AsyncSession = Depends(get_db),
):
    q = select(JobPosting).where(JobPosting.company_id == company_id)
    if active_only:
        q = q.where(JobPosting.is_active == True)
    q = q.order_by(JobPosting.first_seen_at.desc())
    return (await db.execute(q)).scalars().all()

@router.get("/signals", response_model=List[JobOut])
async def get_growth_signals(
    limit: int = Query(50, le=200),
    db: AsyncSession = Depends(get_db),
):
    """Alle aktuellen Wachstums-Signale quer über alle Firmen"""
    q = (select(JobPosting)
         .where(JobPosting.is_growth_signal == True, JobPosting.is_active == True)
         .order_by(JobPosting.first_seen_at.desc())
         .limit(limit))
    return (await db.execute(q)).scalars().all()
