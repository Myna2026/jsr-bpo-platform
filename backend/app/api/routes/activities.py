"""CRM Activities Route"""
from uuid import UUID
from typing import Optional, List
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from datetime import datetime

from app.db.session import get_db
from app.models.models import CrmActivity, ActivityType

router = APIRouter()

class ActivityCreate(BaseModel):
    company_id: UUID
    contact_id: Optional[UUID] = None
    type: ActivityType
    subject: Optional[str] = None
    body: Optional[str] = None
    outcome: Optional[str] = None
    duration_seconds: Optional[int] = None
    agent_name: Optional[str] = None
    next_action: Optional[str] = None
    next_action_due_at: Optional[datetime] = None

class ActivityOut(BaseModel):
    id: UUID
    company_id: UUID
    contact_id: Optional[UUID]
    type: ActivityType
    subject: Optional[str]
    body: Optional[str]
    outcome: Optional[str]
    duration_seconds: Optional[int]
    agent_name: Optional[str]
    next_action: Optional[str]
    next_action_due_at: Optional[datetime]
    created_at: datetime
    class Config:
        from_attributes = True

@router.get("/company/{company_id}", response_model=List[ActivityOut])
async def get_activities(company_id: UUID, db: AsyncSession = Depends(get_db)):
    q = select(CrmActivity).where(CrmActivity.company_id == company_id).order_by(CrmActivity.created_at.desc())
    return (await db.execute(q)).scalars().all()

@router.post("", response_model=ActivityOut, status_code=201)
async def create_activity(payload: ActivityCreate, db: AsyncSession = Depends(get_db)):
    activity = CrmActivity(**payload.model_dump())
    db.add(activity)
    await db.commit()
    await db.refresh(activity)
    return activity

@router.get("/due-today", response_model=List[ActivityOut])
async def get_due_today(agent_id: Optional[UUID] = None, db: AsyncSession = Depends(get_db)):
    """Follow-ups die heute fällig sind — für Call Center Morning Briefing"""
    from datetime import date
    from sqlalchemy import func, and_
    q = select(CrmActivity).where(
        func.date(CrmActivity.next_action_due_at) <= date.today(),
        CrmActivity.next_action_due_at.is_not(None),
    )
    if agent_id:
        q = q.where(CrmActivity.agent_id == agent_id)
    return (await db.execute(q.order_by(CrmActivity.next_action_due_at))).scalars().all()
