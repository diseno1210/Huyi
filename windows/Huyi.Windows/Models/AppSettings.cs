namespace Huyi.Windows.Models;

public sealed class AppSettings
{
    public string TranslateShortcut { get; set; } = "F4";
    public string ScreenshotShortcut { get; set; } = "F1";
    public string InputTranslationShortcut { get; set; } = "F5";
    public string LmStudioBaseUrl { get; set; } = "http://127.0.0.1:1234/v1";
    public string LmStudioModel { get; set; } = "local-model";
    public string LmStudioApiKey { get; set; } = "";
    public int LmStudioTimeoutSeconds { get; set; } = 20;
    public bool LaunchAtLogin { get; set; } = false;
}
