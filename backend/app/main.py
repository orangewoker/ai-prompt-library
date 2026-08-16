import hashlib
import json
import logging
import mimetypes
import random
import shutil
import zipfile
from io import BytesIO
from uuid import uuid4
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path
from fastapi import Depends, FastAPI, File, Form, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import func, inspect, or_, text
from sqlalchemy.orm import Session, joinedload
from .config import settings
from .constants import DEFAULT_SYSTEM_PROMPT
from .database import Base, SessionLocal, engine, get_db
from .models import AppSetting, Asset, Category, Job, Provider, PromptProfile, User
from .schemas import AssetPatch, CategoryIn, CategoryPatch, LoginIn, ProfileIn, ProfilePatch, ProviderIn, ProviderPatch, RandomIn, SettingsPatch, UserIn, UserPatch
from .security import ensure_admin, hash_password, issue_token, require_admin, require_auth, verify_password
from .worker import queue_job

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger("visual-prompt-library")


@asynccontextmanager
async def lifespan(app: FastAPI):
    Base.metadata.create_all(engine)
    # SQLite create_all 不会给已有 users 表补列，兼容已经运行过的旧数据库。
    if "avatar_path" not in {column["name"] for column in inspect(engine).get_columns("users")}:
        with engine.begin() as connection:
            connection.execute(text("ALTER TABLE users ADD COLUMN avatar_path VARCHAR(500) DEFAULT ''"))
    db = SessionLocal()
    try:
        ensure_admin(db)
        if not db.get(AppSetting, "comfyui_api_key"):
            db.add(AppSetting(key="comfyui_api_key", value=settings.comfyui_api_key))
        if not db.query(PromptProfile).count():
            db.add(PromptProfile(name="视觉分析专家 V1", system_prompt=DEFAULT_SYSTEM_PROMPT, temperature=0.2, max_tokens=1200))
        pending_job_ids = []
        stuck = db.query(Job).filter(Job.status.in_(["processing", "pending"])).all()
        for job in stuck:
            job.status = "pending"; pending_job_ids.append(job.id); asset = db.get(Asset, job.asset_id)
            if asset: asset.status = "pending"
        db.commit()
        # 容器重启后自动恢复未完成任务，避免任务永久停留在 pending。
        for job_id in pending_job_ids:
            queue_job(job_id)
    finally:
        db.close()
    yield


