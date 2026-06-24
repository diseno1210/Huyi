using System;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Huyi.Windows.Models;

namespace Huyi.Windows.Windows;

public sealed class SelectionWindow : Window
{
    private readonly TaskCompletionSource<SelectionResult?> _completion = new();
    private readonly Rect _virtualBounds;
    private readonly SelectionCanvas _canvas;

    public SelectionWindow(BitmapSource screenshot, Rect virtualBounds, string instruction, bool showsToolbar)
    {
        _virtualBounds = virtualBounds;
        Left = virtualBounds.Left;
        Top = virtualBounds.Top;
        Width = virtualBounds.Width;
        Height = virtualBounds.Height;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        Cursor = Cursors.Cross;

        _canvas = new SelectionCanvas(screenshot, instruction, showsToolbar);
        _canvas.Completed += (_, result) => Finish(result);
        Content = _canvas;

        KeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape)
            {
                Finish(null);
            }
        };
        Loaded += (_, _) =>
        {
            Focus();
            Activate();
        };
    }

    public Task<SelectionResult?> WaitAsync() => _completion.Task;

    private void Finish(SelectionResult? result)
    {
        if (result != null)
        {
            var rect = result.ScreenRect;
            result = result with { ScreenRect = new Rect(rect.X + _virtualBounds.X, rect.Y + _virtualBounds.Y, rect.Width, rect.Height) };
        }
        _completion.TrySetResult(result);
        Close();
    }
}

public sealed class SelectionCanvas : Canvas
{
    private const double HandleSize = 9;
    private readonly BitmapSource _screenshot;
    private readonly string _instruction;
    private readonly Border? _toolbar;
    private Rect _selection;
    private Point _start;
    private DragMode _dragMode = DragMode.None;

    public event EventHandler<SelectionResult>? Completed;

    public SelectionCanvas(BitmapSource screenshot, string instruction, bool showsToolbar)
    {
        _screenshot = screenshot;
        _instruction = instruction;
        Focusable = true;
        Background = Brushes.Transparent;
        ClipToBounds = true;
        MouseLeftButtonDown += OnMouseDown;
        MouseMove += OnMouseMove;
        MouseLeftButtonUp += OnMouseUp;
        MouseRightButtonDown += (_, _) => Completed?.Invoke(this, new SelectionResult(SelectionAction.Cancel, Rect.Empty));
        MouseDown += (_, e) =>
        {
            if (ReferenceEquals(e.OriginalSource, this)
                && e.ClickCount == 2
                && _selection.Width > 2
                && _selection.Height > 2)
            {
                Completed?.Invoke(this, new SelectionResult(SelectionAction.Copy, _selection));
            }
        };

        if (showsToolbar)
        {
            _toolbar = ToolbarChrome.Bar(
                Chip("识别文字", "OCR 文字识别", SelectionAction.Ocr),
                Chip("画笔", "画笔标注", SelectionAction.Pen),
                Chip("箭头", "箭头标注", SelectionAction.Arrow),
                Chip("钉图", "钉在屏幕上", SelectionAction.Pin),
                Chip("复制", "复制到剪贴板", SelectionAction.Copy),
                Chip("保存", "保存为 PNG", SelectionAction.Save),
                Chip("取消", "取消截图", SelectionAction.Cancel));
            _toolbar.Visibility = Visibility.Collapsed;
            Children.Add(_toolbar);
        }
    }

    private ToolChip Chip(string text, string tooltip, SelectionAction action)
    {
        var chip = new ToolChip(text, tooltip);
        chip.Click += () => Completed?.Invoke(this, new SelectionResult(action, _selection));
        return chip;
    }

