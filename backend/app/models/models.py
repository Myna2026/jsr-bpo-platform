"""
SQLAlchemy ORM Models — Tourism Leads Platform
"""
import uuid
from datetime import datetime
from typing import List, Optional

from sqlalchemy import (
    String, Integer, SmallInteger, Boolean, Text, BigInteger,
    DateTime, Date, ForeignKey, Enum as SAEnum, ARRAY, JSON
)
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship
from sqlalchemy.sql import func
import enum


class Base(DeclarativeBase):
    pass


# ── Enums (spiegeln die DB-Enums) ──────────────────────────

class CompanyCategory(str, enum.Enum):
    airline = "airline"
    kreuzfahrt = "kreuzfahrt"
    veranstalter = "veranstalter"
    pauschalreise = "pauschalreise"
    ota = "ota"
    vermittler = "vermittler"
    hotelkette = "hotelkette"
    boutique_hotel = "boutique_hotel"
    mietwagen = "mietwagen"
    dmc = "dmc"
    incoming = "incoming"
    transfer = "transfer"
    bahn = "bahn"
    bus_coach = "bus_coach"
    activity_provider = "activity_provider"
    tech_provider = "tech_provider"
    versicherung = "versicherung"
    sonstiges = "sonstiges"


class CompanySize(str, enum.Enum):
    micro = "micro"
    small = "small"
    medium = "medium"
    large = "large"
    enterprise = "enterprise"


class CountryCode(str, enum.Enum):
    DE = "DE"
    AT = "AT"
    CH = "CH"


class LeadPriority(str, enum.Enum):
    low = "low"
    medium = "medium"
    high = "high"
    vip = "vip"


class LeadStatus(str, enum.Enum):
    neu = "neu"
    in_bearbeitung = "in_bearbeitung"
    kontaktiert = "kontaktiert"
    qualifiziert = "qualifiziert"
    angebot = "angebot"
    gewonnen = "gewonnen"
    verloren = "verloren"
    do_not_contact = "do_not_contact"


class ContactDepartment(str, enum.Enum):
    geschaeftsfuehrung = "geschaeftsfuehrung"
    management = "management"
    sales = "sales"
    marketing = "marketing"
    operations = "operations"
    customer_service = "customer_service"
    finance = "finance"
    hr = "hr"
    it = "it"
    procurement = "procurement"
    sonstiges = "sonstiges"


class JobPlatform(str, enum.Enum):
    indeed = "indeed"
    stepstone = "stepstone"
    monster = "monster"
    linkedin = "linkedin"
    xing_jobs = "xing_jobs"
    arbeitsagentur = "arbeitsagentur"
    glassdoor = "glassdoor"
    kununu = "kununu"
    jobware = "jobware"
    stellenanzeigen_de = "stellenanzeigen_de"
    hokify = "hokify"
    karriere_at = "karriere_at"
    jobs_ch = "jobs_ch"
    karriereseite = "karriereseite"
    sonstiges = "sonstiges"


class ActivityType(str, enum.Enum):
    call_ausgehend = "call_ausgehend"
    call_eingehend = "call_eingehend"
    email_ausgehend = "email_ausgehend"
    email_eingehend = "email_eingehend"
    linkedin_nachricht = "linkedin_nachricht"
    meeting = "meeting"
    notiz = "notiz"
    statuswechsel = "statuswechsel"


# ── Models ──────────────────────────────────────────────────

