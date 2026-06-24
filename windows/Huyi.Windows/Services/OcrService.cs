using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Runtime.InteropServices.WindowsRuntime;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Huyi.Windows.Models;
using Windows.Globalization;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.System.UserProfile;

namespace Huyi.Windows.Services;

public sealed class OcrService
{
    public async Task<IReadOnlyList<RecognizedLine>> RecognizeLinesAsync(
        BitmapSource image,
        OcrMode mode,
        CancellationToken cancellationToken = default)
    {
        var engines = CreateEngines(mode);
        if (engines.Count == 0)
        {
            throw new InvalidOperationException("Windows OCR 不可用。请在 Windows 设置中安装英文/中文 OCR 语言能力。");
        }

        var best = new List<RecognizedLine>();
        foreach (var engine in engines)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var result = await engine.RecognizeAsync(ToSoftwareBitmap(image));
            var lines = result.Lines
                .Select(line => new RecognizedLine(line.Text, LineBounds(line)))
                .Where(line => !string.IsNullOrWhiteSpace(line.Text))
                .ToList();

            if (lines.Sum(line => line.Text.Length) > best.Sum(line => line.Text.Length))
            {
                best = lines;
            }
        }

        return best;
    }

    public async Task<string> RecognizeTextAsync(
        BitmapSource image,
        OcrMode mode,
        CancellationToken cancellationToken = default)
    {
        var lines = await RecognizeLinesAsync(image, mode, cancellationToken);
        return string.Join(Environment.NewLine, lines.Select(line => line.Text));
    }

    private static Rect LineBounds(OcrLine line)
    {
        var bounds = Rect.Empty;
        foreach (var word in line.Words)
        {
            var rect = word.BoundingRect;
            bounds.Union(new Rect(rect.X, rect.Y, rect.Width, rect.Height));
        }
        return bounds;
    }

    private static IReadOnlyList<OcrEngine> CreateEngines(OcrMode mode)
    {
        var languageTags = mode == OcrMode.English
            ? new[] { "en-US", "en" }
            : new[] { "zh-Hans-CN", "zh-Hant-TW", "en-US", "en" };

        var engines = new List<OcrEngine>();
        foreach (var tag in languageTags)
        {
            try
            {
                var language = new Language(tag);
                if (!OcrEngine.IsLanguageSupported(language))
                {
                    continue;
                }

                var engine = OcrEngine.TryCreateFromLanguage(language);
                if (engine != null)
                {
                    engines.Add(engine);
                }
            }
            catch
            {
                // Some Windows language tags may not be installed on the current system.
            }
        }

        if (engines.Count == 0)
        {
            var userProfile = GlobalizationPreferences.Languages.FirstOrDefault();
            if (!string.IsNullOrWhiteSpace(userProfile))
            {
                try
                {
                    var language = new Language(userProfile);
                    if (OcrEngine.IsLanguageSupported(language))
                    {
                        var engine = OcrEngine.TryCreateFromLanguage(language);
                        if (engine != null)
                        {
                            engines.Add(engine);
                        }
                    }
                }
                catch
                {
                    // Fall through to caller error.
                }
            }
        }

        return engines;
    }

    private static SoftwareBitmap ToSoftwareBitmap(BitmapSource source)
    {
        var formatted = source.Format == PixelFormats.Bgra32
            ? source
            : new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);

        var stride = formatted.PixelWidth * 4;
        var pixels = new byte[stride * formatted.PixelHeight];
        formatted.CopyPixels(pixels, stride, 0);
        return SoftwareBitmap.CreateCopyFromBuffer(
            pixels.AsBuffer(),
            BitmapPixelFormat.Bgra8,
            formatted.PixelWidth,
            formatted.PixelHeight,
            BitmapAlphaMode.Premultiplied);
    }
}
