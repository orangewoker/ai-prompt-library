# ComfyUI Visual Prompt Library

将本目录复制到 `ComfyUI/custom_nodes/`，重启 ComfyUI 即可。在节点菜单 `Visual Prompt Library/提示词库` 下提供：

- **视觉提示词库 · 随机抽取**：分类填写分类 ID 或名称，多个分类用英文逗号分隔；服务端返回的是一条条完整提示词，不会拼接不同素材。
- **视觉提示词库 · 指定素材**：按素材 ID 获取提示词。

首次安装：

```bash
pip install -r requirements.txt
```

服务器地址填写 AI Prompt Library 地址，例如 `http://localhost:8765`。API Key 可在网页“系统设置 → ComfyUI 访问密钥”中设置，或使用 `.env` 的 `COMFYUI_API_KEY` 初始值，与节点中的 `X-API-Key` 保持一致。网络错误会以中文节点错误提示，不会让 ComfyUI 崩溃。