class Company(Base):
    __tablename__ = "companies"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)

    name: Mapped[str] = mapped_column(String(255), nullable=False, index=True)
    legal_form: Mapped[Optional[str]] = mapped_column(String(50))
    brand_names: Mapped[Optional[List[str]]] = mapped_column(ARRAY(String))

    category: Mapped[CompanyCategory] = mapped_column(SAEnum(CompanyCategory, name="company_category"), nullable=False)
    subcategory: Mapped[Optional[str]] = mapped_column(String(100))
    tags: Mapped[Optional[List[str]]] = mapped_column(ARRAY(String))

    country: Mapped[CountryCode] = mapped_column(SAEnum(CountryCode, name="country_code"), nullable=False)
    state: Mapped[Optional[str]] = mapped_column(String(100))
    city: Mapped[Optional[str]] = mapped_column(String(100))
    postal_code: Mapped[Optional[str]] = mapped_column(String(20))
    street: Mapped[Optional[str]] = mapped_column(String(255))
    address_full: Mapped[Optional[str]] = mapped_column(Text)

    website: Mapped[Optional[str]] = mapped_column(String(500))
    email_general: Mapped[Optional[str]] = mapped_column(String(255))
    email_sales: Mapped[Optional[str]] = mapped_column(String(255))
    phone_main: Mapped[Optional[str]] = mapped_column(String(50))
    phone_sales: Mapped[Optional[str]] = mapped_column(String(50))
    linkedin_url: Mapped[Optional[str]] = mapped_column(String(500))
    xing_url: Mapped[Optional[str]] = mapped_column(String(500))

    size: Mapped[Optional[CompanySize]] = mapped_column(SAEnum(CompanySize, name="company_size"))
    employees_approx: Mapped[Optional[int]] = mapped_column(Integer)
    revenue_approx_eur: Mapped[Optional[int]] = mapped_column(BigInteger)
    revenue_year: Mapped[Optional[int]] = mapped_column(SmallInteger)
    revenue_source: Mapped[Optional[str]] = mapped_column(String(100))
    founded_year: Mapped[Optional[int]] = mapped_column(SmallInteger)
    hrb_number: Mapped[Optional[str]] = mapped_column(String(50))

    priority: Mapped[LeadPriority] = mapped_column(SAEnum(LeadPriority, name="lead_priority"), default=LeadPriority.medium)
    status: Mapped[LeadStatus] = mapped_column(SAEnum(LeadStatus, name="lead_status"), default=LeadStatus.neu)
    score: Mapped[int] = mapped_column(SmallInteger, default=50)
    notes: Mapped[Optional[str]] = mapped_column(Text)

    has_open_jobs: Mapped[bool] = mapped_column(Boolean, default=False)
    open_jobs_count: Mapped[int] = mapped_column(Integer, default=0)
    last_job_signal_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    news_signal: Mapped[Optional[str]] = mapped_column(Text)

    data_source: Mapped[Optional[str]] = mapped_column(String(100))
    data_quality: Mapped[int] = mapped_column(SmallInteger, default=50)
    last_crawled_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    jobs_prio1: Mapped[int] = mapped_column(Integer, default=0)
    jobs_prio2: Mapped[int] = mapped_column(Integer, default=0)
    jobs_prio3: Mapped[int] = mapped_column(Integer, default=0)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    # Relationships
    contacts: Mapped[List["Contact"]] = relationship("Contact", back_populates="company", cascade="all, delete-orphan")
    job_postings: Mapped[List["JobPosting"]] = relationship("JobPosting", back_populates="company", cascade="all, delete-orphan")
    activities: Mapped[List["CrmActivity"]] = relationship("CrmActivity", back_populates="company", cascade="all, delete-orphan")


