using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Huyi.Windows.Models;
using Huyi.Windows.Services;

namespace Huyi.Windows.Windows;

public sealed class SettingsWindow : Window
{
    private readonly SettingsService _settingsService;
    private readonly Action _onChanged;
    private readonly HotKeyRecorderBox _translateShortcut = new();
    private readonly HotKeyRecorderBox _screenshotShortcut = new();
    private readonly HotKeyRecorderBox _inputShortcut = new();
    private readonly TextBox _baseUrl = new();
    private readonly TextBox _model = new();
    private readonly PasswordBox _apiKey = new();
    private readonly TextBox _timeout = new();
    private readonly CheckBox _launchAtLogin = new() { Content = "开机启动" };

    public SettingsWindow(SettingsService settingsService, Action onChanged)
    {
        _settingsService = settingsService;
        _onChanged = onChanged;

        Title = "设置";
        Width = 520;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        var root = new DockPanel { Margin = new Thickness(28, 22, 28, 18), LastChildFill = true };

        // Bottom bar is added first so it always reserves space and stays visible.
        var bottom = new DockPanel { Margin = new Thickness(0, 18, 0, 0) };
        DockPanel.SetDock(bottom, Dock.Bottom);
        var save = new Button
        {
            Content = "保存",
            Width = 96,
            Height = 32,
            HorizontalAlignment = HorizontalAlignment.Right
        };
        save.Click += (_, _) => Save();
        DockPanel.SetDock(save, Dock.Right);
        _launchAtLogin.VerticalAlignment = VerticalAlignment.Center;
        bottom.Children.Add(save);
        bottom.Children.Add(_launchAtLogin);
        root.Children.Add(bottom);

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        for (var i = 0; i < 9; i++)
        {
            grid.RowDefinitions.Add(new RowDefinition { Height = i is 0 or 4 ? new GridLength(40) : new GridLength(44) });
        }

        AddSection(grid, "快捷键（点击后按下组合键）", 0);
        AddRow(grid, "截图翻译快捷键", _translateShortcut, 1);
        AddRow(grid, "截图快捷键", _screenshotShortcut, 2);
        AddRow(grid, "输入翻译快捷键", _inputShortcut, 3);

        AddSection(grid, "LM Studio", 4);
        AddRow(grid, "Base URL", _baseUrl, 5);
        AddRow(grid, "Model", _model, 6);
        AddRow(grid, "API Key", _apiKey, 7);
        AddRow(grid, "超时（秒）", _timeout, 8);

        root.Children.Add(grid);
        Content = root;
        LoadSettings();
    }

