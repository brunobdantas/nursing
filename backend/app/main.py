from __future__ import annotations

import os
from contextlib import asynccontextmanager
from collections.abc import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.gzip import GZipMiddleware
from sqlalchemy.ext.asyncio import AsyncEngine, async_sessionmaker, create_async_engine

from app.api.router import router


def create_app(*, database_url: str | None = None) -> FastAPI:
    configured_url = database_url or os.getenv("DATABASE_URL")

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        engine: AsyncEngine | None = None
        if configured_url:
            engine = create_async_engine(configured_url, pool_pre_ping=True)
            app.state.db_sessionmaker = async_sessionmaker(
                engine,
                expire_on_commit=False,
            )

        yield

        if engine is not None:
            await engine.dispose()

    app = FastAPI(
        title="Nursing Clinical API",
        version="0.9.0",
        lifespan=lifespan,
    )
    app.add_middleware(GZipMiddleware, minimum_size=1000, compresslevel=6)
    app.include_router(router)
    return app


app = create_app()
