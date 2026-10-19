"""AgriSentry AI - FastAPI application assembly (Modules 5+6+7+8+9+10 wiring).

Run:  uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
Docs: http://localhost:8000/docs
"""
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .api import analysis, explain, future_risk, health, history, risk, sensors, weather
from .config import settings
from .database.db import db
from .utils.errors import AppError, error_payload

app = FastAPI(title=settings.app_name, version="0.1.0")

# Flutter dev needs CORS; tighten origins for production.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

for r in (health.router, sensors.router, weather.router, risk.router,
          future_risk.router, explain.router, history.router, analysis.router):
    app.include_router(r)


# ---------- consistent error contract (Contract section 23) ----------

@app.exception_handler(AppError)
async def app_error_handler(request: Request, exc: AppError) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code,
                        content=error_payload(exc.code, exc.message))


@app.exception_handler(HTTPException)
async def http_error_handler(request: Request, exc: HTTPException) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code,
                        content=error_payload("HTTP_ERROR", str(exc.detail)))


@app.exception_handler(Exception)
async def generic_error_handler(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(status_code=500,
                        content=error_payload("INTERNAL_ERROR",
                                              "Something went wrong on the server."))