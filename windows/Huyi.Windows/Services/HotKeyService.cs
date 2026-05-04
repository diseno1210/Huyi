using System.Runtime.InteropServices;
using System.Windows.Interop;

namespace Huyi.Windows.Services;

public sealed class HotKeyService : IDisposable
{
    private const int WmHotKey = 0x0312;
    private readonly HwndSource _source;
    private readonly Dictionary<int, Action> _handlers = new();

    public HotKeyService()
    {
        var parameters = new HwndSourceParameters("HuyiHotKeySink")
        {
            Width = 0,
            Height = 0,
            WindowStyle = 0x800000
        };
        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);
    }

    public void Register(int id, string shortcut, Action handler)
    {
        Unregister(id);
        var parsed = ShortcutParser.Parse(shortcut);
        if (!RegisterHotKey(_source.Handle, id, parsed.Modifiers, parsed.Key))
        {
            throw new InvalidOperationException($"快捷键注册失败：{shortcut}");
        }
        _handlers[id] = handler;
    }

    public void Unregister(int id)
    {
        if (_handlers.Remove(id))
        {
            UnregisterHotKey(_source.Handle, id);
        }
    }

    public void Dispose()
    {
        foreach (var id in _handlers.Keys.ToArray())
        {
            Unregister(id);
        }
        _source.RemoveHook(WndProc);
        _source.Dispose();
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmHotKey && _handlers.TryGetValue(wParam.ToInt32(), out var handler))
        {
            handler();
            handled = true;
        }
        return IntPtr.Zero;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}

public static class ShortcutParser
{
    private const uint ModAlt = 0x0001;
    private const uint ModControl = 0x0002;
    private const uint ModShift = 0x0004;
    private const uint ModWin = 0x0008;

    public static readonly string[] Presets =
    [
        "Ctrl+Shift+A", "Ctrl+Shift+T", "Ctrl+Shift+S",
        "Alt+Shift+A", "Alt+Shift+S", "Win+Shift+S",
        "F1", "F2", "F3", "F4", "F5"
    ];

    public static (uint Modifiers, uint Key) Parse(string shortcut)
    {
        var modifiers = 0u;
        var keyPart = "";
        foreach (var part in shortcut.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
        {
            switch (part.ToUpperInvariant())
            {
                case "CTRL":
                case "CONTROL":
                    modifiers |= ModControl;
                    break;
                case "ALT":
                case "OPTION":
                    modifiers |= ModAlt;
                    break;
                case "SHIFT":
                    modifiers |= ModShift;
                    break;
                case "WIN":
                case "WINDOWS":
                case "COMMAND":
                    modifiers |= ModWin;
                    break;
                default:
                    keyPart = part.ToUpperInvariant();
                    break;
            }
        }

        if (keyPart.StartsWith('F') && int.TryParse(keyPart[1..], out var functionKey) && functionKey is >= 1 and <= 24)
        {
            return (modifiers, (uint)(0x70 + functionKey - 1));
        }

        if (keyPart.Length == 1 && keyPart[0] is >= 'A' and <= 'Z')
        {
            return (modifiers, keyPart[0]);
        }

        throw new InvalidOperationException($"不支持的快捷键：{shortcut}");
    }
}
