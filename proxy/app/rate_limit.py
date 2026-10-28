"""Per-client sliding-window rate limit, kept in memory (single-instance proxy)."""

import time
from collections import defaultdict, deque
from collections.abc import Awaitable, Callable
from threading import Lock

from fastapi import Request, Response
from fastapi.responses import JSONResponse

from app.envelope import error_body

WINDOW_SECONDS = 60.0
EXEMPT_PATHS = frozenset({"/health"})


class RateLimiter:
    def __init__(self, limit_per_minute: int, clock: Callable[[], float] = time.monotonic) -> None:
        self._limit = limit_per_minute
        self._clock = clock
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()

    def allow(self, client: str) -> bool:
        now = self._clock()
        with self._lock:
            hits = self._hits[client]
            while hits and now - hits[0] > WINDOW_SECONDS:
                hits.popleft()
            if len(hits) >= self._limit:
                return False
            hits.append(now)
            return True

    async def middleware(self, request: Request, call_next: Callable[[Request], Awaitable[Response]]) -> Response:
        if request.url.path in EXEMPT_PATHS:
            return await call_next(request)
        client = request.client.host if request.client else "unknown"
        if not self.allow(client):
            return JSONResponse(status_code=429, content=error_body("rate_limited", "Too many requests. Slow down a little."))
        return await call_next(request)
