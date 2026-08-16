import base64
import hashlib
import hmac
import json
import secrets
import time
from fastapi import Depends, Header, HTTPException, status
from sqlalchemy.orm import Session
from .config import settings
from .database import get_db
from .models import AppSetting, User


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 120_000)
    return f"pbkdf2$120000${base64.urlsafe_b64encode(salt).decode()}${base64.urlsafe_b64encode(digest).decode()}"


def verify_password(password: str, encoded: str) -> bool:
    try:
        _, rounds, salt, digest = encoded.split("$")
        actual = hashlib.pbkdf2_hmac("sha256", password.encode(), base64.urlsafe_b64decode(salt), int(rounds))
        return hmac.compare_digest(actual, base64.urlsafe_b64decode(digest))
    except (ValueError, TypeError):
        return False


def issue_token(username: str) -> str:
    payload = f"{username}:{int(time.time()) + 86400}"
    signature = hmac.new(settings.api_key.encode(), payload.encode(), hashlib.sha256).hexdigest()
    return base64.urlsafe_b64encode(f"{payload}:{signature}".encode()).decode()


def valid_token(token: str) -> bool:
    try:
        raw = base64.urlsafe_b64decode(token.encode()).decode()
        username, expiry, signature = raw.rsplit(":", 2)
        payload = f"{username}:{expiry}"
        expected = hmac.new(settings.api_key.encode(), payload.encode(), hashlib.sha256).hexdigest()
        return int(expiry) > int(time.time()) and hmac.compare_digest(signature, expected)
    except (ValueError, TypeError, base64.binascii.Error):
        return False


def token_username(token: str) -> str | None:
    try:
        raw = base64.urlsafe_b64decode(token.encode()).decode()
        username, expiry, signature = raw.rsplit(":", 2)
        payload = f"{username}:{expiry}"
        expected = hmac.new(settings.api_key.encode(), payload.encode(), hashlib.sha256).hexdigest()
        if int(expiry) > int(time.time()) and hmac.compare_digest(signature, expected):
            return username
    except (ValueError, TypeError, base64.binascii.Error):
        pass
    return None


def comfyui_key(db: Session) -> str:
    row = db.get(AppSetting, "comfyui_api_key")
    return row.value if row and row.value else settings.comfyui_api_key


def require_auth(authorization: str | None = Header(default=None), x_api_key: str | None = Header(default=None), db: Session = Depends(get_db)):
    if x_api_key and (hmac.compare_digest(x_api_key, settings.api_key) or hmac.compare_digest(x_api_key, comfyui_key(db))):
        return ensure_admin(db)
    username = token_username(authorization[7:]) if authorization and authorization.lower().startswith("bearer ") else None
    if username:
        user = db.query(User).filter(User.username == username, User.enabled.is_(True)).first()
        if user:
            return user
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="请先登录或提供有效的 X-API-Key")


def require_admin(current_user: User = Depends(require_auth)):
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="只有管理员可以执行此操作")
    return current_user


def ensure_admin(db: Session):
    user = db.query(User).filter(User.username == settings.admin_username).first()
    if not user:
        user = User(username=settings.admin_username, password_hash=hash_password(settings.admin_password), role="admin")
        db.add(user)
        db.commit()
    return user
