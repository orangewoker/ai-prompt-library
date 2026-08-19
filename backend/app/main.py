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
from .models import AppSetting, Asset, Category, ComfyApiKey, Job, Provider, ProviderModel, PromptProfile, User
from .schemas import AssetPatch, CategoryIn, CategoryPatch, ComfyApiKeyIn, ComfyApiKeyPatch, LoginIn, ProfileIn, ProfilePatch, ProviderIn, ProviderPatch, RandomIn, SettingsPatch, UserIn, UserPatch
from .security import ensure_admin, hash_api_key, hash_password, issue_token, mask_api_key, require_admin, require_auth, verify_password
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
        legacy_key = db.get(AppSetting, "comfyui_api_key")
        if not legacy_key:
            legacy_key = AppSetting(key="comfyui_api_key", value=settings.comfyui_api_key)
            db.add(legacy_key)
            # SessionLocal 关闭 autoflush，先提交才能确保后续迁移读取到刚创建的设置。
            db.commit()
        if legacy_key.value and not db.query(ComfyApiKey).filter(ComfyApiKey.name == "默认 ComfyUI 密钥").first():
            db.add(ComfyApiKey(name="默认 ComfyUI 密钥", key_hash=hash_api_key(legacy_key.value), key_prefix=legacy_key.value[:3], key_suffix=legacy_key.value[-4:]))
        if not db.query(PromptProfile).count():
            db.add(PromptProfile(name="视觉分析专家 V1", system_prompt=DEFAULT_SYSTEM_PROMPT, temperature=0.2, max_tokens=1200))
        # 将旧版本 Provider.model 自动迁移到一对多模型列表。
        for provider in db.query(Provider).all():
            if provider.model and not provider.models:
                provider.models.append(ProviderModel(model_name=provider.model))
        compress_existing_assets(db)
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
    api_scope = getattr(user, "_api_category_ids", "__unset__")
    if api_scope != "__unset__":
        return api_scope
    return None if user.role == "admin" else {category.id for category in user.category_access}


def serialize_user(user: User):
    return {"id": user.id, "username": user.username, "role": user.role, "enabled": user.enabled, "avatar_url": f"/media/{user.avatar_path}" if user.avatar_path else "", "category_ids": [c.id for c in user.category_access], "category_names": [c.name for c in user.category_access], "created_at": user.created_at}


def serialize_asset(a: Asset, detail=False):
    result = {"id": a.id, "category_id": a.category_id, "category_name": a.category.name if a.category else "", "original_filename": a.original_filename,
              "image_url": f"/media/{a.image_path}", "thumbnail_url": f"/media/{a.thumbnail_path}", "ai_original_text": a.ai_original_text,
              "prompt_text": a.prompt_text, "provider_id": a.provider_id, "model_name": a.model_name, "prompt_profile_id": a.prompt_profile_id,
              "width": a.width, "height": a.height, "status": a.status, "error_message": a.error_message, "created_at": a.created_at, "updated_at": a.updated_at}
    return result


def normalize_model_names(values: list[str]) -> list[str]:
    result = []
    seen = set()
    for value in values:
        name = str(value).strip()[:300]
        if name and name not in seen:
            result.append(name)
            seen.add(name)
    return result


def set_provider_models(provider: Provider, names: list[str]):
    names = normalize_model_names(names)
    # 原地复用已有记录，避免“手动模型”同时出现在远端列表时，替换集合在
    # SQLite flush 阶段先插入后删除而触发 provider_id/model_name 唯一键冲突。
    existing = {item.model_name: item for item in provider.models}
    desired = set(names)
    for item in list(provider.models):
        if item.model_name not in desired:
            provider.models.remove(item)
    for name in names:
        if name not in existing:
            provider.models.append(ProviderModel(model_name=name))
    if provider.model not in names:
        provider.model = names[0] if names else ""


def serialize_provider(provider: Provider):
    models = [item.model_name for item in provider.models]
    if provider.model and provider.model not in models:
        models.insert(0, provider.model)
    return {
        "id": provider.id,
        "name": provider.name,
        "base_url": provider.base_url,
        "api_key_masked": (provider.api_key[:3] + "••••••••" + provider.api_key[-4:]) if len(provider.api_key) > 7 else ("••••••••" if provider.api_key else ""),
        "model": provider.model,
        "models": models,
        "enabled": provider.enabled,
        "created_at": provider.created_at,
        "updated_at": provider.updated_at,
    }


