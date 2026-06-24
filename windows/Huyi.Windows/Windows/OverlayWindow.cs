using System;
using System.Collections.Generic;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Huyi.Windows.Models;

namespace Huyi.Windows.Windows;

public sealed class OverlayWindow : Window
{
    private sealed record Entry(Border Box, TextBlock Text, string Source, string Target, double Width, double Height);

    private readonly List<Entry> _entries = new();
    private readonly Image _originalView;
    private readonly ToolChip _imageChip;
    private readonly ToolChip _sourceChip;
    private readonly Border _toolbar;

    public OverlayWindow(BitmapSource originalImage, Rect captureScreenRect, Rect virtualBounds, IReadOnlyList<TranslationOverlayItem> items)
    {
        Left = virtualBounds.Left;
        Top = virtualBounds.Top;
        Width = virtualBounds.Width;
        Height = virtualBounds.Height;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        ResizeMode = ResizeMode.NoResize;

        var offsetX = captureScreenRect.Left - virtualBounds.Left;
        var offsetY = captureScreenRect.Top - virtualBounds.Top;

        var canvas = new Canvas { Background = Brushes.Transparent };

        _originalView = new Image
        {
            Source = originalImage,
            Width = captureScreenRect.Width,
            Height = captureScreenRect.Height,
            Stretch = Stretch.Fill,
            Visibility = Visibility.Collapsed
        };
        Canvas.SetLeft(_originalView, offsetX);
        Canvas.SetTop(_originalView, offsetY);
        canvas.Children.Add(_originalView);

        foreach (var item in items)
        {
            var rect = item.Bounds;
            var width = Math.Max(rect.Width + 10, 64);
            var height = Math.Max(rect.Height + 6, 22);
            var box = new Border
            {
                Background = new SolidColorBrush(Color.FromArgb(0xC2, 0x16, 0x16, 0x16)),
                CornerRadius = new CornerRadius(5),
                Width = width,
                Height = height,
                ClipToBounds = true
            };
            var text = new TextBlock
            {
                Text = item.TargetText,
                Foreground = Brushes.White,
                FontFamily = new FontFamily("Microsoft YaHei UI"),
                FontWeight = FontWeights.SemiBold,
                TextWrapping = TextWrapping.Wrap,
                TextTrimming = TextTrimming.CharacterEllipsis,
                Margin = new Thickness(6, 3, 6, 3),
                FontSize = FitFontSize(item.TargetText, width, height)
            };
            box.Child = text;
            Canvas.SetLeft(box, offsetX + rect.Left - 5);
            Canvas.SetTop(box, offsetY + rect.Top - 3);
            canvas.Children.Add(box);
            _entries.Add(new Entry(box, text, item.SourceText, item.TargetText, width, height));
        }

        _imageChip = new ToolChip("原图模式", "显示原图，隐藏译文") { IsToggle = true };
        _sourceChip = new ToolChip("原文", "切换显示识别到的原文") { IsToggle = true };
        var resetChip = new ToolChip("重置", "恢复默认译文显示");
        var closeChip = new ToolChip("✕", "关闭译文");
        _imageChip.Click += UpdateView;
        _sourceChip.Click += UpdateView;
        resetChip.Click += () =>
        {
            _imageChip.IsActive = false;
            _sourceChip.IsActive = false;
            UpdateView();
        };
        closeChip.Click += Close;
        _toolbar = ToolbarChrome.Bar(_imageChip, _sourceChip, resetChip, closeChip);
        canvas.Children.Add(_toolbar);

        Content = canvas;

        PreviewMouseDown += (_, e) =>
        {
            if (!IsInToolbar(e.OriginalSource as DependencyObject))
            {
                Close();
            }
        };
        PreviewMouseWheel += (_, _) => Close();
        KeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape)
            {
                Close();
            }
        };

        Loaded += (_, _) => PositionToolbar(offsetX, offsetY, captureScreenRect);
    }

    private void PositionToolbar(double offsetX, double offsetY, Rect captureScreenRect)
    {
        _toolbar.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var size = _toolbar.DesiredSize;
        var left = offsetX;
        var top = offsetY + captureScreenRect.Height + 10;
        if (top + size.Height > Height)
        {
            top = offsetY - size.Height - 10;
        }
        left = Math.Max(6, Math.Min(left, Width - size.Width - 6));
        top = Math.Max(6, Math.Min(top, Height - size.Height - 6));
        Canvas.SetLeft(_toolbar, left);
        Canvas.SetTop(_toolbar, top);
    }

    private void UpdateView()
    {
        var showImage = _imageChip.IsActive;
        var showSource = _sourceChip.IsActive;
        _originalView.Visibility = showImage ? Visibility.Visible : Visibility.Collapsed;
        foreach (var entry in _entries)
        {
            entry.Box.Visibility = showImage ? Visibility.Collapsed : Visibility.Visible;
            var content = showSource ? entry.Source : entry.Target;
            entry.Text.Text = content;
            entry.Text.FontSize = FitFontSize(content, entry.Width, entry.Height);
        }
    }

    private bool IsInToolbar(DependencyObject? node)
    {
        while (node != null)
        {
            if (ReferenceEquals(node, _toolbar))
            {
                return true;
            }
            node = VisualTreeHelper.GetParent(node) ?? LogicalTreeHelper.GetParent(node);
        }
        return false;
    }

    private static double FitFontSize(string text, double width, double height)
    {
        if (string.IsNullOrEmpty(text))
        {
            return 13;
        }

        var typeface = new Typeface(new FontFamily("Microsoft YaHei UI"), FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal);
        var max = Math.Min(Math.Max(height * 0.56, 10), 17);
        for (var size = max; size > 9; size -= 1)
        {
            var formatted = new FormattedText(
                text,
                CultureInfo.CurrentUICulture,
                FlowDirection.LeftToRight,
                typeface,
                size,
                Brushes.White,
                1.0)
            {
                MaxTextWidth = Math.Max(1, width - 12)
            };
            if (formatted.Height <= height - 6)
            {
                return size;
            }
        }
        return 9;
    }
}
