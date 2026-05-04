using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Forms = System.Windows.Forms;

namespace Huyi.Windows.Services;

public sealed class ScreenshotService
{
    public Rect VirtualScreenBounds()
    {
        var bounds = Forms.SystemInformation.VirtualScreen;
        return new Rect(bounds.Left, bounds.Top, bounds.Width, bounds.Height);
    }

    public BitmapSource CaptureVirtualScreen()
    {
        var bounds = Forms.SystemInformation.VirtualScreen;
        using var bitmap = new Bitmap(bounds.Width, bounds.Height);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.CopyFromScreen(bounds.Left, bounds.Top, 0, 0, bounds.Size);
        }
        return BitmapToSource(bitmap);
    }

    public CapturedImage Capture(Rect screenRect)
    {
        var x = (int)Math.Round(screenRect.X);
        var y = (int)Math.Round(screenRect.Y);
        var width = Math.Max(1, (int)Math.Round(screenRect.Width));
        var height = Math.Max(1, (int)Math.Round(screenRect.Height));
        using var bitmap = new Bitmap(width, height);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.CopyFromScreen(x, y, 0, 0, new System.Drawing.Size(width, height));
        }
        return new CapturedImage(BitmapToSource(bitmap), new Rect(x, y, width, height));
    }

    public BitmapSource Crop(BitmapSource source, Rect rect, Rect virtualBounds)
    {
        var x = Math.Max(0, (int)Math.Round(rect.X - virtualBounds.X));
        var y = Math.Max(0, (int)Math.Round(rect.Y - virtualBounds.Y));
        var width = Math.Max(1, Math.Min((int)Math.Round(rect.Width), source.PixelWidth - x));
        var height = Math.Max(1, Math.Min((int)Math.Round(rect.Height), source.PixelHeight - y));
        var cropped = new CroppedBitmap(source, new Int32Rect(x, y, width, height));
        cropped.Freeze();
        return cropped;
    }

    public static BitmapSource RenderVisual(FrameworkElement visual)
    {
        var width = Math.Max(1, (int)Math.Ceiling(visual.ActualWidth));
        var height = Math.Max(1, (int)Math.Ceiling(visual.ActualHeight));
        var target = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        target.Render(visual);
        target.Freeze();
        return target;
    }

    public static void CopyImage(BitmapSource image)
    {
        Clipboard.SetImage(image);
    }

    public static void SavePng(BitmapSource image, string fileName)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(image));
        using var stream = File.Create(fileName);
        encoder.Save(stream);
    }

    private static BitmapSource BitmapToSource(Bitmap bitmap)
    {
        var handle = bitmap.GetHbitmap();
        try
        {
            var source = Imaging.CreateBitmapSourceFromHBitmap(
                handle,
                IntPtr.Zero,
                Int32Rect.Empty,
                BitmapSizeOptions.FromEmptyOptions());
            source.Freeze();
            return source;
        }
        finally
        {
            DeleteObject(handle);
        }
    }

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr hObject);
}