def serialize_comfy_api_key(api_key: ComfyApiKey):
    return {
        "id": api_key.id,
        "name": api_key.name,
        "key_masked": mask_api_key(api_key.key_prefix + ("x" * 8) + api_key.key_suffix) if api_key.key_prefix or api_key.key_suffix else "••••••••",
        "enabled": api_key.enabled,
        "category_ids": [category.id for category in api_key.category_access],
        "category_names": [category.name for category in api_key.category_access],
        "all_categories": not bool(api_key.category_access),
        "created_at": api_key.created_at,
        "updated_at": api_key.updated_at,
    }


def provider_endpoint(base_url: str, resource: str) -> str:
    endpoint = base_url.strip().rstrip("/")
    for suffix in ("/chat/completions", "/models"):
        if endpoint.endswith(suffix):
            endpoint = endpoint[:-len(suffix)]
            break
    return f"{endpoint}/{resource}"


def save_normalized_image(data: bytes, image_path: Path, thumbnail_path: Path) -> tuple[int, int]:
    """保存最长边 1024 的 JPEG，并从同一副本生成缩略图。"""
    from PIL import Image, ImageOps

    with Image.open(BytesIO(data)) as source:
        source = ImageOps.exif_transpose(source)
        source.load()
        source.thumbnail((1024, 1024), Image.Resampling.LANCZOS)
        if source.mode in ("RGBA", "LA") or (source.mode == "P" and "transparency" in source.info):
            rgba = source.convert("RGBA")
            background = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
            background.alpha_composite(rgba)
            image = background.convert("RGB")
        else:
            image = source.convert("RGB")
        image_path.parent.mkdir(parents=True, exist_ok=True)
        thumbnail_path.parent.mkdir(parents=True, exist_ok=True)
        image.save(image_path, "JPEG", quality=88, optimize=True, progressive=True)
        thumbnail = image.copy()
        thumbnail.thumbnail((640, 640), Image.Resampling.LANCZOS)
        thumbnail.save(thumbnail_path, "WEBP", quality=84, method=6)
        return image.size


def compress_existing_assets(db: Session):
    """首次升级时把历史原图也转换掉，避免升级后旧数据继续占用原图空间。"""
    marker = db.get(AppSetting, "images_compressed_v1")
    if marker and marker.value == "1":
        return
    failed = 0
    for asset in db.query(Asset).all():
        old_path = settings.data_dir / asset.image_path
        if not old_path.exists():
            continue
        new_path = old_path.with_suffix(".jpg")
        thumb_path = settings.data_dir / asset.thumbnail_path
        try:
            width, height = save_normalized_image(old_path.read_bytes(), new_path, thumb_path)
            if new_path != old_path:
                old_path.unlink(missing_ok=True)
            asset.image_path = str(new_path.relative_to(settings.data_dir))
            asset.width = width
            asset.height = height
        except Exception:
            failed += 1
            logger.exception("历史素材压缩失败 asset_id=%s", asset.id)
    if not marker:
        marker = AppSetting(key="images_compressed_v1", value="1" if failed == 0 else "0")
        db.add(marker)
    else:
        marker.value = "1" if failed == 0 else "0"
    db.commit()
    if failed:
        logger.warning("有 %s 个历史素材未能压缩，下一次启动会重试", failed)


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
    key = setting.value
    default_key = db.query(ComfyApiKey).filter(ComfyApiKey.name == "默认 ComfyUI 密钥").first()
    duplicate_key = db.query(ComfyApiKey).filter(ComfyApiKey.key_hash == hash_api_key(key), ComfyApiKey.id != (default_key.id if default_key else -1)).first()
    if duplicate_key:
        raise HTTPException(409, "该密钥已被其他 ComfyUI 密钥使用")
    if not default_key:
        default_key = ComfyApiKey(name="默认 ComfyUI 密钥", key_hash=hash_api_key(key), key_prefix=key[:3], key_suffix=key[-4:])
        db.add(default_key)
    else:
        default_key.key_hash = hash_api_key(key); default_key.key_prefix = key[:3]; default_key.key_suffix = key[-4:]; default_key.enabled = True
    db.commit()
    return {"ok": True, "comfyui_api_key_masked": mask_api_key(key)}


