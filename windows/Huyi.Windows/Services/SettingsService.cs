using System;
using System.IO;
using System.Text.Json;
using Huyi.Windows.Models;

namespace Huyi.Windows.Services;

public sealed class SettingsService
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public string SettingsPath { get; }
    public AppSettings Current { get; private set; }

    public SettingsService()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var directory = Path.Combine(appData, "Huyi");
        Directory.CreateDirectory(directory);
        SettingsPath = Path.Combine(directory, "settings.json");
        Current = Load();
    }

    public AppSettings Reload()
    {
        Current = Load();
        return Current;
    }

    public void Save(AppSettings settings)
    {
        settings.LmStudioBaseUrl = settings.LmStudioBaseUrl.Trim();
        settings.LmStudioModel = settings.LmStudioModel.Trim();
        settings.LmStudioApiKey = settings.LmStudioApiKey.Trim();
        settings.LmStudioTimeoutSeconds = Math.Max(1, settings.LmStudioTimeoutSeconds);
        var json = JsonSerializer.Serialize(settings, JsonOptions);
        File.WriteAllText(SettingsPath, json);
        Current = settings;
    }

    private AppSettings Load()
    {
        if (!File.Exists(SettingsPath))
        {
            var defaults = new AppSettings();
            Save(defaults);
            return defaults;
        }

        try
        {
            var json = File.ReadAllText(SettingsPath);
            return JsonSerializer.Deserialize<AppSettings>(json, JsonOptions) ?? new AppSettings();
        }
        catch
        {
            return new AppSettings();
        }
    }
}
