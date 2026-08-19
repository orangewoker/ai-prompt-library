from io import BytesIO
from PIL import Image
from .conftest import auth_headers


def test_health_and_login():
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as client:
        assert client.get("/api/v1/health").json()["status"] == "ok"
        headers = auth_headers(client)
        assert "Authorization" in headers
        assert client.get("/api/v1/categories", headers=headers).status_code == 200


def test_category_crud_and_random_exact_prompt():
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as client:
        headers = auth_headers(client)
        a = client.post("/api/v1/categories", headers=headers, json={"name": "街拍测试"}).json()
        b = client.post("/api/v1/categories", headers=headers, json={"name": "户外测试"}).json()
        assert a["name"] == "街拍测试"
        assert client.patch(f"/api/v1/categories/{a['id']}", headers=headers, json={"description": "desc"}).status_code == 200
        for category, prompt in ((a, "完整提示词 A"), (b, "完整提示词 B")):
            image = BytesIO(); Image.new("RGB", (32, 24), "red").save(image, "PNG"); image.seek(0)
            response = client.post("/api/v1/assets/upload", headers=headers, data={"category_id": category["id"], "force": "true"}, files={"files": (f"{category['id']}.png", image, "image/png")})
            asset_id = response.json()["items"][0]["id"]
            client.patch(f"/api/v1/assets/{asset_id}", headers=headers, json={"prompt_text": prompt})
        assert client.delete(f"/api/v1/categories/{a['id']}", headers=headers).status_code == 409
        result = client.post("/api/v1/random", headers=headers, json={"category_ids": [a["id"], b["id"]], "count": 1, "seed": 99}).json()["items"][0]["prompt"]
        assert result in {"完整提示词 A", "完整提示词 B"}
        assert not ("完整提示词 A" in result and "完整提示词 B" in result)


def test_upload_thumbnail_and_restore():
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as client:
        headers = auth_headers(client)
        category = client.post("/api/v1/categories", headers=headers, json={"name": "上传测试"}).json()
        image = BytesIO(); Image.new("RGB", (40, 50), "blue").save(image, "JPEG"); image.seek(0)
        response = client.post("/api/v1/assets/upload", headers=headers, data={"category_id": category["id"]}, files={"files": ("photo.jpg", image, "image/jpeg")})
        assert response.status_code == 200 and response.json()["items"][0]["thumbnail_url"].endswith(".webp")
        asset_id = response.json()["items"][0]["id"]
        item = client.get(f"/api/v1/assets/{asset_id}", headers=headers).json()
        assert item["image_url"].endswith(".jpg")
        assert item["width"] == 40 and item["height"] == 50
        client.patch(f"/api/v1/assets/{asset_id}", headers=headers, json={"prompt_text": "手工修改"})
        assert client.post(f"/api/v1/assets/{asset_id}/restore", headers=headers).json()["prompt_text"] == ""


def test_upload_resizes_saved_image_to_longest_edge_1024():
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as client:
        headers = auth_headers(client)
        category = client.post("/api/v1/categories", headers=headers, json={"name": "尺寸压缩测试"}).json()
        image = BytesIO(); Image.new("RGB", (2400, 1200), "orange").save(image, "PNG"); image.seek(0)
        response = client.post("/api/v1/assets/upload", headers=headers, data={"category_id": category["id"]}, files={"files": ("large.png", image, "image/png")})
        assert response.status_code == 200
        item = client.get(f"/api/v1/assets/{response.json()['items'][0]['id']}", headers=headers).json()
        assert item["image_url"].endswith(".jpg")
        assert max(item["width"], item["height"]) == 1024


