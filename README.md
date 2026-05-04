# 虎译 / LocalScreenTranslator

A small macOS 15.2+ menu bar app for local AI screenshot translation, screenshot capture, OCR, and Chinese-English input translation.

## Features

- `F4` lets you drag a screen area, OCR the English text, translate it with LM Studio, and show the Chinese translation as a transparent overlay.
- `F1` opens a manual screenshot selector. The selector does not auto-detect desktop windows or auto-confirm after resizing.
- The screenshot selector supports corner and edge resize handles, darker outside masking, whole-selection dragging, double-click-to-copy, and a bottom toolbar using the same icon buttons as the screenshot preview.
- The screenshot toolbar supports OCR, pen, arrow, pin, copy, save, and close actions. Pinning creates the pinned image directly and closes the screenshot selector/preview window.
- The `文` button recognizes Chinese Simplified, Chinese Traditional, and English text, then shows the editable OCR text panel.
- The screenshot preview supports pen, arrow, color, pin, copy, save, and close actions. Copying or double-clicking the preview image copies the annotated screenshot and closes the preview.
- `F5` opens an input translation window. Chinese input translates to English; English input translates to Chinese. Mixed Chinese-English text follows the Chinese-to-English rule when Chinese characters are present.
- Pinned screenshots stay above other windows, can be dragged, zoomed with the mouse wheel, copied from the right-click menu, or destroyed.
- Translation overlays disappear when you click, right-click, or scroll.
- The menu bar settings window can change shortcuts, configure the LM Studio endpoint/model/API key, and try to enable launch at login.
- Passive clipboard translation is intentionally disabled to avoid conflicts with shared clipboard tools.
- Uses Apple Vision OCR. Translation defaults to LM Studio at `http://127.0.0.1:1234/v1` with model `local-model`.

## Run From Source

```sh
swift run LocalScreenTranslator
```

The first screen translation may require macOS Screen Recording permission. If the system asks, grant permission and run the app again.

LM Studio translation expects the local server to be enabled with an OpenAI-compatible endpoint. If your loaded model has a different identifier, set it in the app settings.

## Install / Refresh App

```sh
scripts/install_app.sh
open "/Users/trivoid/Applications/虎译.app"
```

The install script builds a release binary, regenerates the tiger app icon, and refreshes `/Users/trivoid/Applications/虎译.app`.

## Notes

This is an MVP for personal use. It is not notarized or App Store ready.

The Swift app in `Sources/LocalScreenTranslator/` is macOS-only. It uses Apple Vision OCR, AppKit, Carbon, and ScreenCaptureKit.

## Windows Version

Windows 原生 WPF 版在 `windows/Huyi.Windows/`。它使用 Windows 内置 OCR、Win32 全局快捷键、Win32 屏幕捕获和 LM Studio OpenAI-compatible 翻译接口。

在 Windows 10/11 x64 且已安装 .NET 8 SDK 的机器上运行：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/package_windows.ps1
```

输出到 `dist/Huyi-Windows-Portable/` 和 `dist/Huyi-Windows-Portable.zip`。
