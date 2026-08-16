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
        client.patch(f"/api/v1/assets/{asset_id}", headers=headers, json={"prompt_text": "手工修改"})
        assert client.post(f"/api/v1/assets/{asset_id}/restore", headers=headers).json()["prompt_text"] == ""


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
        masked = client.patch("/api/v1/settings", headers=admin_headers, json={"comfyui_api_key": "test-comfy-key"}).json()["comfyui_api_key_masked"]
        assert masked.startswith("tes")
        assert client.get("/api/v1/categories", headers={"X-API-Key": "test-comfy-key"}).status_code == 200
        client.delete(f"/api/v1/users/{user['id']}", headers=admin_headers)
        client.delete(f"/api/v1/categories/{visible['id']}", headers=admin_headers)
        client.delete(f"/api/v1/categories/{hidden['id']}", headers=admin_headers)
