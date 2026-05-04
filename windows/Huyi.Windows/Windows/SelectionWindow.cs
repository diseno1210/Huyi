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
    private readonly bool _showsToolbar;
    private readonly SelectionCanvas _canvas;

    public SelectionWindow(BitmapSource screenshot, Rect virtualBounds, string instruction, bool showsToolbar)
    {
        _virtualBounds = virtualBounds;
        _showsToolbar = showsToolbar;
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
    private readonly bool _showsToolbar;
    private Rect _selection;
    private Point _start;
    private DragMode _dragMode = DragMode.None;

    public event EventHandler<SelectionResult>? Completed;

    public SelectionCanvas(BitmapSource screenshot, string instruction, bool showsToolbar)
    {
        _screenshot = screenshot;
        _instruction = instruction;
        _showsToolbar = showsToolbar;
        Focusable = true;
        Background = Brushes.Transparent;
        ClipToBounds = true;
        MouseLeftButtonDown += OnMouseDown;
        MouseMove += OnMouseMove;
        MouseLeftButtonUp += OnMouseUp;
        MouseRightButtonDown += (_, _) => Completed?.Invoke(this, new SelectionResult(SelectionAction.Cancel, Rect.Empty));
        MouseDown += (_, e) =>
        {
            if (e.ClickCount == 2 && _selection.Width > 2 && _selection.Height > 2)
            {
                Completed?.Invoke(this, new SelectionResult(SelectionAction.Copy, _selection));
            }
        };
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
            if (_showsToolbar)
            {
                DrawToolbar(dc);
            }
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
        if (_showsToolbar && ToolbarActionAt(point) is { } action)
        {
            Completed?.Invoke(this, new SelectionResult(action, _selection));
            return;
        }

        _start = point;
        _dragMode = HitTestMode(point);
        if (_dragMode == DragMode.None)
        {
            _selection = new Rect(point, point);
            _dragMode = DragMode.Create;
        }
        InvalidateVisual();
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
    }

    private void OnMouseUp(object sender, MouseButtonEventArgs e)
    {
        ReleaseMouseCapture();
        _dragMode = DragMode.None;
        _selection = Clamp(_selection);
        InvalidateVisual();
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

    private void DrawToolbar(DrawingContext dc)
    {
        var buttons = ToolbarButtons();
        var toolbarWidth = buttons.Count * 42 + 10;
        var x = Math.Clamp(_selection.Left, 12, Math.Max(12, ActualWidth - toolbarWidth - 12));
        var y = Math.Min(ActualHeight - 48, _selection.Bottom + 10);
        if (y + 42 > ActualHeight) y = Math.Max(12, _selection.Top - 52);
        var background = new Rect(x, y, toolbarWidth, 42);
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(235, 30, 30, 30)), null, background, 6, 6);

        for (var i = 0; i < buttons.Count; i++)
        {
            var rect = new Rect(x + 5 + i * 42, y + 5, 32, 32);
            dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(255, 245, 245, 245)), null, rect, 4, 4);
            var text = new FormattedText(
                buttons[i].Label,
                System.Globalization.CultureInfo.CurrentUICulture,
                FlowDirection.LeftToRight,
                new Typeface("Segoe UI Symbol"),
                15,
                Brushes.Black,
                VisualTreeHelper.GetDpi(this).PixelsPerDip);
            dc.DrawText(text, new Point(rect.Left + (rect.Width - text.Width) / 2, rect.Top + 6));
        }
    }

    private SelectionAction? ToolbarActionAt(Point point)
    {
        if (_selection.Width <= 2 || _selection.Height <= 2) return null;
        var buttons = ToolbarButtons();
        var toolbarWidth = buttons.Count * 42 + 10;
        var x = Math.Clamp(_selection.Left, 12, Math.Max(12, ActualWidth - toolbarWidth - 12));
        var y = Math.Min(ActualHeight - 48, _selection.Bottom + 10);
        if (y + 42 > ActualHeight) y = Math.Max(12, _selection.Top - 52);

        for (var i = 0; i < buttons.Count; i++)
        {
            var rect = new Rect(x + 5 + i * 42, y + 5, 32, 32);
            if (rect.Contains(point)) return buttons[i].Action;
        }
        return null;
    }

    private static IReadOnlyList<(string Label, SelectionAction Action)> ToolbarButtons() =>
    [
        ("文", SelectionAction.Ocr),
        ("✎", SelectionAction.Pen),
        ("↗", SelectionAction.Arrow),
        ("⌖", SelectionAction.Pin),
        ("⧉", SelectionAction.Copy),
        ("⇩", SelectionAction.Save),
        ("×", SelectionAction.Cancel)
    ];

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
