using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Huyi.Windows.Services;

namespace Huyi.Windows.Windows;

public sealed class PinnedImageWindow : Window
{
    private readonly BitmapSource _image;
    private readonly ScaleTransform _scale = new(1, 1);
    private Point _dragStart;
    private bool _dragging;

    public PinnedImageWindow(BitmapSource image, Rect? near = null)
    {
        _image = image;
        Width = Math.Min(720, image.Width);
        Height = Math.Min(520, image.Height);
        Left = near?.Left + 18 ?? 120;
        Top = near?.Top + 18 ?? 120;
        Topmost = true;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;

        var border = new Border
        {
            BorderBrush = Brushes.DodgerBlue,
            BorderThickness = new Thickness(1),
            Background = Brushes.White,
            Child = new Image
            {
                Source = image,
                Stretch = Stretch.Uniform,
                RenderTransform = _scale,
                RenderTransformOrigin = new Point(0.5, 0.5)
            }
        };
        Content = border;

        var menu = new ContextMenu();
        var copy = new MenuItem { Header = "复制图片" };
        copy.Click += (_, _) => ScreenshotService.CopyImage(_image);
        var close = new MenuItem { Header = "关闭" };
        close.Click += (_, _) => Close();
        menu.Items.Add(copy);
        menu.Items.Add(close);
        ContextMenu = menu;

        MouseLeftButtonDown += (_, e) =>
        {
            _dragging = true;
            _dragStart = e.GetPosition(this);
            CaptureMouse();
        };
        MouseMove += (_, e) =>
        {
            if (!_dragging) return;
            var point = PointToScreen(e.GetPosition(this));
            Left = point.X - _dragStart.X;
            Top = point.Y - _dragStart.Y;
        };
        MouseLeftButtonUp += (_, _) =>
        {
            _dragging = false;
            ReleaseMouseCapture();
        };
        MouseWheel += (_, e) =>
        {
            var factor = e.Delta > 0 ? 1.08 : 0.92;
            _scale.ScaleX = Math.Clamp(_scale.ScaleX * factor, 0.25, 4);
            _scale.ScaleY = _scale.ScaleX;
        };
    }
}
