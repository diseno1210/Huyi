using System;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using Huyi.Windows.Models;
using Huyi.Windows.Services;

namespace Huyi.Windows.Windows;

public sealed class InputTranslationWindow : Window
{
    private readonly TranslationService _translationService;
    private readonly SettingsService _settingsService;
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(350) };
    private readonly TextBox _input = new();
    private readonly TextBlock _status = new();
    private readonly TextBox _result = new();
    private string _latestResult = "";

    public InputTranslationWindow(TranslationService translationService, SettingsService settingsService)
    {
        _translationService = translationService;
        _settingsService = settingsService;

        Title = "输入翻译";
        Width = 540;
        Height = 330;
        Topmost = true;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;

        _timer.Tick += async (_, _) =>
        {
            _timer.Stop();
            await TranslateAsync();
        };

        var root = new DockPanel { Margin = new Thickness(14) };
        var copyButton = new Button
        {
            Content = "复制译文",
            Width = 100,
            Height = 30,
            Margin = new Thickness(0, 8, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Left
        };
        copyButton.Click += (_, _) =>
        {
            if (!string.IsNullOrWhiteSpace(_latestResult))
            {
                Clipboard.SetText(_latestResult);
            }
        };
        DockPanel.SetDock(copyButton, Dock.Bottom);
        root.Children.Add(copyButton);

        var grid = new Grid();
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(104) });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(28) });
        grid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        _input.AcceptsReturn = true;
        _input.TextWrapping = TextWrapping.Wrap;
        _input.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        _input.FontSize = 15;
        _input.TextChanged += (_, _) => ScheduleTranslation();

        _status.Text = "自动检测：中文 ⇄ English";
        _status.Margin = new Thickness(2, 6, 0, 0);
        _status.Foreground = SystemColors.GrayTextBrush;

        _result.Text = "请输入中文或英文。";
        _result.AcceptsReturn = true;
        _result.TextWrapping = TextWrapping.Wrap;
        _result.VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        _result.FontSize = 15;
        _result.IsReadOnly = true;

        Grid.SetRow(_input, 0);
        Grid.SetRow(_status, 1);
        Grid.SetRow(_result, 2);
        grid.Children.Add(_input);
        grid.Children.Add(_status);
        grid.Children.Add(_result);
        root.Children.Add(grid);
        Content = root;
    }

    protected override void OnActivated(EventArgs e)
    {
        base.OnActivated(e);
        _input.Focus();
    }

    private void ScheduleTranslation()
    {
        _timer.Stop();
        var text = _input.Text.Trim();
        if (string.IsNullOrWhiteSpace(text))
        {
            _latestResult = "";
            _status.Text = "自动检测：中文 ⇄ English";
            _result.Text = "请输入中文或英文。";
            return;
        }

        var direction = DetectDirection(text);
        _status.Text = StatusText(direction);
        _result.Text = direction == TranslationDirection.EnglishToChinese ? "正在翻译为中文..." : "Translating to English...";
        _timer.Start();
    }

    private async Task TranslateAsync()
    {
        var text = _input.Text.Trim();
        if (string.IsNullOrWhiteSpace(text)) return;

        var direction = DetectDirection(text);
        try
        {
            var result = (await _translationService.TranslateAsync([text], direction, _settingsService.Current)).FirstOrDefault() ?? "";
            if (text != _input.Text.Trim()) return;
            _latestResult = result;
            _status.Text = StatusText(direction);
            _result.Text = result;
        }
        catch (Exception ex)
        {
            _latestResult = "";
            _status.Text = StatusText(direction);
            _result.Text = $"LM Studio 翻译失败：{ex.Message}";
        }
    }

    private static TranslationDirection DetectDirection(string text) =>
        Regex.IsMatch(text, @"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
            ? TranslationDirection.ChineseToEnglish
            : TranslationDirection.EnglishToChinese;

    private static string StatusText(TranslationDirection direction) =>
        direction == TranslationDirection.EnglishToChinese
            ? "检测为 English，译文输出中文"
            : "检测为中文，译文输出 English";
}
