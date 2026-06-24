using System;
using System.Drawing;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media.Imaging;
using Huyi.Windows.Models;
using Huyi.Windows.Services;
using Huyi.Windows.Windows;
using Forms = System.Windows.Forms;

namespace Huyi.Windows;

public partial class App : Application
{
    private readonly SettingsService _settingsService = new();
    private readonly ScreenshotService _screenshotService = new();
    private readonly OcrService _ocrService = new();
    private readonly TranslationService _translationService = new();
    private HotKeyService? _hotKeys;
    private Forms.NotifyIcon? _tray;
    private OverlayWindow? _overlay;
    private InputTranslationWindow? _inputTranslationWindow;
    private SettingsWindow? _settingsWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        CreateTray();
        ConfigureHotKeys();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _tray?.Dispose();
        _hotKeys?.Dispose();
        base.OnExit(e);
    }

    private void CreateTray()
    {
        _tray = new Forms.NotifyIcon
        {
            Text = "虎译",
            Icon = SystemIcons.Application,
            Visible = true,
            ContextMenuStrip = new Forms.ContextMenuStrip()
        };
        _tray.DoubleClick += (_, _) => ShowInputTranslation();
        AddTrayItem("截图翻译", TranslateScreenArea);
        AddTrayItem("截图", CaptureScreenshot);
        AddTrayItem("输入翻译", ShowInputTranslation);
        _tray.ContextMenuStrip!.Items.Add(new Forms.ToolStripSeparator());
        AddTrayItem("设置...", OpenSettings);
        AddTrayItem("清除译文", ClearOverlay);
        _tray.ContextMenuStrip!.Items.Add(new Forms.ToolStripSeparator());
        AddTrayItem("退出", () => Shutdown());
    }

    private void AddTrayItem(string title, Action action)
    {
        var item = new Forms.ToolStripMenuItem(title);
        item.Click += (_, _) => Dispatcher.Invoke(action);
        _tray!.ContextMenuStrip!.Items.Add(item);
    }

    private void ConfigureHotKeys()
    {
        _hotKeys?.Dispose();
        _hotKeys = new HotKeyService();
        var settings = _settingsService.Reload();
        try
        {
            _hotKeys.Register(1, settings.TranslateShortcut, () => Dispatcher.Invoke(TranslateScreenArea));
            _hotKeys.Register(2, settings.ScreenshotShortcut, () => Dispatcher.Invoke(CaptureScreenshot));
            _hotKeys.Register(3, settings.InputTranslationShortcut, () => Dispatcher.Invoke(ShowInputTranslation));
        }
        catch (Exception ex)
        {
            MessageBox.Show($"快捷键注册失败：{ex.Message}", "虎译", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private async void TranslateScreenArea()
    {
        try
        {
            ClearOverlay();
            var context = await SelectAreaAsync("拖拽选择要翻译的区域，按 Esc 取消", showsToolbar: false);
            if (context == null || context.Selection.ScreenRect.Width < 2 || context.Selection.ScreenRect.Height < 2)
            {
                return;
            }

            var screenRect = context.Selection.ScreenRect;
            var image = _screenshotService.Crop(context.Screenshot, screenRect, context.VirtualBounds);
            var lines = await _ocrService.RecognizeLinesAsync(image, OcrMode.English);
            if (lines.Count == 0)
            {
                MessageBox.Show("所选区域没有识别到英文文字。", "未识别到文字", MessageBoxButton.OK, MessageBoxImage.Information);
                return;
            }

            var translations = await _translationService.TranslateAsync(
                lines.Select(line => line.Text).ToArray(),
                TranslationDirection.EnglishToChinese,
                _settingsService.Current);
            var items = lines.Zip(translations, (line, translated) =>
                new TranslationOverlayItem(line.Text, translated, line.Bounds)).ToArray();

            _overlay = new OverlayWindow(image, screenRect, context.VirtualBounds, items);
            _overlay.Closed += (_, _) => _overlay = null;
            _overlay.Show();
        }
        catch (Exception ex)
        {
            MessageBox.Show($"翻译失败：{ex.Message}", "虎译", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private async void CaptureScreenshot()
    {
        try
        {
            var context = await SelectAreaAsync("拖拽选择截图区域，调整锚点后点击下方按钮执行操作", showsToolbar: true);
            if (context == null || context.Selection.Action == SelectionAction.Cancel)
            {
                return;
            }

            var selection = context.Selection;
            var capture = new CapturedImage(
                _screenshotService.Crop(context.Screenshot, selection.ScreenRect, context.VirtualBounds),
                selection.ScreenRect);
            switch (selection.Action)
            {
                case SelectionAction.Preview:
                    ShowPreview(capture);
                    break;
                case SelectionAction.Pen:
                    ShowPreview(capture, AnnotationTool.Pen);
                    break;
                case SelectionAction.Arrow:
                    ShowPreview(capture, AnnotationTool.Arrow);
                    break;
                case SelectionAction.Ocr:
                    await ShowOcrPanelAsync(capture);
                    break;
                case SelectionAction.Pin:
                    new PinnedImageWindow(capture.Image, capture.ScreenRect).Show();
                    break;
                case SelectionAction.Copy:
                    ScreenshotService.CopyImage(capture.Image);
                    break;
                case SelectionAction.Save:
                    SaveCapture(capture.Image);
                    break;
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show($"截图失败：{ex.Message}", "虎译", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private sealed record SelectionContext(SelectionResult Selection, BitmapSource Screenshot, Rect VirtualBounds);

    private async Task<SelectionContext?> SelectAreaAsync(string instruction, bool showsToolbar)
    {
        var screenshot = _screenshotService.CaptureVirtualScreen();
        var bounds = _screenshotService.VirtualScreenBounds();
        var window = new SelectionWindow(screenshot, bounds, instruction, showsToolbar);
        window.Show();
        var selection = await window.WaitAsync();
        return selection == null ? null : new SelectionContext(selection, screenshot, bounds);
    }

    private void ShowPreview(CapturedImage capture, AnnotationTool initialTool = AnnotationTool.None)
    {
        var preview = new PreviewWindow(capture.Image, capture.ScreenRect, _ocrService, initialTool);
        preview.PinRequested += (_, image) => new PinnedImageWindow(image, capture.ScreenRect).Show();
        preview.Show();
    }

    private async Task ShowOcrPanelAsync(CapturedImage capture)
    {
        try
        {
            var text = await _ocrService.RecognizeTextAsync(capture.Image, OcrMode.ChineseAndEnglish);
            new TextPanelWindow(string.IsNullOrWhiteSpace(text) ? "未识别到文字。" : text, capture.ScreenRect).Show();
        }
        catch (Exception ex)
        {
            MessageBox.Show($"文字识别失败：{ex.Message}", "虎译", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private static void SaveCapture(BitmapSource image)
    {
        var dialog = new Microsoft.Win32.SaveFileDialog
        {
            Title = "保存截图",
            FileName = "截图.png",
            Filter = "PNG Image|*.png"
        };
        if (dialog.ShowDialog() == true)
        {
            ScreenshotService.SavePng(image, dialog.FileName);
        }
    }

    private void ShowInputTranslation()
    {
        if (_inputTranslationWindow?.IsVisible == true)
        {
            _inputTranslationWindow.Activate();
            return;
        }

        _inputTranslationWindow = new InputTranslationWindow(_translationService, _settingsService);
        _inputTranslationWindow.Closed += (_, _) => _inputTranslationWindow = null;
        _inputTranslationWindow.Show();
    }

    private void OpenSettings()
    {
        if (_settingsWindow?.IsVisible == true)
        {
            _settingsWindow.Activate();
            return;
        }

        _settingsWindow = new SettingsWindow(_settingsService, ConfigureHotKeys);
        _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        _settingsWindow.Show();
    }

    private void ClearOverlay()
    {
        _overlay?.Close();
        _overlay = null;
    }
}
