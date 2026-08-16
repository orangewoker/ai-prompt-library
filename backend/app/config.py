from pathlib import Path
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "AI Prompt Library"
    admin_username: str = "admin"
    admin_password: str = "admin123"
    api_key: str = "change-me-api-key"
    comfyui_api_key: str = "change-me-comfyui-key"
    data_dir: Path = Path("/app/data")
    cors_origins: str = "*"
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def db_url(self) -> str:
        return f"sqlite:///{self.data_dir / 'app.db'}"

    @property
    def image_dir(self) -> Path:
        return self.data_dir / "images"

    @property
    def thumbnail_dir(self) -> Path:
        return self.data_dir / "thumbnails"

    @property
    def export_dir(self) -> Path:
        return self.data_dir / "exports"

    @property
    def backup_dir(self) -> Path:
        return self.data_dir / "backups"


settings = Settings()
for directory in (settings.data_dir, settings.image_dir, settings.thumbnail_dir, settings.export_dir, settings.backup_dir, settings.data_dir / "logs"):
    directory.mkdir(parents=True, exist_ok=True)
