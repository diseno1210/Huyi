# 虎译 Windows

Windows 原生 WPF 版虎译。它与 macOS 版保持同一功能目标，但平台实现独立。

## 功能

- `F4` 区域截图翻译：截图、英文 OCR、LM Studio 翻译、透明浮层显示译文。
- `F1` 截图工具：选区、调整、OCR、画笔、箭头、钉图、复制、保存。
- `F5` 输入翻译：中文自动译英，英文自动译中。
- 托盘菜单：截图翻译、截图、输入翻译、设置、清除译文、退出。
- 设置保存到 `%APPDATA%\Huyi\settings.json`。

## LM Studio

默认使用 OpenAI-compatible endpoint：

```text
http://127.0.0.1:1234/v1
```

默认模型名：

```text
local-model
```

如果 LM Studio 中显示的 model id 不同，请在设置页里修改。

## OCR

OCR 使用 Windows 内置 OCR。若提示 OCR 不可用，请在 Windows 设置中安装英文/中文语言能力。

## 打包

在 Windows 10/11 x64 且已安装 .NET 8 SDK 的机器上运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/package_windows.ps1
```

输出：

- `dist/Huyi-Windows-Portable/`
- `dist/Huyi-Windows-Portable.zip`
