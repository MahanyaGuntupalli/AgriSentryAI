"""Consistent error contract (Contract section 23).

Every backend error is returned as:
    {"error": {"code": "...", "message": "..."}}
"""


class AppError(Exception):
    def __init__(self, code: str, message: str, status_code: int = 400):
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code


def error_payload(code: str, message: str) -> dict:
    return {"error": {"code": code, "message": message}}