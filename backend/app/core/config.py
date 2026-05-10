from pydantic_settings import BaseSettings
from typing import List


class Settings(BaseSettings):
    ENV: str = "development"
    DATABASE_URL: str = "postgresql+asyncpg://leads:leads@localhost:5432/tourism_leads"
    REDIS_URL: str = "redis://localhost:6379/0"
    SECRET_KEY: str = "change-me-in-production"
    CORS_ORIGINS: List[str] = ["http://localhost:3000", "http://localhost:5173"]

    # Crawler
    CRAWLER_DELAY_SECONDS: float = 2.0
    USER_AGENT: str = "TourismLeadsBot/1.0 (internal research tool)"

    # Externe APIs (Keys via .env)
    APOLLO_API_KEY: str = ""
    HUNTER_API_KEY: str = ""
    PROXYCURL_API_KEY: str = ""   # LinkedIn Enrichment (legal)

    # OpenAI / Anthropic für Enrichment
    ANTHROPIC_API_KEY: str = ""

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
