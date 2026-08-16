# AI Prompt Library

AI 图片反推素材库服务：上传图片、选择分类、调用 OpenAI Compatible 视觉模型生成一条完整提示词，并以图片与提示词一一绑定的方式长期管理。随机功能只抽取完整素材提示词，绝不跨图片拼接。

## 1. 项目目录

```text
AI-pml/
├── backend/app/                 FastAPI、SQLite、后台 Worker
├── frontend/                    Vue 3 + TypeScript + Element Plus
├── comfyui_plugin/              ComfyUI 中文节点
├── data/                        持久化数据库、原图、缩略图、备份
├── Dockerfile
├── docker-compose.yml
└── .env.example
```

截图位置：本项目以可运行页面为准，启动后可直接打开首页；后续截图文件建议放在 `docs/screenshots/`，当前仓库不依赖截图才能运行。

## 2. Docker Desktop 启动（推荐）

先安装并启动 Docker Desktop，在项目根目录执行：

```powershell
Copy-Item .env.example .env
# 编辑 .env，至少修改 ADMIN_PASSWORD 和 API_KEY
docker compose up -d --build
docker compose ps
docker compose logs -f visual-prompt-library
```

打开 http://localhost:8765，默认账号来自 `ADMIN_USERNAME`，密码来自 `ADMIN_PASSWORD`。示例文件默认是 `admin / change-this-password`；真正运行前请修改。

## 3. 本地开发

后端（Python 3.12）：

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r backend/requirements.txt
$env:DATA_DIR = "$PWD\data"
uvicorn backend.app.main:app --reload --port 8765
```

前端另开终端：

```powershell
cd frontend
npm install
npm run dev
```

开发前端地址 http://localhost:5173，Vite 会将 `/api` 与 `/media` 代理到 8765。生产构建由 Dockerfile 编译后由 FastAPI 统一提供。

## 4. LM Studio 配置

1. 在 LM Studio 加载支持视觉输入的模型并启动 Local Server。
2. Docker Desktop 下 Base URL 填 `http://host.docker.internal:1234/v1`；直接本机开发可填 `http://localhost:1234/v1`。
3. API Key 可填 `lm-studio`（LM Studio 通常不校验）或你的服务要求的 Key。
4. Model 填 LM Studio 中实际加载的模型标识。
5. 在“系统提示词模板”确认或修改“视觉分析专家 V1”，上传时选择 Provider 与模板。

上传只负责保存文件、生成缩略图和创建 Job，会立即返回；AI 分析由容器后台 Worker 执行。没有 Provider 或视觉模型不支持图片时，任务会进入“失败”，错误显示在“分析任务”。

## 5. 功能使用

- 支持单张、多张、文件夹选择和 Ctrl+V 粘贴图片。
- 素材详情可编辑当前提示词、复制、恢复 AI 原文、重新分析、移动分类、删除。
- 分类删除前必须为空。
- 随机提示词支持多分类、1~100 条和可复现 Seed。
- API 写操作和 ComfyUI 调用支持 `X-API-Key`；网页使用登录后的 Bearer Token。
- 管理员可在“账号管理”新增账号并分配可见分类；在“系统设置”修改独立的 ComfyUI 访问密钥。

## 6. API 示例

```bash
curl http://localhost:8765/api/v1/health
curl -H "X-API-Key: change-me-api-key" http://localhost:8765/api/v1/categories
curl -X POST http://localhost:8765/api/v1/random \
  -H "Content-Type: application/json" -H "X-API-Key: change-me-api-key" \
  -d '{"category_ids":[1,3],"count":1,"seed":123456}'
```

主要路由统一在 `/api/v1`：health、auth/login、categories、assets、providers、prompt-profiles、jobs、random、export、backup。

## 7. ComfyUI 插件

插件目录：`comfyui_plugin/ComfyUI-VisualPromptLibrary`。将整个目录复制到 `ComfyUI/custom_nodes/`，然后执行：

```bash
pip install -r ComfyUI-VisualPromptLibrary/requirements.txt
```

Windows 便携版使用 `python_embeded\\python.exe -m pip install -r ...\\requirements.txt`。重启 ComfyUI 后，在 `Visual Prompt Library/提示词库` 找到“视觉提示词库 · 随机抽取”和“视觉提示词库 · 指定素材”两个节点。分类会在每次执行时从服务器动态读取，支持分类 ID/名称和多分类逗号筛选；网络错误会转换为中文节点错误。

服务器地址不能带 `/api/v1`：同机直连使用 `http://127.0.0.1:8765`，ComfyUI 在 Docker 中使用 `http://host.docker.internal:8765`，飞牛上使用 `http://飞牛IP:8765`。API Key 填网页“系统设置 → ComfyUI 访问密钥”，不是 LM Studio 的 Key。详细安装和排查见 `comfyui_plugin/ComfyUI-VisualPromptLibrary/README.md`。

