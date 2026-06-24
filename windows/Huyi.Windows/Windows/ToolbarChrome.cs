using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace Huyi.Windows.Windows;

/// <summary>
/// A flat, dark toolbar button used by the screenshot and translation overlays.
/// Supports an optional toggle state with a highlighted background.
/// </summary>
public sealed class ToolChip : Border
{
    private static readonly Brush ActiveBrush = new SolidColorBrush(Color.FromRgb(0x2D, 0x7D, 0xFF));
    private static readonly Brush HoverBrush = new SolidColorBrush(Color.FromArgb(0x4D, 0xFF, 0xFF, 0xFF));

    private readonly TextBlock _label;
    private bool _active;

    public event Action? Click;

    public bool IsToggle { get; init; }

    public bool IsActive
    {
        get => _active;
        set
        {
            _active = value;
            Refresh(IsMouseOver);
        }
    }

    public ToolChip(string text, string tooltip)
    {
        _label = new TextBlock
        {
            Text = text,
            Foreground = Brushes.White,
            FontFamily = new FontFamily("Microsoft YaHei UI"),
            FontSize = 13,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center
        };
        Child = _label;
        Padding = new Thickness(11, 6, 11, 6);
        CornerRadius = new CornerRadius(5);
        Margin = new Thickness(2, 0, 2, 0);
        Background = Brushes.Transparent;
        Cursor = Cursors.Hand;
        ToolTip = tooltip;
        SnapsToDevicePixels = true;

        MouseEnter += (_, _) => Refresh(true);
        MouseLeave += (_, _) => Refresh(false);
        MouseLeftButtonDown += (_, e) => e.Handled = true;
        MouseLeftButtonUp += (_, e) =>
        {
            e.Handled = true;
            if (IsToggle)
            {
                _active = !_active;
            }
            Refresh(IsMouseOver);
            Click?.Invoke();
        };
    }

    public void SetText(string text) => _label.Text = text;

    private void Refresh(bool hover)
    {
        Background = _active ? ActiveBrush : hover ? HoverBrush : Brushes.Transparent;
    }
}

public static class ToolbarChrome
{
    public static Border Bar(params UIElement[] children)
    {
        var stack = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var child in children)
        {
            stack.Children.Add(child);
        }

        var bar = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(0xF0, 0x23, 0x23, 0x23)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(9),
            Padding = new Thickness(5),
            Child = stack,
            Effect = new DropShadowEffect
            {
                BlurRadius = 14,
                ShadowDepth = 2,
                Opacity = 0.45,
                Color = Colors.Black
            }
        };
        bar.MouseLeftButtonDown += (_, e) => e.Handled = true;
        return bar;
    }
}
