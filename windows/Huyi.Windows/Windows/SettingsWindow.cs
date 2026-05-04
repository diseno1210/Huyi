using System.Windows;
using System.Windows.Controls;
using Huyi.Windows.Models;
using Huyi.Windows.Services;

namespace Huyi.Windows.Windows;

public sealed class SettingsWindow : Window
{
    private readonly SettingsService _settingsService;
    private readonly Action _onChanged;
    private readonly ComboBox _translateShortcut = new();
    private readonly ComboBox _screenshotShortcut = new();
    private readonly ComboBox _inputShortcut = new();
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
        Width = 500;
        Height = 468;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        var root = new Grid { Margin = new Thickness(28, 22, 28, 20) };
        for (var i = 0; i < 10; i++)
        {
            root.RowDefinitions.Add(new RowDefinition { Height = i is 0 or 4 ? new GridLength(38) : new GridLength(42) });
        }
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        AddSection(root, "快捷键", 0);
        AddRow(root, "截图翻译快捷键", _translateShortcut, 1);
        AddRow(root, "截图快捷键", _screenshotShortcut, 2);
        AddRow(root, "输入翻译快捷键", _inputShortcut, 3);

        AddSection(root, "LM Studio", 4);
        AddRow(root, "Base URL", _baseUrl, 5);
        AddRow(root, "Model", _model, 6);
        AddRow(root, "API Key", _apiKey, 7);
        AddRow(root, "超时（秒）", _timeout, 8);

        var bottom = new DockPanel();
        var save = new Button
        {
            Content = "保存",
            Width = 90,
            Height = 30,
            HorizontalAlignment = HorizontalAlignment.Right
        };
        save.Click += (_, _) => Save();
        DockPanel.SetDock(save, Dock.Right);
        bottom.Children.Add(save);
        bottom.Children.Add(_launchAtLogin);
        Grid.SetRow(bottom, 9);
        Grid.SetColumnSpan(bottom, 2);
        root.Children.Add(bottom);

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
        control.Height = control is ComboBox ? 30 : 26;

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
        FillShortcuts(_translateShortcut, settings.TranslateShortcut);
        FillShortcuts(_screenshotShortcut, settings.ScreenshotShortcut);
        FillShortcuts(_inputShortcut, settings.InputTranslationShortcut);
        _baseUrl.Text = settings.LmStudioBaseUrl;
        _model.Text = settings.LmStudioModel;
        _apiKey.Password = settings.LmStudioApiKey;
        _timeout.Text = settings.LmStudioTimeoutSeconds.ToString();
        _launchAtLogin.IsChecked = StartupService.IsEnabled();
    }

    private static void FillShortcuts(ComboBox comboBox, string selected)
    {
        comboBox.Items.Clear();
        foreach (var preset in ShortcutParser.Presets)
        {
            comboBox.Items.Add(preset);
        }
        comboBox.SelectedItem = ShortcutParser.Presets.Contains(selected) ? selected : ShortcutParser.Presets[0];
    }

    private void Save()
    {
        var translate = _translateShortcut.SelectedItem?.ToString() ?? "F4";
        var screenshot = _screenshotShortcut.SelectedItem?.ToString() ?? "F1";
        var input = _inputShortcut.SelectedItem?.ToString() ?? "F5";
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
