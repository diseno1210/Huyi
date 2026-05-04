using System.Windows;
using System.Windows.Media.Imaging;

namespace Huyi.Windows.Models;

public enum TranslationDirection
{
    EnglishToChinese,
    ChineseToEnglish
}

public enum OcrMode
{
    English,
    ChineseAndEnglish
}

public enum SelectionAction
{
    Preview,
    Ocr,
    Pen,
    Arrow,
    Pin,
    Copy,
    Save,
    Cancel
}

public sealed record RecognizedLine(string Text, Rect Bounds);

public sealed record SelectionResult(SelectionAction Action, Rect ScreenRect);

public sealed record CapturedImage(BitmapSource Image, Rect ScreenRect);

public sealed record TranslationOverlayItem(string SourceText, string TargetText, Rect Bounds);