class Contact(Base):
    __tablename__ = "contacts"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    company_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("companies.id", ondelete="CASCADE"), nullable=False)

    first_name: Mapped[Optional[str]] = mapped_column(String(100))
    last_name: Mapped[str] = mapped_column(String(100), nullable=False)
    salutation: Mapped[Optional[str]] = mapped_column(String(20))
    title: Mapped[Optional[str]] = mapped_column(String(50))

    job_title: Mapped[Optional[str]] = mapped_column(String(255))
    department: Mapped[Optional[ContactDepartment]] = mapped_column(SAEnum(ContactDepartment, name="contact_department"))
    seniority: Mapped[Optional[str]] = mapped_column(String(50))
    is_decision_maker: Mapped[bool] = mapped_column(Boolean, default=False)

    email: Mapped[Optional[str]] = mapped_column(String(255))
    email_verified: Mapped[bool] = mapped_column(Boolean, default=False)
    phone_direct: Mapped[Optional[str]] = mapped_column(String(50))
    phone_mobile: Mapped[Optional[str]] = mapped_column(String(50))
    linkedin_url: Mapped[Optional[str]] = mapped_column(String(500))
    xing_url: Mapped[Optional[str]] = mapped_column(String(500))

    is_current_employee: Mapped[bool] = mapped_column(Boolean, default=True)
    verified_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    source: Mapped[Optional[str]] = mapped_column(String(100))

    notes: Mapped[Optional[str]] = mapped_column(Text)
    last_contacted_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    do_not_contact: Mapped[bool] = mapped_column(Boolean, default=False)

    last_crawled_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

    company: Mapped["Company"] = relationship("Company", back_populates="contacts")
    activities: Mapped[List["CrmActivity"]] = relationship("CrmActivity", back_populates="contact")


class JobPosting(Base):
    __tablename__ = "job_postings"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    company_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("companies.id", ondelete="CASCADE"), nullable=False)

    title: Mapped[str] = mapped_column(String(500), nullable=False)
    department: Mapped[Optional[str]] = mapped_column(String(200))
    location: Mapped[Optional[str]] = mapped_column(String(200))
    job_type: Mapped[Optional[str]] = mapped_column(String(50))
    remote_ok: Mapped[Optional[bool]] = mapped_column(Boolean)

    platform: Mapped[JobPlatform] = mapped_column(SAEnum(JobPlatform, name="job_platform"), nullable=False)
    external_url: Mapped[Optional[str]] = mapped_column(String(1000))
    external_id: Mapped[Optional[str]] = mapped_column(String(200))
    platform_posted_at: Mapped[Optional[datetime]] = mapped_column(Date)

    is_growth_signal: Mapped[bool] = mapped_column(Boolean, default=False)
    signal_category: Mapped[Optional[str]] = mapped_column(String(100))
    relevance_score: Mapped[int] = mapped_column(SmallInteger, default=50)

    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    first_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    closed_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    company: Mapped["Company"] = relationship("Company", back_populates="job_postings")


class CrmActivity(Base):
    __tablename__ = "crm_activities"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    company_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("companies.id", ondelete="CASCADE"), nullable=False)
    contact_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True), ForeignKey("contacts.id", ondelete="SET NULL"))

    type: Mapped[ActivityType] = mapped_column(SAEnum(ActivityType, name="activity_type"), nullable=False)
    subject: Mapped[Optional[str]] = mapped_column(String(500))
    body: Mapped[Optional[str]] = mapped_column(Text)
    outcome: Mapped[Optional[str]] = mapped_column(String(100))
    duration_seconds: Mapped[Optional[int]] = mapped_column(Integer)

    agent_name: Mapped[Optional[str]] = mapped_column(String(100))
    agent_id: Mapped[Optional[uuid.UUID]] = mapped_column(UUID(as_uuid=True))

    next_action: Mapped[Optional[str]] = mapped_column(String(500))
    next_action_due_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))

    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    company: Mapped["Company"] = relationship("Company", back_populates="activities")
    contact: Mapped[Optional["Contact"]] = relationship("Contact", back_populates="activities")


class CrawlerRun(Base):
    __tablename__ = "crawler_runs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    crawler_name: Mapped[str] = mapped_column(String(100), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    records_found: Mapped[int] = mapped_column(Integer, default=0)
    records_new: Mapped[int] = mapped_column(Integer, default=0)
    records_updated: Mapped[int] = mapped_column(Integer, default=0)
    error_message: Mapped[Optional[str]] = mapped_column(Text)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    finished_at: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True))
    meta: Mapped[Optional[dict]] = mapped_column(JSONB)
