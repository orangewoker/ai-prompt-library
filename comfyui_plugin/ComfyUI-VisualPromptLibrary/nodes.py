"""ComfyUI nodes for AI Prompt Library.

The nodes intentionally fetch categories on every execution. This keeps the
category list in sync with the server without storing any library data in the
ComfyUI installation.
"""
import requests


def _headers(api_key):
    return {"X-API-Key": api_key} if api_key.strip() else {}


def _base(server):
    value = server.strip().rstrip("/")
    if not value:
        raise RuntimeError("提示词库服务器地址不能为空")
    return value


def _timeout(value):
    try:
        return max(3, min(int(value), 180))
    except (TypeError, ValueError):
        return 30


def _categories(server, api_key, timeout):
    try:
        response = requests.get(f"{_base(server)}/api/v1/categories", headers=_headers(api_key), params={"enabled_only": "true"}, timeout=timeout)
        response.raise_for_status()
        rows = response.json()
        if not isinstance(rows, list):
            raise ValueError("服务器返回的分类数据格式不正确")
        return [row for row in rows if isinstance(row, dict) and "id" in row and "name" in row]
    except (requests.RequestException, ValueError, TypeError) as exc:
        raise RuntimeError(f"提示词库服务器连接失败：{exc}") from exc


def _category_tokens(value):
    if isinstance(value, (list, tuple)):
        values = value
    else:
        values = str(value or "").replace("，", ",").split(",")
    return {str(item).strip() for item in values if str(item).strip() and str(item).strip() not in {"全部", "全部分类", "*"}}


class VisualPromptRandom:
    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {
            "服务器地址": ("STRING", {"default": "http://localhost:8765"}),
            "API Key": ("STRING", {"default": "change-me-comfyui-key", "multiline": False}),
            "分类": ("STRING", {"default": "", "multiline": False, "placeholder": "留空为全部；填写分类 ID，多个用逗号分隔"}),
            "抽取数量": ("INT", {"default": 1, "min": 1, "max": 100}),
            "随机种子": ("INT", {"default": 0, "min": 0, "max": 2147483647}),
        }, "optional": {"超时秒数": ("INT", {"default": 30, "min": 3, "max": 180})}}

    RETURN_TYPES = ("STRING", "INT", "STRING")
    RETURN_NAMES = ("提示词", "素材ID", "分类")
    FUNCTION = "run"
    CATEGORY = "Visual Prompt Library/提示词库"

    def run(self, 服务器地址, **kwargs):
        api_key = kwargs.get("API Key", "")
        category_text = kwargs.get("分类", "")
        count = kwargs.get("抽取数量", 1)
        seed = kwargs.get("随机种子", 0)
        timeout = _timeout(kwargs.get("超时秒数", 30))
        category_rows = _categories(服务器地址, api_key, timeout)
        ids = []
        wanted = _category_tokens(category_text)
        for row in category_rows:
            if not wanted or str(row["id"]) in wanted or row["name"] in wanted:
                ids.append(row["id"])
        if not ids:
            raise RuntimeError("没有匹配的启用分类，请检查分类名称或 ID")
        try:
            response = requests.post(f"{_base(服务器地址)}/api/v1/random", headers={**_headers(api_key), "Content-Type": "application/json"}, json={"category_ids": ids, "count": count, "seed": seed}, timeout=timeout)
            response.raise_for_status()
            items = response.json().get("items", [])
        except (requests.RequestException, ValueError, TypeError) as exc:
            raise RuntimeError(f"随机提示词请求失败：{exc}") from exc
        if not items:
            raise RuntimeError("所选分类中没有可用的完整提示词")
        return ("\n".join(item["prompt"] for item in items), items[0]["asset_id"], items[0]["category_name"])


class VisualPromptById:
    @classmethod
    def INPUT_TYPES(cls):
        return {"required": {"服务器地址": ("STRING", {"default": "http://localhost:8765"}), "素材ID": ("INT", {"default": 1, "min": 1})}, "optional": {"API Key": ("STRING", {"default": "change-me-comfyui-key", "multiline": False}), "超时秒数": ("INT", {"default": 30, "min": 3, "max": 180})}}

    RETURN_TYPES = ("STRING", "INT", "STRING")
    RETURN_NAMES = ("提示词", "素材ID", "分类")
    FUNCTION = "run"
    CATEGORY = "Visual Prompt Library/提示词库"

    def run(self, 服务器地址, **kwargs):
        api_key = kwargs.get("API Key", "")
        asset_id = kwargs.get("素材ID", 1)
        try:
            response = requests.get(f"{_base(服务器地址)}/api/v1/assets/{asset_id}", headers=_headers(api_key), timeout=_timeout(kwargs.get("超时秒数", 30)))
            response.raise_for_status(); item = response.json()
            if not isinstance(item, dict):
                raise ValueError("服务器返回的素材数据格式不正确")
        except (requests.RequestException, ValueError, TypeError) as exc:
            raise RuntimeError(f"指定素材请求失败：{exc}") from exc
        if not item.get("prompt_text"):
            raise RuntimeError("该素材还没有可用提示词")
        return (item["prompt_text"], item["id"], item.get("category_name", ""))


NODE_CLASS_MAPPINGS = {"VisualPromptRandom": VisualPromptRandom, "VisualPromptById": VisualPromptById}
NODE_DISPLAY_NAME_MAPPINGS = {"VisualPromptRandom": "视觉提示词库 · 随机抽取", "VisualPromptById": "视觉提示词库 · 指定素材"}
