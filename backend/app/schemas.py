from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field


class CategoryIn(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    description: str = ""
    sort_order: int = 0
    enabled: bool = True


class CategoryPatch(BaseModel):
    name: str | None = None
    description: str | None = None
    sort_order: int | None = None
    enabled: bool | None = None


class ProviderIn(BaseModel):
    name: str
    base_url: str
    api_key: str = ""
    model: str
    enabled: bool = True


class ProviderPatch(BaseModel):
    name: str | None = None
    base_url: str | None = None
    api_key: str | None = None
    model: str | None = None
    enabled: bool | None = None


class ProfileIn(BaseModel):
    name: str
    system_prompt: str
    temperature: float = 0.2
    max_tokens: int = 1200
    enabled: bool = True


class ProfilePatch(ProfileIn):
    pass


class AssetPatch(BaseModel):
    prompt_text: str | None = None
    category_id: int | None = None


class RandomIn(BaseModel):
    category_ids: list[int] = Field(min_length=1)
    count: int = Field(default=1, ge=1, le=100)
    seed: int = 0


class LoginIn(BaseModel):
    username: str
    password: str


class UserIn(BaseModel):
    username: str = Field(min_length=2, max_length=80)
    password: str = Field(min_length=6, max_length=200)
    role: str = "user"
    enabled: bool = True
    category_ids: list[int] = []


class UserPatch(BaseModel):
    username: str | None = None
    password: str | None = Field(default=None, min_length=6, max_length=200)
    role: str | None = None
    enabled: bool | None = None
    category_ids: list[int] | None = None


class SettingsPatch(BaseModel):
    comfyui_api_key: str = Field(min_length=1, max_length=500)
