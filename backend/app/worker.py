import base64
import logging
import mimetypes
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
import httpx
from .database import SessionLocal
from .config import settings
from .models import Asset, Job, Provider, PromptProfile

logger = logging.getLogger("visual-prompt-library")
executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="ai-worker")


def queue_job(job_id: int):
    executor.submit(process_job, job_id)


def process_job(job_id: int):
    db = SessionLocal()
    job = db.get(Job, job_id)
    if not job:
        db.close(); return
    try:
        job.status = "processing"; job.started_at = datetime.now(timezone.utc); db.commit()
        asset = db.get(Asset, job.asset_id)
        provider = db.get(Provider, asset.provider_id) if asset and asset.provider_id else None
        profile = db.get(PromptProfile, asset.prompt_profile_id) if asset and asset.prompt_profile_id else None
        if not asset or not provider or not profile:
            raise RuntimeError("缺少 AI Provider 或视觉分析模板")
        raw = (settings.data_dir / asset.image_path).read_bytes()
        mime = mimetypes.guess_type(asset.original_filename)[0] or "image/jpeg"
        image_url = f"data:{mime};base64,{base64.b64encode(raw).decode()}"
        endpoint = provider.base_url.rstrip("/")
        if not endpoint.endswith("/chat/completions"):
            endpoint += "/chat/completions"
        headers = {"Content-Type": "application/json"}
        if provider.api_key:
            headers["Authorization"] = f"Bearer {provider.api_key}"
        payload = {"model": provider.model, "temperature": profile.temperature, "max_tokens": profile.max_tokens,
                   "messages": [{"role": "system", "content": profile.system_prompt},
                                {"role": "user", "content": [{"type": "text", "text": "请分析这张图片并输出最终完整提示词。"}, {"type": "image_url", "image_url": {"url": image_url}}]}]}
        with httpx.Client(timeout=180) as client:
            response = client.post(endpoint, headers=headers, json=payload)
            response.raise_for_status()
            body = response.json()
        text = body.get("choices", [{}])[0].get("message", {}).get("content", "")
        if isinstance(text, list):
            text = "".join(part.get("text", "") for part in text if isinstance(part, dict))
        if not text.strip():
            raise RuntimeError("视觉模型没有返回有效文本")
        asset.ai_original_text = text.strip(); asset.prompt_text = text.strip(); asset.status = "completed"; asset.error_message = ""
        job.status = "completed"; job.finished_at = datetime.now(timezone.utc); db.commit()
        logger.info("AI分析完成 asset_id=%s provider=%s", asset.id, provider.name)
    except Exception as exc:
        logger.exception("AI分析失败 job_id=%s", job_id)
        job.status = "failed"; job.error_message = str(exc)[:2000]; job.finished_at = datetime.now(timezone.utc)
        asset = db.get(Asset, job.asset_id)
        if asset:
            asset.status = "failed"; asset.error_message = str(exc)[:2000]
        db.commit()
    finally:
        db.close()