app = FastAPI(title=settings.app_name, version="1.0.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=settings.cors_origins.split(","), allow_credentials=True, allow_methods=["*"], allow_headers=["*"])
app.mount("/media", StaticFiles(directory=str(settings.data_dir)), name="media")


def serialize_category(c: Category):
    return {"id": c.id, "name": c.name, "description": c.description, "sort_order": c.sort_order, "enabled": c.enabled, "asset_count": len(c.assets), "created_at": c.created_at, "updated_at": c.updated_at}


def allowed_category_ids(user: User) -> set[int] | None:
    return None if user.role == "admin" else {category.id for category in user.category_access}


def serialize_user(user: User):
    return {"id": user.id, "username": user.username, "role": user.role, "enabled": user.enabled, "avatar_url": f"/media/{user.avatar_path}" if user.avatar_path else "", "category_ids": [c.id for c in user.category_access], "category_names": [c.name for c in user.category_access], "created_at": user.created_at}


def serialize_asset(a: Asset, detail=False):
    result = {"id": a.id, "category_id": a.category_id, "category_name": a.category.name if a.category else "", "original_filename": a.original_filename,
              "image_url": f"/media/{a.image_path}", "thumbnail_url": f"/media/{a.thumbnail_path}", "ai_original_text": a.ai_original_text,
              "prompt_text": a.prompt_text, "provider_id": a.provider_id, "model_name": a.model_name, "prompt_profile_id": a.prompt_profile_id,
              "width": a.width, "height": a.height, "status": a.status, "error_message": a.error_message, "created_at": a.created_at, "updated_at": a.updated_at}
    return result


@app.get("/api/v1/health")
def health(db: Session = Depends(get_db)):
    return {"status": "ok", "service": settings.app_name, "database": "sqlite"}


@app.post("/api/v1/auth/login")
def login(payload: LoginIn, db: Session = Depends(get_db)):
    ensure_admin(db)
    user = db.query(User).filter(User.username == payload.username).first()
    if not user or not user.enabled or not verify_password(payload.password, user.password_hash):
        raise HTTPException(401, "用户名或密码错误")
    return {"access_token": issue_token(user.username), "token_type": "bearer", "username": user.username, "user_id": user.id, "role": user.role, "avatar_url": f"/media/{user.avatar_path}" if user.avatar_path else "", "category_ids": [c.id for c in user.category_access]}


@app.get("/api/v1/users")
def list_users(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    return [serialize_user(user) for user in db.query(User).order_by(User.id).all()]


@app.post("/api/v1/users")
def create_user(payload: UserIn, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    if db.query(User).filter(User.username == payload.username).first():
        raise HTTPException(409, "账号名已存在")
    if payload.role not in {"admin", "user"}:
        raise HTTPException(400, "账号角色只能是 admin 或 user")
    categories = db.query(Category).filter(Category.id.in_(payload.category_ids)).all() if payload.category_ids else []
    if len(categories) != len(set(payload.category_ids)):
        raise HTTPException(400, "存在无效分类")
    user = User(username=payload.username, password_hash=hash_password(payload.password), role=payload.role, enabled=payload.enabled, category_access=categories)
    db.add(user); db.commit(); db.refresh(user)
    return serialize_user(user)


@app.patch("/api/v1/users/{user_id}")
def patch_user(user_id: int, payload: UserPatch, db: Session = Depends(get_db), current_user: User = Depends(require_admin)):
    user = db.get(User, user_id)
    if not user: raise HTTPException(404, "账号不存在")
    values = payload.model_dump(exclude_unset=True)
    if "username" in values:
        duplicate = db.query(User).filter(User.username == values["username"], User.id != user_id).first()
        if duplicate: raise HTTPException(409, "账号名已存在")
        user.username = values.pop("username")
    if "password" in values:
        user.password_hash = hash_password(values.pop("password"))
    category_ids = values.pop("category_ids", None)
    if "role" in values:
        if values["role"] not in {"admin", "user"}: raise HTTPException(400, "账号角色只能是 admin 或 user")
        if user.id == current_user.id and values["role"] != "admin": raise HTTPException(400, "不能取消当前管理员自己的管理员角色")
    if "enabled" in values and user.id == current_user.id and not values["enabled"]: raise HTTPException(400, "不能停用当前登录账号")
    for key, value in values.items(): setattr(user, key, value)
    if category_ids is not None:
        categories = db.query(Category).filter(Category.id.in_(category_ids)).all() if category_ids else []
        if len(categories) != len(set(category_ids)): raise HTTPException(400, "存在无效分类")
        user.category_access = categories
    db.commit(); db.refresh(user)
    return serialize_user(user)


@app.delete("/api/v1/users/{user_id}")
def delete_user(user_id: int, db: Session = Depends(get_db), current_user: User = Depends(require_admin)):
    user = db.get(User, user_id)
    if not user: raise HTTPException(404, "账号不存在")
    if user.id == current_user.id or user.username == settings.admin_username:
        raise HTTPException(400, "不能删除当前管理员或系统主账号")
    db.delete(user); db.commit(); return {"ok": True}


@app.post("/api/v1/users/{user_id}/avatar")
async def upload_avatar(user_id: int, file: UploadFile = File(...), db: Session = Depends(get_db), current_user: User = Depends(require_auth)):
    user = db.get(User, user_id)
    if not user: raise HTTPException(404, "账号不存在")
    if current_user.id != user_id and current_user.role != "admin": raise HTTPException(403, "只能修改自己的头像")
    if not file.filename or Path(file.filename).suffix.lower() not in {".jpg", ".jpeg", ".png", ".webp"}:
        raise HTTPException(400, "头像只支持 JPG、PNG、WEBP")
    from PIL import Image
    data = await file.read()
    try:
        with Image.open(BytesIO(data)) as image:
            image.thumbnail((256, 256))
            output = BytesIO(); image.convert("RGB").save(output, "WEBP", quality=88)
    except Exception as exc:
        raise HTTPException(400, f"头像图片无法读取：{str(exc)[:120]}") from exc
    filename = f"user_{user.id}_{uuid4().hex}.webp"
    path = settings.avatar_dir / filename
    path.write_bytes(output.getvalue())
    if user.avatar_path: (settings.data_dir / user.avatar_path).unlink(missing_ok=True)
    user.avatar_path = str(path.relative_to(settings.data_dir)); db.commit(); db.refresh(user)
    return {"ok": True, "avatar_url": f"/media/{user.avatar_path}"}


@app.get("/api/v1/settings")
def get_settings(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    from .security import comfyui_key
    key = comfyui_key(db)
    return {"comfyui_api_key_masked": (key[:3] + "••••••••" + key[-4:]) if len(key) > 7 else "••••••••", "has_comfyui_api_key": bool(key)}


@app.patch("/api/v1/settings")
def patch_settings(payload: SettingsPatch, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    setting = db.get(AppSetting, "comfyui_api_key")
    if not setting:
        setting = AppSetting(key="comfyui_api_key", value=payload.comfyui_api_key); db.add(setting)
    else:
        setting.value = payload.comfyui_api_key
    db.commit()
    key = setting.value
    return {"ok": True, "comfyui_api_key_masked": (key[:3] + "••••••••" + key[-4:]) if len(key) > 7 else "••••••••"}


@app.get("/api/v1/categories")
def list_categories(enabled_only: bool = False, db: Session = Depends(get_db), current_user: User = Depends(require_auth)):
    query = db.query(Category).options(joinedload(Category.assets)).order_by(Category.sort_order, Category.id)
    if enabled_only: query = query.filter(Category.enabled.is_(True))
    allowed = allowed_category_ids(current_user)
    if allowed is not None: query = query.filter(Category.id.in_(allowed))
    return [serialize_category(c) for c in query.all()]


@app.post("/api/v1/categories")
def create_category(payload: CategoryIn, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    if db.query(Category).filter(Category.name == payload.name).first(): raise HTTPException(409, "分类名称已存在")
    c = Category(**payload.model_dump()); db.add(c); db.commit(); db.refresh(c); return serialize_category(c)


@app.patch("/api/v1/categories/{category_id}")
def patch_category(category_id: int, payload: CategoryPatch, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    c = db.get(Category, category_id)
    if not c: raise HTTPException(404, "分类不存在")
    for key, value in payload.model_dump(exclude_unset=True).items(): setattr(c, key, value)
    db.commit(); db.refresh(c); return serialize_category(c)


@app.delete("/api/v1/categories/{category_id}")
def delete_category(category_id: int, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    c = db.get(Category, category_id)
    if not c: raise HTTPException(404, "分类不存在")
    if db.query(Asset).filter(Asset.category_id == category_id).count(): raise HTTPException(409, "该分类中存在素材，请移动素材后再删除")
    db.delete(c); db.commit(); return {"ok": True}


@app.get("/api/v1/providers")
def list_providers(db: Session = Depends(get_db), _: bool = Depends(require_auth)):
    rows = db.query(Provider).order_by(Provider.id.desc()).all()
    return [{"id": p.id, "name": p.name, "base_url": p.base_url, "api_key_masked": (p.api_key[:3] + "••••••••" + p.api_key[-4:]) if len(p.api_key) > 7 else ("••••••••" if p.api_key else ""), "model": p.model, "enabled": p.enabled, "created_at": p.created_at, "updated_at": p.updated_at} for p in rows]


@app.post("/api/v1/providers")
def create_provider(payload: ProviderIn, db: Session = Depends(get_db), _: bool = Depends(require_auth)):
    p = Provider(**payload.model_dump()); db.add(p); db.commit(); db.refresh(p); return {"id": p.id, "name": p.name, "base_url": p.base_url, "model": p.model, "enabled": p.enabled}


@app.patch("/api/v1/providers/{provider_id}")
def patch_provider(provider_id: int, payload: ProviderPatch, db: Session = Depends(get_db), _: bool = Depends(require_auth)):
    p = db.get(Provider, provider_id)
    if not p: raise HTTPException(404, "Provider 不存在")
    values = payload.model_dump(exclude_unset=True)
    if values.get("api_key") == "": values.pop("api_key", None)
    for key, value in values.items(): setattr(p, key, value)
    db.commit(); return {"id": p.id, "name": p.name, "base_url": p.base_url, "model": p.model, "enabled": p.enabled}


@app.delete("/api/v1/providers/{provider_id}")
def delete_provider(provider_id: int, db: Session = Depends(get_db), _: bool = Depends(require_auth)):
    p = db.get(Provider, provider_id)
    if not p: raise HTTPException(404, "Provider 不存在")
    db.delete(p); db.commit(); return {"ok": True}


@app.post("/api/v1/providers/{provider_id}/test")
def test_provider(provider_id: int, db: Session = Depends(get_db), _: bool = Depends(require_auth)):
    import httpx
    p = db.get(Provider, provider_id)
    if not p: raise HTTPException(404, "Provider 不存在")
    endpoint = p.base_url.rstrip("/")
    if not endpoint.endswith("/chat/completions"): endpoint += "/chat/completions"
    try:
        headers = {"Authorization": f"Bearer {p.api_key}"} if p.api_key else {}
        with httpx.Client(timeout=15) as client: response = client.post(endpoint, headers=headers, json={"model": p.model, "messages": [{"role": "user", "content": "请回复连接成功"}], "max_tokens": 10})
        response.raise_for_status(); return {"ok": True, "message": "连接成功"}
    except Exception as exc: return {"ok": False, "message": f"连接失败：{str(exc)[:300]}"}


@app.get("/api/v1/prompt-profiles")
def list_profiles(db: Session = Depends(get_db), _: bool = Depends(require_auth)):
    return [{"id": p.id, "name": p.name, "system_prompt": p.system_prompt, "temperature": p.temperature, "max_tokens": p.max_tokens, "enabled": p.enabled, "created_at": p.created_at, "updated_at": p.updated_at} for p in db.query(PromptProfile).order_by(PromptProfile.id).all()]


@app.post("/api/v1/prompt-profiles")
def create_profile(payload: ProfileIn, db: Session = Depends(get_db), _: bool = Depends(require_auth)):
    p = PromptProfile(**payload.model_dump()); db.add(p); db.commit(); db.refresh(p); return {"id": p.id, **payload.model_dump()}


@app.patch("/api/v1/prompt-profiles/{profile_id}")
def patch_profile(profile_id: int, payload: ProfilePatch, db: Session = Depends(get_db), _: bool = Depends(require_auth)):
    p = db.get(PromptProfile, profile_id)
    if not p: raise HTTPException(404, "模板不存在")
    for key, value in payload.model_dump(exclude_unset=True).items(): setattr(p, key, value)
    db.commit(); return {"id": p.id, "name": p.name, "system_prompt": p.system_prompt, "temperature": p.temperature, "max_tokens": p.max_tokens, "enabled": p.enabled}


@app.get("/api/v1/assets")
def list_assets(category_id: int | None = None, search: str = "", status: str | None = None, page: int = Query(1, ge=1), page_size: int = Query(60, ge=1, le=200), db: Session = Depends(get_db), current_user: User = Depends(require_auth)):
    query = db.query(Asset).options(joinedload(Asset.category)).order_by(Asset.created_at.desc())
    if category_id: query = query.filter(Asset.category_id == category_id)
    allowed = allowed_category_ids(current_user)
    if allowed is not None: query = query.filter(Asset.category_id.in_(allowed))
    if status: query = query.filter(Asset.status == status)
    if search: query = query.filter(or_(Asset.original_filename.ilike(f"%{search}%"), Asset.prompt_text.ilike(f"%{search}%")))
    total = query.count(); rows = query.offset((page - 1) * page_size).limit(page_size).all()
    return {"items": [serialize_asset(a) for a in rows], "total": total, "page": page, "page_size": page_size}


@app.get("/api/v1/assets/{asset_id}")
def get_asset(asset_id: int, db: Session = Depends(get_db), current_user: User = Depends(require_auth)):
    a = db.get(Asset, asset_id)
    if not a: raise HTTPException(404, "素材不存在")
    allowed = allowed_category_ids(current_user)
    if allowed is not None and a.category_id not in allowed: raise HTTPException(403, "你没有访问该分类的权限")
    return serialize_asset(a, True)


@app.post("/api/v1/assets/upload")
async def upload_assets(files: list[UploadFile] = File(...), category_id: int = Form(...), provider_id: int | None = Form(None), prompt_profile_id: int | None = Form(None), force: bool = Form(False), db: Session = Depends(get_db), current_user: User = Depends(require_auth)):
    category = db.get(Category, category_id)
    if not category: raise HTTPException(404, "分类不存在")
    allowed = allowed_category_ids(current_user)
    if allowed is not None and category_id not in allowed: raise HTTPException(403, "你没有向该分类上传素材的权限")
    results, duplicates = [], []
    for upload in files:
        if not upload.filename or Path(upload.filename).suffix.lower() not in {".jpg", ".jpeg", ".png", ".webp"}: continue
        data = await upload.read(); digest = hashlib.sha256(data).hexdigest()
        existing = db.query(Asset).filter(Asset.image_hash == digest).first()
        if existing and not force:
            duplicates.append({"filename": upload.filename, "asset_id": existing.id}); continue
        suffix = Path(upload.filename).suffix.lower() or ".jpg"
        stamp = f"{digest[:16]}_{datetime.now().strftime('%Y%m%d%H%M%S%f')}"
        image_path = settings.image_dir / f"{stamp}{suffix}"
        image_path.write_bytes(data)
        from PIL import Image
        try:
            with Image.open(image_path) as image:
                width, height = image.size; thumb_path = settings.thumbnail_dir / f"{stamp}.webp"; image.thumbnail((640, 640)); image.convert("RGB").save(thumb_path, "WEBP", quality=84)
        except Exception:
            image_path.unlink(missing_ok=True); continue
        asset = Asset(category_id=category_id, original_filename=upload.filename, image_path=str(image_path.relative_to(settings.data_dir)), thumbnail_path=str(thumb_path.relative_to(settings.data_dir)), image_hash=digest, provider_id=provider_id, prompt_profile_id=prompt_profile_id, model_name=(db.get(Provider, provider_id).model if provider_id and db.get(Provider, provider_id) else ""), width=width, height=height, status="pending")
        db.add(asset); db.flush(); job = Job(asset_id=asset.id, status="pending"); db.add(job); db.commit(); db.refresh(job); queue_job(job.id)
        results.append(serialize_asset(asset))
    return {"items": results, "duplicates": duplicates}


@app.patch("/api/v1/assets/{asset_id}")
def patch_asset(asset_id: int, payload: AssetPatch, db: Session = Depends(get_db), current_user: User = Depends(require_auth)):
    a = db.get(Asset, asset_id)
    if not a: raise HTTPException(404, "素材不存在")
    allowed = allowed_category_ids(current_user)
    if allowed is not None and a.category_id not in allowed: raise HTTPException(403, "你没有编辑该素材的权限")
    if payload.category_id is not None and not db.get(Category, payload.category_id): raise HTTPException(404, "目标分类不存在")
    if allowed is not None and payload.category_id is not None and payload.category_id not in allowed: raise HTTPException(403, "你没有移动到目标分类的权限")
    for key, value in payload.model_dump(exclude_unset=True).items(): setattr(a, key, value)
    db.commit(); db.refresh(a); return serialize_asset(a)


@app.post("/api/v1/assets/{asset_id}/restore")
def restore_asset(asset_id: int, db: Session = Depends(get_db), current_user: User = Depends(require_auth)):
    a = db.get(Asset, asset_id)
    if not a: raise HTTPException(404, "素材不存在")
    allowed = allowed_category_ids(current_user)
    if allowed is not None and a.category_id not in allowed: raise HTTPException(403, "你没有访问该素材的权限")
    a.prompt_text = a.ai_original_text; db.commit(); return serialize_asset(a)


@app.post("/api/v1/assets/{asset_id}/reanalyze")
def reanalyze(asset_id: int, db: Session = Depends(get_db), current_user: User = Depends(require_auth)):
    a = db.get(Asset, asset_id)
    if not a: raise HTTPException(404, "素材不存在")
    allowed = allowed_category_ids(current_user)
    if allowed is not None and a.category_id not in allowed: raise HTTPException(403, "你没有重新分析该素材的权限")
    job = Job(asset_id=a.id, status="pending"); a.status = "pending"; a.error_message = ""; db.add(job); db.commit(); db.refresh(job); queue_job(job.id); return {"ok": True, "job_id": job.id}


@app.delete("/api/v1/assets/{asset_id}")
def delete_asset(asset_id: int, db: Session = Depends(get_db), current_user: User = Depends(require_auth)):
    a = db.get(Asset, asset_id)
    if not a: raise HTTPException(404, "素材不存在")
    allowed = allowed_category_ids(current_user)
    if allowed is not None and a.category_id not in allowed: raise HTTPException(403, "你没有删除该素材的权限")
    for relative in (a.image_path, a.thumbnail_path): (settings.data_dir / relative).unlink(missing_ok=True)
    db.query(Job).filter(Job.asset_id == a.id).delete(); db.delete(a); db.commit(); return {"ok": True}


@app.get("/api/v1/jobs")
def list_jobs(status: str | None = None, db: Session = Depends(get_db), current_user: User = Depends(require_auth)):
    query = db.query(Job).order_by(Job.created_at.desc())
    if status: query = query.filter(Job.status == status)
    allowed = allowed_category_ids(current_user)
    rows = []
    for job in query.limit(200).all():
        asset = db.get(Asset, job.asset_id)
        if not asset: continue
        if allowed is not None and asset.category_id not in allowed: continue
        category = db.get(Category, asset.category_id)
        rows.append({"id": job.id, "asset_id": job.asset_id, "original_filename": asset.original_filename, "thumbnail_url": f"/media/{asset.thumbnail_path}", "category_id": asset.category_id, "category_name": category.name if category else "", "asset_status": asset.status, "status": job.status, "error_message": job.error_message, "created_at": job.created_at, "started_at": job.started_at, "finished_at": job.finished_at})
    return rows


@app.post("/api/v1/random")
def random_prompts(payload: RandomIn, db: Session = Depends(get_db), current_user: User = Depends(require_auth)):
    allowed = allowed_category_ids(current_user)
    category_ids = payload.category_ids if allowed is None else [category_id for category_id in payload.category_ids if category_id in allowed]
    rows = db.query(Asset).options(joinedload(Asset.category)).filter(Asset.category_id.in_(category_ids), Asset.prompt_text != "").all()
    if not rows: return {"items": []}
    rng = random.Random(payload.seed) if payload.seed else random.SystemRandom()
    chosen = rng.sample(rows, min(payload.count, len(rows)))
    return {"items": [{"asset_id": a.id, "category_id": a.category_id, "category_name": a.category.name if a.category else "", "prompt": a.prompt_text, "thumbnail_url": f"/media/{a.thumbnail_path}"} for a in chosen]}


@app.get("/api/v1/export")
def export_category(category_id: int, db: Session = Depends(get_db), current_user: User = Depends(require_auth)):
    c = db.get(Category, category_id)
    if not c: raise HTTPException(404, "分类不存在")
    allowed = allowed_category_ids(current_user)
    if allowed is not None and category_id not in allowed: raise HTTPException(403, "你没有导出该分类的权限")
    rows = db.query(Asset).filter(Asset.category_id == c.id).all(); output = [{"id": a.id, "category": c.name, "prompt": a.prompt_text, "image": a.image_path} for a in rows]
    path = settings.export_dir / f"category_{c.id}.json"; path.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8"); return FileResponse(path, media_type="application/json", filename=path.name)


@app.get("/api/v1/backup")
def backup(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    db.commit(); path = settings.backup_dir / f"backup_{datetime.now().strftime('%Y%m%d_%H%M%S')}.zip"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        if (settings.data_dir / "app.db").exists(): archive.write(settings.data_dir / "app.db", "app.db")
        for folder in (settings.image_dir, settings.thumbnail_dir, settings.avatar_dir):
            for item in folder.glob("*"): archive.write(item, str(item.relative_to(settings.data_dir)))
    return FileResponse(path, media_type="application/zip", filename=path.name)


@app.get("/{full_path:path}")
def frontend(full_path: str):
    # main.py 位于 /app/backend/app，前端构建产物位于 /app/backend/static。
    static_root = Path(__file__).resolve().parents[1] / "static"
    requested = static_root / full_path
    if requested.is_file(): return FileResponse(requested, headers={"Cache-Control": "no-store, max-age=0"})
    index = static_root / "index.html"
    if index.exists(): return FileResponse(index, headers={"Cache-Control": "no-store, max-age=0"})
    return {"service": settings.app_name, "message": "前端尚未构建，请运行 npm run build"}