    protected override void OnRender(DrawingContext dc)
    {
        dc.DrawImage(_screenshot, new Rect(0, 0, ActualWidth, ActualHeight));
        dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(125, 0, 0, 0)), null, new Rect(0, 0, ActualWidth, ActualHeight));

        if (_selection.Width > 2 && _selection.Height > 2)
        {
            dc.PushClip(new RectangleGeometry(_selection));
            dc.DrawImage(_screenshot, new Rect(0, 0, ActualWidth, ActualHeight));
            dc.Pop();
            dc.DrawRectangle(null, new Pen(Brushes.DodgerBlue, 2), _selection);
            DrawHandles(dc);
            DrawSizeBadge(dc);
        }

        var text = new FormattedText(
            _instruction,
            System.Globalization.CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            new Typeface("Microsoft YaHei UI"),
            15,
            Brushes.White,
            VisualTreeHelper.GetDpi(this).PixelsPerDip);
        dc.DrawText(text, new Point(24, 20));
    }

    private void OnMouseDown(object sender, MouseButtonEventArgs e)
    {
        CaptureMouse();
        var point = e.GetPosition(this);
        _start = point;
        _dragMode = HitTestMode(point);
        if (_dragMode == DragMode.None)
        {
            _selection = new Rect(point, point);
            _dragMode = DragMode.Create;
        }
        InvalidateVisual();
        UpdateToolbar();
    }

    private void OnMouseMove(object sender, MouseEventArgs e)
    {
        var point = e.GetPosition(this);
        Cursor = CursorFor(HitTestMode(point));
        if (_dragMode == DragMode.None || e.LeftButton != MouseButtonState.Pressed) return;

        switch (_dragMode)
        {
            case DragMode.Create:
                _selection = Normalize(_start, point);
                break;
            case DragMode.Move:
                var delta = point - _start;
                _selection = Clamp(new Rect(_selection.X + delta.X, _selection.Y + delta.Y, _selection.Width, _selection.Height));
                _start = point;
                break;
            case DragMode.ResizeLeft:
                _selection = Normalize(new Point(point.X, _selection.Top), new Point(_selection.Right, _selection.Bottom));
                break;
            case DragMode.ResizeRight:
                _selection = Normalize(new Point(_selection.Left, _selection.Top), new Point(point.X, _selection.Bottom));
                break;
            case DragMode.ResizeTop:
                _selection = Normalize(new Point(_selection.Left, point.Y), new Point(_selection.Right, _selection.Bottom));
                break;
            case DragMode.ResizeBottom:
                _selection = Normalize(new Point(_selection.Left, _selection.Top), new Point(_selection.Right, point.Y));
                break;
        }
        InvalidateVisual();
        UpdateToolbar();
    }

    private void OnMouseUp(object sender, MouseButtonEventArgs e)
    {
        ReleaseMouseCapture();
        _dragMode = DragMode.None;
        _selection = Clamp(_selection);
        InvalidateVisual();
        UpdateToolbar();
    }

    private void UpdateToolbar()
    {
        if (_toolbar == null) return;
        if (_selection.Width <= 2 || _selection.Height <= 2)
        {
            _toolbar.Visibility = Visibility.Collapsed;
            return;
        }

        _toolbar.Visibility = Visibility.Visible;
        _toolbar.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        var size = _toolbar.DesiredSize;
        var left = Math.Clamp(_selection.Left, 8, Math.Max(8, ActualWidth - size.Width - 8));
        var top = _selection.Bottom + 10;
        if (top + size.Height > ActualHeight - 8)
        {
            top = _selection.Top - size.Height - 10;
        }
        if (top < 8)
        {
            top = Math.Max(8, Math.Min(ActualHeight - size.Height - 8, _selection.Bottom + 10));
        }
        SetLeft(_toolbar, left);
        SetTop(_toolbar, top);
    }

    private DragMode HitTestMode(Point point)
    {
        if (_selection.Width < 2 || _selection.Height < 2) return DragMode.None;
        if (Math.Abs(point.X - _selection.Left) <= HandleSize && point.Y >= _selection.Top && point.Y <= _selection.Bottom) return DragMode.ResizeLeft;
        if (Math.Abs(point.X - _selection.Right) <= HandleSize && point.Y >= _selection.Top && point.Y <= _selection.Bottom) return DragMode.ResizeRight;
        if (Math.Abs(point.Y - _selection.Top) <= HandleSize && point.X >= _selection.Left && point.X <= _selection.Right) return DragMode.ResizeTop;
        if (Math.Abs(point.Y - _selection.Bottom) <= HandleSize && point.X >= _selection.Left && point.X <= _selection.Right) return DragMode.ResizeBottom;
        return _selection.Contains(point) ? DragMode.Move : DragMode.None;
    }

    private Cursor CursorFor(DragMode mode) => mode switch
    {
        DragMode.Move => Cursors.SizeAll,
        DragMode.ResizeLeft or DragMode.ResizeRight => Cursors.SizeWE,
        DragMode.ResizeTop or DragMode.ResizeBottom => Cursors.SizeNS,
        _ => Cursors.Cross
    };

    private void DrawHandles(DrawingContext dc)
    {
        foreach (var point in new[]
        {
            new Point(_selection.Left, _selection.Top),
            new Point(_selection.Right, _selection.Top),
            new Point(_selection.Left, _selection.Bottom),
            new Point(_selection.Right, _selection.Bottom)
        })
        {
            dc.DrawRectangle(Brushes.White, new Pen(Brushes.DodgerBlue, 1), new Rect(point.X - 4, point.Y - 4, 8, 8));
        }
    }

    private void DrawSizeBadge(DrawingContext dc)
    {
        var label = $"{(int)Math.Round(_selection.Width)} × {(int)Math.Round(_selection.Height)}";
        var text = new FormattedText(
            label,
            System.Globalization.CultureInfo.CurrentUICulture,
            FlowDirection.LeftToRight,
            new Typeface("Microsoft YaHei UI"),
            12,
            Brushes.White,
            VisualTreeHelper.GetDpi(this).PixelsPerDip);
        var badge = new Rect(_selection.Left, Math.Max(0, _selection.Top - 22), text.Width + 12, 18);
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(220, 30, 30, 30)), null, badge, 4, 4);
        dc.DrawText(text, new Point(badge.Left + 6, badge.Top + 2));
    }

    private Rect Clamp(Rect rect)
    {
        var width = Math.Min(rect.Width, ActualWidth);
        var height = Math.Min(rect.Height, ActualHeight);
        var x = Math.Clamp(rect.X, 0, Math.Max(0, ActualWidth - width));
        var y = Math.Clamp(rect.Y, 0, Math.Max(0, ActualHeight - height));
        return new Rect(x, y, Math.Max(1, width), Math.Max(1, height));
    }

    private static Rect Normalize(Point a, Point b) =>
        new(Math.Min(a.X, b.X), Math.Min(a.Y, b.Y), Math.Abs(a.X - b.X), Math.Abs(a.Y - b.Y));

    private enum DragMode
    {
        None,
        Create,
        Move,
        ResizeLeft,
        ResizeRight,
        ResizeTop,
        ResizeBottom
    }
}