## 8. 数据、备份与飞牛 OS

所有持久化数据在 `/app/data`，宿主机映射到 `./data`，包括 `app.db`、`images/`、`thumbnails/`、`exports/`、`backups/`、`logs/`。网页“导入导出”可下载完整 ZIP 备份或分类 JSON。

飞牛 OS 完整安装步骤（Docker Hub 镜像）：

1. 在飞牛 Docker 应用中创建目录 `/vol1/1000/visual-prompt-library/data`。
2. 下载仓库中的 `docker-compose.fnos.yml` 和 `.env.example`，将 `.env.example` 复制为同目录 `.env`。
3. 修改 `.env` 中的 `ADMIN_PASSWORD`、`API_KEY`、`COMFYUI_API_KEY`。
4. Docker Hub 镜像为公开镜像，通常不需要登录；如遇到匿名拉取限流，可先在飞牛终端登录：

```bash
docker login
```

5. 在 `docker-compose.fnos.yml` 所在目录启动：

```bash
docker compose -f docker-compose.fnos.yml pull
docker compose -f docker-compose.fnos.yml up -d
docker compose -f docker-compose.fnos.yml ps
docker compose -f docker-compose.fnos.yml logs -f visual-prompt-library
```

6. 浏览器打开 `http://飞牛IP:8765`，使用 `.env` 中的管理员账号密码登录。
7. 首次登录后进入“系统设置”修改 ComfyUI 密钥，并在 AI 服务管理中填写 LM Studio 或其他视觉模型服务。
8. 安装 ComfyUI 插件：复制 `comfyui_plugin/ComfyUI-VisualPromptLibrary` 到 `ComfyUI/custom_nodes/`，在 ComfyUI Python 环境执行 `pip install -r requirements.txt`，重启 ComfyUI。节点服务器地址填 `http://飞牛IP:8765`，API Key 填网页系统设置中的 ComfyUI 密钥。

如果 Docker Hub 镜像暂时无法拉取，也可以在飞牛上使用源码构建：下载整个 GitHub 仓库 ZIP 并解压，在项目根目录执行：

```bash
cp .env.example .env
# 编辑 .env，至少修改 ADMIN_PASSWORD、API_KEY、COMFYUI_API_KEY
docker compose -f docker-compose.fnos-build.yml build
docker compose -f docker-compose.fnos-build.yml up -d
docker compose -f docker-compose.fnos-build.yml ps
```

源码构建文件是 `docker-compose.fnos-build.yml`，数据仍然保存在 `/vol1/1000/visual-prompt-library/data`。飞牛需要能访问 Docker Hub 以下载 Node/Python 基础镜像；构建期间不要同时启动镜像版 Compose。

飞牛 OS 使用的 Compose 文件：

```yaml
services:
  visual-prompt-library:
    image: allenpie/visual-prompt-library:latest
    ports:
      - "8765:8765"
    volumes:
      - /vol1/1000/visual-prompt-library/data:/app/data
    env_file:
      - .env
    restart: unless-stopped
```

升级版本：备份数据后执行 `docker compose -f docker-compose.fnos.yml pull && docker compose -f docker-compose.fnos.yml up -d`。数据库和图片都在 `/vol1/1000/visual-prompt-library/data`，升级不会删除。

## 9. 镜像构建与发布准备

当前项目可在 Docker Desktop 本地构建：

```bash
docker compose build
docker buildx build --platform linux/amd64,linux/arm64 -t allenpie/visual-prompt-library:latest -t allenpie/visual-prompt-library:v1.0.0 --push .
```

当前已发布 Docker Hub 多架构镜像：`allenpie/visual-prompt-library:latest` 和 `allenpie/visual-prompt-library:v1.0.0`，支持 `linux/amd64`、`linux/arm64`。未登录对应 registry 时不会自动发布；先执行 `docker login`。

## 10. 常见排查

- 页面打不开：`docker compose ps`、`docker compose logs visual-prompt-library`，确认 8765 端口未被占用。
- 登录失败：检查 `.env` 是否挂载成功；修改后执行 `docker compose up -d`。
- AI 连接失败：确认视觉模型、Base URL、Model；Docker 中访问宿主机必须使用 `host.docker.internal`。
- Job 失败：打开“分析任务”查看错误；容器重启会把 processing 任务恢复为 pending。
- 图片重复：同一 SHA256 会提示已有素材；重新上传需通过后端 force 参数或前端重复确认流程。

## 11. 当前 V1 验收边界

已实现个人/单管理员模式、未来 owner_id 预留字段、SQLite Worker、API Key、Docker Compose、ComfyUI 节点、备份导出和自动化 API/数据库/随机/上传测试。多用户权限、真正的导入恢复与高级批量操作留在后续版本。