    private static void AddSection(Grid grid, string text, int row)
    {
        var label = new TextBlock
        {
            Text = text,
            FontWeight = FontWeights.SemiBold,
            FontSize = 15,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetRow(label, row);
        Grid.SetColumnSpan(label, 2);
        grid.Children.Add(label);
    }

    private static void AddRow(Grid grid, string labelText, Control control, int row)
    {
        var label = new TextBlock
        {
            Text = labelText,
            FontWeight = FontWeights.Medium,
            VerticalAlignment = VerticalAlignment.Center
        };
        control.VerticalAlignment = VerticalAlignment.Center;
        control.Height = control is HotKeyRecorderBox ? 30 : 26;

        Grid.SetRow(label, row);
        Grid.SetColumn(label, 0);
        Grid.SetRow(control, row);
        Grid.SetColumn(control, 1);
        grid.Children.Add(label);
        grid.Children.Add(control);
    }

    private void LoadSettings()
    {
        var settings = _settingsService.Reload();
        _translateShortcut.SetShortcut(settings.TranslateShortcut);
        _screenshotShortcut.SetShortcut(settings.ScreenshotShortcut);
        _inputShortcut.SetShortcut(settings.InputTranslationShortcut);
        _baseUrl.Text = settings.LmStudioBaseUrl;
        _model.Text = settings.LmStudioModel;
        _apiKey.Password = settings.LmStudioApiKey;
        _timeout.Text = settings.LmStudioTimeoutSeconds.ToString();
        _launchAtLogin.IsChecked = StartupService.IsEnabled();
    }

    private void Save()
    {
        var translate = _translateShortcut.Shortcut;
        var screenshot = _screenshotShortcut.Shortcut;
        var input = _inputShortcut.Shortcut;
        if (new[] { translate, screenshot, input }.Any(string.IsNullOrWhiteSpace))
        {
            MessageBox.Show(this, "请为三个功能都设置快捷键。", "快捷键缺失", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        if (new[] { translate, screenshot, input }.Distinct().Count() != 3)
        {
            MessageBox.Show(this, "截图翻译、截图、输入翻译三个快捷键不能相同。", "快捷键冲突", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var settings = new AppSettings
        {
            TranslateShortcut = translate,
            ScreenshotShortcut = screenshot,
            InputTranslationShortcut = input,
            LmStudioBaseUrl = _baseUrl.Text,
            LmStudioModel = _model.Text,
            LmStudioApiKey = _apiKey.Password,
            LmStudioTimeoutSeconds = int.TryParse(_timeout.Text, out var timeout) ? timeout : 20,
            LaunchAtLogin = _launchAtLogin.IsChecked == true
        };

        _settingsService.Save(settings);
        StartupService.SetEnabled(settings.LaunchAtLogin);
        _onChanged();
        Close();
    }
}

/// <summary>
/// A read-only box that records a global-hotkey combination when focused:
/// click it, then press the desired modifier(s) plus a letter or function key.
/// </summary>
public sealed class HotKeyRecorderBox : TextBox
{
    private const string Placeholder = "点击后按下快捷键";

    public string Shortcut { get; private set; } = "";

    public HotKeyRecorderBox()
    {
        IsReadOnly = true;
        IsReadOnlyCaretVisible = false;
        Cursor = Cursors.Hand;
        Focusable = true;
        VerticalContentAlignment = VerticalAlignment.Center;
        ToolTip = "点击后按下组合键，例如 Ctrl+Alt+T 或 F4；按 Esc 取消";
        PreviewKeyDown += OnPreviewKeyDown;
        GotKeyboardFocus += (_, _) => SelectAll();
    }

    public void SetShortcut(string shortcut)
    {
        Shortcut = shortcut ?? "";
        Text = string.IsNullOrWhiteSpace(Shortcut) ? Placeholder : Shortcut;
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        e.Handled = true;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;

        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt
            or Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin)
        {
            return;
        }

        if (key == Key.Escape)
        {
            SetShortcut(Shortcut);
            return;
        }

        var keyName = KeyName(key);
        if (keyName == null)
        {
            return;
        }

        var modifiers = Keyboard.Modifiers;
        var parts = new List<string>();
        if (modifiers.HasFlag(ModifierKeys.Control)) parts.Add("Ctrl");
        if (modifiers.HasFlag(ModifierKeys.Alt)) parts.Add("Alt");
        if (modifiers.HasFlag(ModifierKeys.Shift)) parts.Add("Shift");
        if (modifiers.HasFlag(ModifierKeys.Windows)) parts.Add("Win");

        var isFunctionKey = keyName.Length > 1;
        if (!isFunctionKey && parts.Count == 0)
        {
            // A bare letter would hijack that key system-wide; require a modifier.
            return;
        }

        parts.Add(keyName);
        var candidate = string.Join("+", parts);
        try
        {
            ShortcutParser.Parse(candidate);
            SetShortcut(candidate);
        }
        catch
        {
            // Unsupported combination; keep the previous value.
        }
    }

    private static string? KeyName(Key key)
    {
        if (key is >= Key.F1 and <= Key.F24)
        {
            return "F" + (key - Key.F1 + 1);
        }
        if (key is >= Key.A and <= Key.Z)
        {
            return key.ToString();
        }
        return null;
    }
}