@app.get("/api/v1/comfyui-keys")
def list_comfy_api_keys(db: Session = Depends(get_db), _: User = Depends(require_admin)):
    return [serialize_comfy_api_key(item) for item in db.query(ComfyApiKey).order_by(ComfyApiKey.id).all()]


@app.post("/api/v1/comfyui-keys")
def create_comfy_api_key(payload: ComfyApiKeyIn, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    import secrets
    if db.query(ComfyApiKey).filter(ComfyApiKey.name == payload.name).first():
        raise HTTPException(409, "密钥名称已存在")
    key = payload.key.strip() or secrets.token_urlsafe(32)
    if db.query(ComfyApiKey).filter(ComfyApiKey.key_hash == hash_api_key(key)).first():
        raise HTTPException(409, "该密钥已存在")
    categories = db.query(Category).filter(Category.id.in_(payload.category_ids)).all() if payload.category_ids else []
    if len(categories) != len(set(payload.category_ids)):
        raise HTTPException(400, "存在无效分类")
    item = ComfyApiKey(name=payload.name.strip(), key_hash=hash_api_key(key), key_prefix=key[:3], key_suffix=key[-4:], enabled=payload.enabled, category_access=categories)
    db.add(item); db.commit(); db.refresh(item)
    return {**serialize_comfy_api_key(item), "key": key}


@app.patch("/api/v1/comfyui-keys/{key_id}")
def patch_comfy_api_key(key_id: int, payload: ComfyApiKeyPatch, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    item = db.get(ComfyApiKey, key_id)
    if not item: raise HTTPException(404, "密钥不存在")
    values = payload.model_dump(exclude_unset=True)
    if "name" in values:
        duplicate = db.query(ComfyApiKey).filter(ComfyApiKey.name == values["name"], ComfyApiKey.id != key_id).first()
        if duplicate: raise HTTPException(409, "密钥名称已存在")
        item.name = values.pop("name").strip()
    raw_key = values.pop("key", None)
    if raw_key is not None:
        raw_key = raw_key.strip()
        if not raw_key: raise HTTPException(400, "新密钥不能为空")
        duplicate_key = db.query(ComfyApiKey).filter(ComfyApiKey.key_hash == hash_api_key(raw_key), ComfyApiKey.id != key_id).first()
        if duplicate_key: raise HTTPException(409, "该密钥已存在")
        item.key_hash = hash_api_key(raw_key); item.key_prefix = raw_key[:3]; item.key_suffix = raw_key[-4:]
    category_ids = values.pop("category_ids", None)
    for key, value in values.items(): setattr(item, key, value)
    if category_ids is not None:
        categories = db.query(Category).filter(Category.id.in_(category_ids)).all() if category_ids else []
        if len(categories) != len(set(category_ids)): raise HTTPException(400, "存在无效分类")
        item.category_access = categories
    db.commit(); db.refresh(item)
    return serialize_comfy_api_key(item)


@app.delete("/api/v1/comfyui-keys/{key_id}")
def delete_comfy_api_key(key_id: int, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    item = db.get(ComfyApiKey, key_id)
    if not item: raise HTTPException(404, "密钥不存在")
    if item.name == "默认 ComfyUI 密钥": raise HTTPException(400, "默认密钥请通过系统设置修改")
    db.delete(item); db.commit(); return {"ok": True}


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
    return [serialize_provider(p) for p in rows]


@app.post("/api/v1/providers")
def create_provider(payload: ProviderIn, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    values = payload.model_dump(exclude={"models"})
    model_names = normalize_model_names(payload.models or ([payload.model] if payload.model else []))
    p = Provider(**values)
    set_provider_models(p, model_names)
    db.add(p); db.commit(); db.refresh(p)
    return serialize_provider(p)


@app.patch("/api/v1/providers/{provider_id}")
def patch_provider(provider_id: int, payload: ProviderPatch, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    p = db.get(Provider, provider_id)
    if not p: raise HTTPException(404, "Provider 不存在")
    values = payload.model_dump(exclude_unset=True)
    if values.get("api_key") == "": values.pop("api_key", None)
    model_names = values.pop("models", None)
    for key, value in values.items(): setattr(p, key, value)
    if model_names is not None:
        set_provider_models(p, model_names)
    elif "model" in values and p.model:
        set_provider_models(p, [p.model, *[item.model_name for item in p.models]])
    db.commit(); db.refresh(p)
    return serialize_provider(p)


@app.delete("/api/v1/providers/{provider_id}")
def delete_provider(provider_id: int, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    p = db.get(Provider, provider_id)
    if not p: raise HTTPException(404, "Provider 不存在")
    db.delete(p); db.commit(); return {"ok": True}


@app.post("/api/v1/providers/{provider_id}/test")
def test_provider(provider_id: int, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    import httpx
    p = db.get(Provider, provider_id)
    if not p: raise HTTPException(404, "Provider 不存在")
    model_name = p.model or (p.models[0].model_name if p.models else "")
    if not model_name:
        return {"ok": False, "message": "连接失败：请先拉取或添加至少一个模型"}
    endpoint = provider_endpoint(p.base_url, "chat/completions")
    try:
        headers = {"Authorization": f"Bearer {p.api_key}"} if p.api_key else {}
        with httpx.Client(timeout=15) as client: response = client.post(endpoint, headers=headers, json={"model": model_name, "messages": [{"role": "user", "content": "请回复连接成功"}], "max_tokens": 10})
        response.raise_for_status(); return {"ok": True, "message": "连接成功"}
    except Exception as exc: return {"ok": False, "message": f"连接失败：{str(exc)[:300]}"}


@app.post("/api/v1/providers/{provider_id}/models/pull")
def pull_provider_models(provider_id: int, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    import httpx
    provider = db.get(Provider, provider_id)
    if not provider:
        raise HTTPException(404, "Provider 不存在")
    endpoint = provider_endpoint(provider.base_url, "models")
    headers = {"Authorization": f"Bearer {provider.api_key}"} if provider.api_key else {}
    try:
        with httpx.Client(timeout=30) as client:
            response = client.get(endpoint, headers=headers)
            response.raise_for_status()
            body = response.json()
    except Exception as exc:
        raise HTTPException(502, f"拉取模型失败：{str(exc)[:300]}") from exc
    rows = body.get("data", body.get("models", [])) if isinstance(body, dict) else body
    if not isinstance(rows, list):
        raise HTTPException(502, "拉取模型失败：服务返回的模型列表格式无法识别")
    names = []
    for item in rows:
        if isinstance(item, str):
            names.append(item)
        elif isinstance(item, dict):
            names.append(item.get("id") or item.get("name") or item.get("model") or "")
    names = normalize_model_names(names)
    if not names:
        raise HTTPException(502, "拉取模型失败：服务没有返回任何模型")
    set_provider_models(provider, names)
    db.commit(); db.refresh(provider)
    return {"ok": True, "count": len(names), "models": names, "provider": serialize_provider(provider)}


@app.get("/api/v1/prompt-profiles")
def list_profiles(db: Session = Depends(get_db), _: bool = Depends(require_auth)):
    return [{"id": p.id, "name": p.name, "system_prompt": p.system_prompt, "temperature": p.temperature, "max_tokens": p.max_tokens, "enabled": p.enabled, "created_at": p.created_at, "updated_at": p.updated_at} for p in db.query(PromptProfile).order_by(PromptProfile.id).all()]


@app.post("/api/v1/prompt-profiles")
def create_profile(payload: ProfileIn, db: Session = Depends(get_db), _: User = Depends(require_admin)):
    p = PromptProfile(**payload.model_dump()); db.add(p); db.commit(); db.refresh(p); return {"id": p.id, **payload.model_dump()}


@app.patch("/api/v1/prompt-profiles/{profile_id}")
def patch_profile(profile_id: int, payload: ProfilePatch, db: Session = Depends(get_db), _: User = Depends(require_admin)):
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
async def upload_assets(files: list[UploadFile] = File(...), category_id: int = Form(...), provider_id: int | None = Form(None), model_name: str | None = Form(None), prompt_profile_id: int | None = Form(None), force: bool = Form(False), db: Session = Depends(get_db), current_user: User = Depends(require_auth)):
    category = db.get(Category, category_id)
    if not category: raise HTTPException(404, "分类不存在")
    allowed = allowed_category_ids(current_user)
    if allowed is not None and category_id not in allowed: raise HTTPException(403, "你没有向该分类上传素材的权限")
    provider = db.get(Provider, provider_id) if provider_id else None
    selected_model = (model_name or "").strip()
    if provider_id and not provider:
        raise HTTPException(404, "AI 服务不存在")
    if provider and not provider.enabled:
        raise HTTPException(400, "所选 AI 服务已停用")
    if provider:
        available_models = [item.model_name for item in provider.models]
        selected_model = selected_model or provider.model or (available_models[0] if available_models else "")
        if not selected_model:
            raise HTTPException(400, "所选 AI 服务还没有模型，请先拉取或手动添加模型")
        if available_models and selected_model not in available_models:
            raise HTTPException(400, "所选模型不属于该 AI 服务")
    elif selected_model:
        raise HTTPException(400, "选择模型前请先选择 AI 服务")
    results, duplicates = [], []
    for upload in files:
        if not upload.filename or Path(upload.filename).suffix.lower() not in {".jpg", ".jpeg", ".png", ".webp"}: continue
        data = await upload.read(); digest = hashlib.sha256(data).hexdigest()
        existing = db.query(Asset).filter(Asset.image_hash == digest).first()
        if existing and not force:
            duplicates.append({"filename": upload.filename, "asset_id": existing.id}); continue
        stamp = f"{digest[:16]}_{datetime.now().strftime('%Y%m%d%H%M%S%f')}"
        image_path = settings.image_dir / f"{stamp}.jpg"
        thumb_path = settings.thumbnail_dir / f"{stamp}.webp"
        try:
            width, height = save_normalized_image(data, image_path, thumb_path)
        except Exception:
            image_path.unlink(missing_ok=True); thumb_path.unlink(missing_ok=True); continue
        asset = Asset(category_id=category_id, original_filename=upload.filename, image_path=str(image_path.relative_to(settings.data_dir)), thumbnail_path=str(thumb_path.relative_to(settings.data_dir)), image_hash=digest, provider_id=provider_id, prompt_profile_id=prompt_profile_id, model_name=selected_model, width=width, height=height, status="pending")
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
    # 重试失败任务时复用该素材最近的一条任务，避免失败记录一直占据仪表盘；
    # 正在执行的任务不重复入队。
    job = db.query(Job).filter(Job.asset_id == a.id).order_by(Job.created_at.desc(), Job.id.desc()).first()
    if job and job.status in {"pending", "processing"}:
        return {"ok": True, "job_id": job.id, "already_queued": True}
    if not job:
        job = Job(asset_id=a.id)
        db.add(job)
    job.status = "pending"; job.error_message = ""; job.started_at = None; job.finished_at = None; job.created_at = datetime.now()
    a.status = "pending"; a.error_message = ""
    db.commit(); db.refresh(job); queue_job(job.id); return {"ok": True, "job_id": job.id}


@app.delete("/api/v1/assets/{asset_id}")
def delete_asset(asset_id: int, db: Session = Depends(get_db), current_user: User = Depends(require_auth)):
    a = db.get(Asset, asset_id)
    if not a: raise HTTPException(404, "素材不存在")
    allowed = allowed_category_ids(current_user)
    if allowed is not None and a.category_id not in allowed: raise HTTPException(403, "你没有删除该素材的权限")
    for relative in (a.image_path, a.thumbnail_path): (settings.data_dir / relative).unlink(missing_ok=True)
    db.query(Job).filter(Job.asset_id == a.id).delete(); db.delete(a); db.commit(); return {"ok": True}


@app.get("/api/v1/jobs")
def list_jobs(status: str | None = None, db: Session = Depends(get_db), current_user: User = Depends(require_admin)):
    query = db.query(Job).order_by(Job.created_at.desc())
    if status: query = query.filter(Job.status == status)
    allowed = allowed_category_ids(current_user)
    rows = []
    # 仪表盘需要完整统计失败和后续导入的任务，不能因为固定上限导致新任务在进度中消失。
    for job in query.all():
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
def export_category(category_id: int, db: Session = Depends(get_db), current_user: User = Depends(require_admin)):
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
