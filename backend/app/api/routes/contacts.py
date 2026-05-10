"""Contacts Route"""
from uuid import UUID
from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from pydantic import BaseModel
from datetime import datetime

from app.db.session import get_db
from app.models.models import Contact, ContactDepartment

router = APIRouter()

class ContactCreate(BaseModel):
    company_id: UUID
    last_name: str
    first_name: Optional[str] = None
    salutation: Optional[str] = None
    title: Optional[str] = None
    job_title: Optional[str] = None
    department: Optional[ContactDepartment] = None
    seniority: Optional[str] = None
    is_decision_maker: bool = False
    email: Optional[str] = None
    phone_direct: Optional[str] = None
    phone_mobile: Optional[str] = None
    linkedin_url: Optional[str] = None
    xing_url: Optional[str] = None
    source: Optional[str] = None
    notes: Optional[str] = None

class ContactOut(BaseModel):
    id: UUID
    company_id: UUID
    first_name: Optional[str]
    last_name: str
    full_name: Optional[str] = None
    job_title: Optional[str]
    department: Optional[ContactDepartment]
    seniority: Optional[str]
    is_decision_maker: bool
    email: Optional[str]
    email_verified: bool
    phone_direct: Optional[str]
    phone_mobile: Optional[str]
    linkedin_url: Optional[str]
    xing_url: Optional[str]
    is_current_employee: bool
    source: Optional[str]
    created_at: datetime
    class Config:
        from_attributes = True

@router.get("/company/{company_id}", response_model=List[ContactOut])
async def get_contacts_for_company(
    company_id: UUID,
    department: Optional[ContactDepartment] = None,
    decision_makers_only: bool = False,
    db: AsyncSession = Depends(get_db),
):
    q = select(Contact).where(Contact.company_id == company_id, Contact.is_current_employee == True)
    if department:
        q = q.where(Contact.department == department)
    if decision_makers_only:
        q = q.where(Contact.is_decision_maker == True)
    result = await db.execute(q)
    return result.scalars().all()

@router.post("", response_model=ContactOut, status_code=201)
async def create_contact(payload: ContactCreate, db: AsyncSession = Depends(get_db)):
    contact = Contact(**payload.model_dump())
    db.add(contact)
    await db.commit()
    await db.refresh(contact)
    return contact

@router.patch("/{contact_id}/dnc")
async def set_do_not_contact(contact_id: UUID, db: AsyncSession = Depends(get_db)):
    contact = await db.get(Contact, contact_id)
    if not contact:
        raise HTTPException(404, "Kontakt nicht gefunden")
    contact.do_not_contact = True
    await db.commit()
    return {"status": "ok"}
