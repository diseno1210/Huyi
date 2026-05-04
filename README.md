# 虎译 / LocalScreenTranslator

A small macOS 15.2+ menu bar app for local AI screenshot translation, screenshot capture, OCR, and Chinese-English input translation.

## Features

- `F4` lets you drag a screen area, OCR the English text, translate it with local oMLX first, and show the Chinese translation as a transparent overlay.
- `F1` opens a manual screenshot selector. The selector does not auto-detect desktop windows or auto-confirm after resizing.
- The screenshot selector supports corner and edge resize handles, darker outside masking, whole-selection dragging, double-click-to-copy, and a bottom toolbar using the same icon buttons as the screenshot preview.
- The screenshot toolbar supports OCR, pen, arrow, pin, copy, save, and close actions. Pinning creates the pinned image directly and closes the screenshot selector/preview window.
- The `文` button recognizes Chinese Simplified, Chinese Traditional, and English text, then shows the editable OCR text panel.
- The screenshot preview supports pen, arrow, color, pin, copy, save, and close actions. Copying or double-clicking the preview image copies the annotated screenshot and closes the preview.
- `F5` opens an input translation window. Chinese input translates to English; English input translates to Chinese. Mixed Chinese-English text follows the Chinese-to-English rule when Chinese characters are present.
- Pinned screenshots stay above other windows, can be dragged, zoomed with the mouse wheel, copied from the right-click menu, or destroyed.
- Translation overlays disappear when you click, right-click, or scroll.
- The menu bar settings window can change shortcuts, choose the translation engine, configure the local oMLX endpoint/model/API key, and try to enable launch at login.
- Passive clipboard translation is intentionally disabled to avoid conflicts with shared clipboard tools.
- Uses Apple Vision OCR. Translation defaults to local oMLX at `http://127.0.0.1:8000/v1` with model `gemma-4-e4b-it-4bit`, and can fall back to Apple Translation Framework when local AI is unavailable.

## Run From Source

```sh
swift run LocalScreenTranslator
```

The first screen translation may require macOS Screen Recording permission. If the system asks, grant permission and run the app again.

Local AI translation expects an OpenAI-compatible oMLX server. Apple Translation may also need the English/Chinese language assets installed before fallback translation can run fully offline.

## Install / Refresh App

```sh
scripts/install_app.sh
open "/Users/trivoid/Applications/虎译.app"
```

The install script builds a release binary, regenerates the tiger app icon, and refreshes `/Users/trivoid/Applications/虎译.app`.

## Notes

This is an MVP for personal use. It is not notarized or App Store ready.

This app is macOS-only. It uses Apple Vision OCR, Apple Translation Framework, AppKit, Carbon, and ScreenCaptureKit; the current source cannot be directly packaged as a Windows portable app.
