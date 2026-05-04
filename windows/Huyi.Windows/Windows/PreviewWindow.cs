using Microsoft.Win32;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using Huyi.Windows.Models;
using Huyi.Windows.Services;

namespace Huyi.Windows.Windows;

public sealed class PreviewWindow : Window
{
    private readonly BitmapSource _image;
    private readonly Rect _screenRect;
    private readonly OcrService _ocrService;
    private readonly Canvas _surface = new();
    private readonly Image _imageView = new();
    private AnnotationTool _tool = AnnotationTool.None;
    private Brush _color = Brushes.Orange;
    private Polyline? _currentLine;
    private Point _arrowStart;
    private Line? _currentArrow;

    public event EventHandler<BitmapSource>? PinRequested;

    public PreviewWindow(
        BitmapSource image,
        Rect screenRect,
        OcrService ocrService,
        AnnotationTool initialTool = AnnotationTool.None)
    {
        _image = image;
        _screenRect = screenRect;
        _ocrService = ocrService;
        _tool = initialTool;

        Title = "截图预览";
        Width = Math.Min(980, Math.Max(420, image.Width));
        Height = Math.Min(760, Math.Max(320, image.Height + 52));
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Topmost = true;

        var root = new DockPanel();
        root.Children.Add(MakeToolbar());

        var scroll = new ScrollViewer
        {
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Content = _surface
        };
        _surface.Width = image.Width;
        _surface.Height = image.Height;
        _surface.Background = Brushes.Transparent;
        _imageView.Source = image;
        _imageView.Width = image.Width;
        _imageView.Height = image.Height;
        _surface.Children.Add(_imageView);
        _surface.MouseLeftButtonDown += OnMouseDown;
        _surface.MouseMove += OnMouseMove;
        _surface.MouseLeftButtonUp += OnMouseUp;
        _surface.MouseDown += (_, e) =>
        {
            if (e.ClickCount == 2)
            {
                CopyAndClose();
            }
        };

        root.Children.Add(scroll);
        Content = root;
    }

    private UIElement MakeToolbar()
    {
        var toolbar = new StackPanel
        {
            Height = 44,
            Orientation = Orientation.Horizontal,
            Background = new SolidColorBrush(Color.FromRgb(36, 36, 36))
        };
        DockPanel.SetDock(toolbar, Dock.Top);

        AddButton(toolbar, "文", "文字识别", async () => await RunOcrAsync());
        AddButton(toolbar, "✎", "画笔", () => _tool = AnnotationTool.Pen);
        AddButton(toolbar, "↗", "箭头", () => _tool = AnnotationTool.Arrow);
        AddButton(toolbar, "橙", "橙色", () => _color = Brushes.Orange);
        AddButton(toolbar, "蓝", "蓝色", () => _color = Brushes.DodgerBlue);
        AddButton(toolbar, "绿", "绿色", () => _color = Brushes.LimeGreen);
        AddButton(toolbar, "⌖", "钉图", () => PinRequested?.Invoke(this, AnnotatedImage()));
        AddButton(toolbar, "⧉", "复制", CopyAndClose);
        AddButton(toolbar, "⇩", "保存", Save);
        AddButton(toolbar, "×", "关闭", Close);
        return toolbar;
    }

    private static void AddButton(Panel parent, string label, string tooltip, Action action)
    {
        var button = new Button
        {
            Content = label,
            ToolTip = tooltip,
            Width = 34,
            Height = 30,
            Margin = new Thickness(6, 7, 0, 7)
        };
        button.Click += (_, _) => action();
        parent.Children.Add(button);
    }

    private async Task RunOcrAsync()
    {
        try
        {
            var text = await _ocrService.RecognizeTextAsync(_image, OcrMode.ChineseAndEnglish);
            new TextPanelWindow(string.IsNullOrWhiteSpace(text) ? "未识别到文字。" : text, _screenRect).Show();
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "文字识别失败", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void OnMouseDown(object sender, MouseButtonEventArgs e)
    {
        var point = e.GetPosition(_surface);
        if (_tool == AnnotationTool.Pen)
        {
            _currentLine = new Polyline
            {
                Stroke = _color,
                StrokeThickness = 4,
                StrokeStartLineCap = PenLineCap.Round,
                StrokeEndLineCap = PenLineCap.Round
            };
            _currentLine.Points.Add(point);
            _surface.Children.Add(_currentLine);
            _surface.CaptureMouse();
        }
        else if (_tool == AnnotationTool.Arrow)
        {
            _arrowStart = point;
            _currentArrow = new Line
            {
                X1 = point.X,
                Y1 = point.Y,
                X2 = point.X,
                Y2 = point.Y,
                Stroke = _color,
                StrokeThickness = 4,
                StrokeStartLineCap = PenLineCap.Round,
                StrokeEndLineCap = PenLineCap.Triangle
            };
            _surface.Children.Add(_currentArrow);
            _surface.CaptureMouse();
        }
    }

    private void OnMouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed) return;
        var point = e.GetPosition(_surface);
        if (_currentLine != null)
        {
            _currentLine.Points.Add(point);
        }
        else if (_currentArrow != null)
        {
            _currentArrow.X2 = point.X;
            _currentArrow.Y2 = point.Y;
        }
    }

    private void OnMouseUp(object sender, MouseButtonEventArgs e)
    {
        if (_currentArrow != null)
        {
            AddArrowHead(_arrowStart, new Point(_currentArrow.X2, _currentArrow.Y2), _color);
        }
        _currentLine = null;
        _currentArrow = null;
        _surface.ReleaseMouseCapture();
    }

    private void AddArrowHead(Point start, Point end, Brush brush)
    {
        var vector = start - end;
        if (vector.Length < 1) return;
        vector.Normalize();
        var left = new Vector(vector.X * 14 - vector.Y * 7, vector.Y * 14 + vector.X * 7);
        var right = new Vector(vector.X * 14 + vector.Y * 7, vector.Y * 14 - vector.X * 7);
        var head = new Polygon
        {
            Fill = brush,
            Points = new PointCollection { end, end + left, end + right }
        };
        _surface.Children.Add(head);
    }

    private BitmapSource AnnotatedImage()
    {
        _surface.UpdateLayout();
        return ScreenshotService.RenderVisual(_surface);
    }

    private void CopyAndClose()
    {
        ScreenshotService.CopyImage(AnnotatedImage());
        Close();
    }

    private void Save()
    {
        var dialog = new SaveFileDialog
        {
            Title = "保存截图",
            FileName = "截图.png",
            Filter = "PNG Image|*.png"
        };
        if (dialog.ShowDialog(this) == true)
        {
            ScreenshotService.SavePng(AnnotatedImage(), dialog.FileName);
        }
    }
}

public enum AnnotationTool
{
    None,
    Pen,
    Arrow
}
