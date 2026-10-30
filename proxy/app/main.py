"""EphemeraAI proxy: keeps Meta API keys off the device and wraps each model call."""

import logging
from typing import Any

from fastapi import FastAPI

from app.config import Settings
from app.envelope import install_error_handlers, ok
from app.image_store import ImageStore
from app.providers import build_providers
from app.rate_limit import RateLimiter
from app.routes import enrich, scan, segment


def create_app(settings: Settings | None = None) -> FastAPI:
    config = settings or Settings()
    config.validate_for_startup()

    app = FastAPI(title="EphemeraAI proxy", version="0.1.0")
    app.state.settings = config
    app.state.providers = build_providers(config)
    app.state.image_store = ImageStore(ttl_seconds=config.image_ttl_seconds)

    install_error_handlers(app)
    app.middleware("http")(RateLimiter(config.rate_limit_per_minute).middleware)
    app.include_router(segment.router)
    app.include_router(enrich.router)
    app.include_router(scan.router)

    @app.get("/health")
    def health() -> dict[str, Any]:
        return ok({"status": "ok", "providers": app.state.providers.mode})

    logging.basicConfig(level=logging.INFO)
    return app