def test_user_category_scope_and_comfyui_key():
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as client:
        admin_headers = auth_headers(client)
        visible = client.post("/api/v1/categories", headers=admin_headers, json={"name": "账号可见分类"}).json()
        hidden = client.post("/api/v1/categories", headers=admin_headers, json={"name": "账号隐藏分类"}).json()
        user = client.post("/api/v1/users", headers=admin_headers, json={"username": "scoped-user", "password": "scoped123", "category_ids": [visible["id"]]}).json()
        assert user["category_names"] == ["账号可见分类"]
        user_login = client.post("/api/v1/auth/login", json={"username": "scoped-user", "password": "scoped123"}).json()
        user_headers = {"Authorization": f"Bearer {user_login['access_token']}"}
        assert [item["name"] for item in client.get("/api/v1/categories", headers=user_headers).json()] == ["账号可见分类"]
        assert client.get("/api/v1/users", headers=user_headers).status_code == 403
        assert client.get("/api/v1/jobs", headers=user_headers).status_code == 403
        assert client.get(f"/api/v1/export?category_id={visible['id']}", headers=user_headers).status_code == 403
        assert client.post("/api/v1/providers", headers=user_headers, json={"name": "普通用户不应配置", "base_url": "http://example.test/v1"}).status_code == 403
        assert client.post("/api/v1/prompt-profiles", headers=user_headers, json={"name": "普通用户不应创建", "system_prompt": "test"}).status_code == 403
        masked = client.patch("/api/v1/settings", headers=admin_headers, json={"comfyui_api_key": "test-comfy-key"}).json()["comfyui_api_key_masked"]
        assert masked.startswith("tes")
        assert client.get("/api/v1/categories", headers={"X-API-Key": "test-comfy-key"}).status_code == 200
        client.delete(f"/api/v1/users/{user['id']}", headers=admin_headers)
        client.delete(f"/api/v1/categories/{visible['id']}", headers=admin_headers)
        client.delete(f"/api/v1/categories/{hidden['id']}", headers=admin_headers)


def test_multiple_comfyui_keys_can_limit_categories():
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as client:
        admin_headers = auth_headers(client)
        visible = client.post("/api/v1/categories", headers=admin_headers, json={"name": "密钥可见分类"}).json()
        hidden = client.post("/api/v1/categories", headers=admin_headers, json={"name": "密钥隐藏分类"}).json()
        image = BytesIO(); Image.new("RGB", (16, 16), "red").save(image, "PNG"); image.seek(0)
        visible_asset = client.post("/api/v1/assets/upload", headers=admin_headers, data={"category_id": visible["id"], "force": "true"}, files={"files": ("visible.png", image, "image/png")}).json()["items"][0]
        image = BytesIO(); Image.new("RGB", (16, 16), "blue").save(image, "PNG"); image.seek(0)
        hidden_asset = client.post("/api/v1/assets/upload", headers=admin_headers, data={"category_id": hidden["id"], "force": "true"}, files={"files": ("hidden.png", image, "image/png")}).json()["items"][0]
        created = client.post("/api/v1/comfyui-keys", headers=admin_headers, json={"name": "工作流 A", "key": "workflow-a-secret", "category_ids": [visible["id"]]}).json()
        assert created["key"] == "workflow-a-secret"
        assert created["category_ids"] == [visible["id"]]
        scoped_headers = {"X-API-Key": "workflow-a-secret"}
        rows = client.get("/api/v1/categories", headers=scoped_headers).json()
        assert [row["id"] for row in rows] == [visible["id"]]
        assert [row["id"] for row in client.get("/api/v1/assets", headers=scoped_headers).json()["items"]] == [visible_asset["id"]]
        assert client.get(f"/api/v1/assets/{visible_asset['id']}", headers=scoped_headers).status_code == 200
        assert client.get(f"/api/v1/assets/{hidden_asset['id']}", headers=scoped_headers).status_code == 403
        blocked_image = BytesIO(); Image.new("RGB", (16, 16), "green").save(blocked_image, "PNG"); blocked_image.seek(0)
        assert client.post("/api/v1/assets/upload", headers=scoped_headers, data={"category_id": hidden["id"]}, files={"files": ("blocked.png", blocked_image, "image/png")}).status_code == 403
        assert client.get("/api/v1/users", headers=scoped_headers).status_code == 403
        assert client.get("/api/v1/comfyui-keys", headers=scoped_headers).status_code == 403
        denied = client.post("/api/v1/random", headers=scoped_headers, json={"category_ids": [hidden["id"]], "count": 1, "seed": 1})
        assert denied.status_code == 200 and denied.json()["items"] == []
        assert client.patch(f"/api/v1/comfyui-keys/{created['id']}", headers=admin_headers, json={"enabled": False}).status_code == 200
        assert client.get("/api/v1/categories", headers=scoped_headers).status_code == 401
        assert client.delete(f"/api/v1/comfyui-keys/{created['id']}", headers=admin_headers).status_code == 200
        client.delete(f"/api/v1/categories/{visible['id']}", headers=admin_headers)
        client.delete(f"/api/v1/categories/{hidden['id']}", headers=admin_headers)


