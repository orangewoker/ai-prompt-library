# ComfyUI Visual Prompt Library

这是 AI Prompt Library 的 ComfyUI 中文插件。它不在本地保存素材，每次执行节点都会从服务器动态读取启用分类和提示词。

## 节点

节点菜单：`Visual Prompt Library/提示词库`

- **视觉提示词库 · 随机抽取**：分类支持 ID、名称、英文逗号/中文逗号分隔；留空或填写“全部分类”表示全部启用分类。多个分类只组成候选池，返回完整素材提示词，不会跨图片拼接。
- **视觉提示词库 · 指定素材**：按素材 ID 获取单条完整提示词。

两个节点均输出：`提示词 STRING`、`素材ID INT`、`分类 STRING`。随机抽取数量大于 1 时，提示词按换行分隔。

## 安装

### 手动安装

将 `ComfyUI-VisualPromptLibrary` 整个目录复制到：

```text
ComfyUI/custom_nodes/ComfyUI-VisualPromptLibrary/
```

然后在 ComfyUI 使用的 Python 环境中安装依赖：

```bash
python -m pip install -r ComfyUI/custom_nodes/ComfyUI-VisualPromptLibrary/requirements.txt
```

Windows 便携版通常使用：

```powershell
python_embeded\python.exe -m pip install -r ComfyUI\custom_nodes\ComfyUI-VisualPromptLibrary\requirements.txt
```

重启 ComfyUI，在节点搜索框输入“视觉提示词库”即可找到节点。

### ComfyUI Manager

也可以把本项目 GitHub 地址作为自定义节点仓库安装；如果 Manager 没有索引该仓库，使用上面的手动安装方式最稳定。

## 连接配置

服务器地址填写 AI Prompt Library 地址，不要带 `/api/v1`：

| ComfyUI 与素材库的位置 | 服务器地址 |
| --- | --- |
| 同一台 Windows 主机直接运行 | `http://127.0.0.1:8765` |
| ComfyUI 在 Docker，素材库在同一台主机 | `http://host.docker.internal:8765` |
| ComfyUI 与素材库都是飞牛 Docker 容器 | `http://飞牛IP:8765`，或同一 Compose 网络中的服务名 |
| ComfyUI 在其他电脑 | `http://素材库所在电脑IP:8765` |

API Key 在网页“系统设置 → ComfyUI 访问密钥”中设置，填入节点的 `API Key`。它对应请求头 `X-API-Key`，不要填写 LM Studio 的 API Key。

## 排查

- 连接失败：先在运行 ComfyUI 的机器上访问 `http://服务器地址/api/v1/health`。
- 401：检查节点 API Key 是否与网页系统设置中的 ComfyUI 密钥一致。
- 没有可用提示词：所选分类必须存在已完成分析且“当前提示词”不为空的素材。
- 修改地址、密钥或网络后重新执行节点即可重新连接；请求超时可将“超时秒数”调大。

所有网络异常都会转换为中文节点错误，不会使 ComfyUI 服务进程崩溃。
