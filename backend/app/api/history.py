"""History endpoints (Contract sections 16 database / 22 history)."""
from fastapi import APIRouter

from ..database.db import db
from ..utils.errors import AppError

router = APIRouter(tags=["history"])


@router.get("/api/history")
def history(limit: int = 50) -> dict:
    return {"scans": db.history(limit)}


@router.get("/api/history/{scan_id}")
def history_item(scan_id: int) -> dict:
    row = db.get_scan(scan_id)
    if not row:
        raise AppError("SCAN_NOT_FOUND", "No scan with that ID exists.", 404)
    return row