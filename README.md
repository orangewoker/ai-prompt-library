# AI Prompt Library

AI Prompt Library 是一个可自托管的图片提示词素材库：上传图片，调用 OpenAI Compatible 视觉模型提取完整提示词，把图片、原始分析和可编辑提示词长期绑定管理，并通过 ComfyUI 或 AI-Lib iOS 客户端复用素材。

## 功能

- 图片单选、多选、文件夹导入和粘贴上传
- 图片压缩、缩略图、SHA256 去重和后台分析任务
- 分类素材库、搜索、编辑、恢复 AI 原文、重新分析和删除
- 多分类随机抽取完整提示词，支持可复现 Seed
- OpenAI Compatible Provider，兼容 LM Studio 等服务
- 管理员账号、分类权限、系统提示词模板、ComfyUI 密钥和备份导出
- ComfyUI 中文节点：随机抽取、指定素材
- AI-Lib iOS 客户端：图片分析、服务端管理、长按保存素材到相册

## 快速启动

复制示例环境变量并修改密码和密钥：

```powershell
Copy-Item .env.example .env
# 编辑 .env，至少修改 ADMIN_PASSWORD、API_KEY、COMFYUI_API_KEY
docker compose up -d --build
docker compose ps
```

浏览器访问 `http://localhost:8765`。默认账号名由 `ADMIN_USERNAME` 设置，首次运行后请立即修改示例密码。

数据持久化在 `./data`，包括 SQLite、图片、缩略图、备份和导出文件。不要提交 `.env`、`data/`、`release/` 或任何真实密钥。

## 本地开发

后端需要 Python 3.12：

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

Vite 开发服务器会把 `/api` 和 `/media` 转发到后端。

## AI Provider

Provider 使用 OpenAI Compatible API。Docker 中连接宿主机服务时使用 Docker 可解析的宿主机地址；直接在宿主机开发时使用服务实际监听地址。API Key 只在服务端保存，网页和 iOS 客户端只显示掩码。

上传素材时选择分类、Provider、模型和提示词模板。上传请求不会等待模型分析，后台 Job 完成后会写入 `ai_original_text` 和 `prompt_text`。

## ComfyUI 插件

插件目录：`comfyui_plugin/ComfyUI-VisualPromptLibrary`。

```bash
pip install -r comfyui_plugin/ComfyUI-VisualPromptLibrary/requirements.txt
```

将插件目录复制到 `ComfyUI/custom_nodes/` 并重启 ComfyUI。服务器地址填写部署服务的根地址，不要附加 `/api/v1`；API Key 使用网页“系统设置”中的 ComfyUI 密钥。

## AI-Lib iOS

完整工程位于 `ios` 分支的 `mobile/ai_lib_ios`。iPhone 不能访问电脑的 `127.0.0.1`，请在客户端填写服务端所在电脑或 NAS 的局域网地址。客户端支持上传分析、素材编辑、Provider/模板/分类/任务/用户管理、备份导出和长按保存图片到系统相册。

Windows 本地检查：

```powershell
git switch ios
cd mobile/ai_lib_ios
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

iOS 未签名 IPA 由 `.github/workflows/ios-build.yml` 在 macOS runner 上构建。工作流使用 `flutter build ios --release --no-codesign`，不会加入证书或 provisioning profile。

## API

统一前缀为 `/api/v1`，主要路由包括：`health`、`auth/login`、`categories`、`assets`、`providers`、`prompt-profiles`、`jobs`、`random`、`export`、`backup`。

```bash
curl http://localhost:8765/api/v1/health
curl -H "X-API-Key: <API_KEY>" http://localhost:8765/api/v1/categories
curl -X POST http://localhost:8765/api/v1/random \
  -H "Content-Type: application/json" \
  -H "X-API-Key: <API_KEY>" \
  -d '{"category_ids":[1],"count":1,"seed":123456}'
```

## 飞牛 OS / NAS

使用 `docker-compose.fnos.yml`，把宿主机数据目录映射到 `/app/data`，并通过 `.env` 注入配置。升级前先从网页下载完整备份，再执行 `docker compose pull && docker compose up -d`。

## 安全与隐私

- `.env` 仅用于本地部署，不提交仓库。
- Provider API Key 不返回明文，日志不记录完整密钥。
- 公开仓库只包含占位配置和文档示例，不包含真实服务商地址、真实 Token 或真实密码。
- 如果曾经把真实密钥提交到 Git，请立即撤销并重新生成；仅删除文件不能使旧提交中的密钥失效。

## 许可证

见 [LICENSE](LICENSE)。
