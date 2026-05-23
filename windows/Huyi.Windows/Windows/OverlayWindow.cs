using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Huyi.Windows.Models;

namespace Huyi.Windows.Windows;

public sealed class OverlayWindow : Window
{
    public OverlayWindow(Rect screenRect, IReadOnlyList<TranslationOverlayItem> items)
    {
        Left = screenRect.Left;
        Top = screenRect.Top;
        Width = screenRect.Width;
        Height = screenRect.Height;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        Focusable = false;

        var canvas = new Canvas();
        foreach (var item in items)
        {
            var text = new TextBlock
            {
                Text = item.TargetText,
                Foreground = Brushes.White,
                Background = new SolidColorBrush(Color.FromArgb(218, 20, 20, 20)),
                TextWrapping = TextWrapping.Wrap,
                Padding = new Thickness(7, 5, 7, 5),
                MaxWidth = Math.Max(160, item.Bounds.Width * 1.6),
                FontSize = 15,
                FontWeight = FontWeights.SemiBold
            };
            Canvas.SetLeft(text, item.Bounds.Left);
            Canvas.SetTop(text, Math.Max(0, item.Bounds.Top - 2));
            canvas.Children.Add(text);
        }
        Content = canvas;

        MouseDown += (_, _) => Close();
        MouseWheel += (_, _) => Close();
        PreviewMouseRightButtonDown += (_, _) => Close();
        Deactivated += (_, _) => Close();
    }
}
