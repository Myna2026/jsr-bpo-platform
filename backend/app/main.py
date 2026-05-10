"""
Tourism Leads Platform — FastAPI Backend
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from app.core.config import settings
from app.api.routes import companies, contacts, jobs, activities, crawler, export


@asynccontextmanager
async def lifespan(app: FastAPI):
    # startup
    print(f"🚀 Tourism Leads API gestartet — {settings.ENV}")
    yield
    # shutdown
    print("👋 Shutdown")


app = FastAPI(
    title="Tourism Leads Platform",
    description="DACH Tourism Lead Management System",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Router registrieren
app.include_router(companies.router,  prefix="/api/v1/companies",  tags=["Companies"])
app.include_router(contacts.router,   prefix="/api/v1/contacts",   tags=["Contacts"])
app.include_router(jobs.router,       prefix="/api/v1/jobs",        tags=["Job Signals"])
app.include_router(activities.router, prefix="/api/v1/activities",  tags=["CRM Activities"])
app.include_router(crawler.router,    prefix="/api/v1/crawler",     tags=["Crawler"])
app.include_router(export.router,     prefix="/api/v1/export",      tags=["Export"])


@app.get("/health")
async def health():
    return {"status": "ok", "version": "0.1.0"}
