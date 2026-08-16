import os
from pathlib import Path
import tempfile

TEST_DATA = Path(tempfile.mkdtemp(prefix="vpl-test-"))
os.environ["DATA_DIR"] = str(TEST_DATA)
os.environ["ADMIN_PASSWORD"] = "test-password"
os.environ["API_KEY"] = "test-api-key"

from fastapi.testclient import TestClient
from app.main import app


def auth_headers(client):
    response = client.post("/api/v1/auth/login", json={"username": "admin", "password": "test-password"})
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def pytest_configure(config):
    config.client = TestClient(app)