def test_avatar_upload_is_saved_and_returned():
    from fastapi.testclient import TestClient
    from app.main import app
    with TestClient(app) as client:
        headers = auth_headers(client)
        image = BytesIO(); Image.new("RGB", (80, 60), "purple").save(image, "PNG"); image.seek(0)
        response = client.post("/api/v1/users/1/avatar", headers=headers, files={"file": ("avatar.png", image, "image/png")})
        assert response.status_code == 200
        assert response.json()["avatar_url"].endswith(".webp")
        user = client.get("/api/v1/users", headers=headers).json()[0]
        assert user["avatar_url"].endswith(".webp")


def test_provider_can_pull_multiple_models_and_upload_uses_selected_model(monkeypatch):
    import importlib
    import httpx
    from fastapi.testclient import TestClient
    from app.main import app

    class FakeResponse:
        def __init__(self, body): self.body = body
        def raise_for_status(self): return None
        def json(self): return self.body

    class FakeClient:
        def __init__(self, *args, **kwargs): pass
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def get(self, url, headers=None):
            assert url == "http://model-host.test/v1/models"
            return FakeResponse({"data": [{"id": "vision-alpha"}, {"id": "vision-beta"}]})
        def post(self, *args, **kwargs):
            return FakeResponse({"choices": [{"message": {"content": "测试提示词"}}]})

    monkeypatch.setattr(httpx, "Client", FakeClient)
    monkeypatch.setattr(importlib.import_module("app.main"), "queue_job", lambda job_id: None)
    with TestClient(app) as client:
        headers = auth_headers(client)
        provider = client.post("/api/v1/providers", headers=headers, json={
            "name": "多模型服务", "base_url": "http://model-host.test/v1", "api_key": "secret", "models": ["vision-alpha"]
        }).json()
        assert provider["models"] == ["vision-alpha"]

        pulled = client.post(f"/api/v1/providers/{provider['id']}/models/pull", headers=headers)
        assert pulled.status_code == 200
        assert pulled.json()["models"] == ["vision-alpha", "vision-beta"]
        saved = next(item for item in client.get("/api/v1/providers", headers=headers).json() if item["id"] == provider["id"])
        assert saved["models"] == ["vision-alpha", "vision-beta"]

        category = client.post("/api/v1/categories", headers=headers, json={"name": "多模型上传测试"}).json()
        profile_id = client.get("/api/v1/prompt-profiles", headers=headers).json()[0]["id"]
        image = BytesIO(); Image.new("RGB", (30, 30), "green").save(image, "PNG"); image.seek(0)
        upload = client.post("/api/v1/assets/upload", headers=headers, data={
            "category_id": category["id"], "provider_id": provider["id"],
            "model_name": "vision-beta", "prompt_profile_id": profile_id,
        }, files={"files": ("multi-model.png", image, "image/png")})
        assert upload.status_code == 200
        assert upload.json()["items"][0]["model_name"] == "vision-beta"

        invalid = BytesIO(); Image.new("RGB", (30, 30), "yellow").save(invalid, "PNG"); invalid.seek(0)
        response = client.post("/api/v1/assets/upload", headers=headers, data={
            "category_id": category["id"], "provider_id": provider["id"], "model_name": "unknown-model",
        }, files={"files": ("invalid-model.png", invalid, "image/png")})
        assert response.status_code == 400
        assert response.json()["detail"] == "所选模型不属于该 AI 服务"
