# AI-Lib iOS

AI Prompt Library 的原生 Flutter iOS 客户端，直接连接现有 FastAPI 服务端。

## 功能

- 登录并保存服务地址与会话
- 仪表盘、素材库筛选与搜索
- 从照片库多选图片或相机拍摄，选择分类、AI 服务、模型和提示词模板后上传分析
- 查看、编辑、复制、恢复、重新分析、移动和删除素材
- 长按素材卡片或详情图片，将图片保存到 iOS 系统相册
- 多分类随机抽取完整提示词和可复现 Seed
- 分类、AI Provider、模型、系统提示词模板、任务、备份导出、账号和 ComfyUI 密钥管理

## 连接服务端

iPhone 无法访问 Windows 的 `127.0.0.1`。服务在电脑或 NAS 上运行时，填写局域网地址，例如：

```text
http://192.168.1.10:8765
```

不要在地址末尾填写 `/api/v1`；即使填写，客户端也会自动移除。

## 本地检查（Windows）

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
```

iOS 二进制由仓库的 `.github/workflows/ios-build.yml` 在 macOS runner 上编译。工作流执行 `flutter build ios --release --no-codesign`，打包并发布 `AI-Lib-<VERSION>-unsigned.ipa`。IPA 不包含证书或 provisioning profile，需要由侧载工具重新签名。
