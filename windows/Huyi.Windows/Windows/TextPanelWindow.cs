using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Huyi.Windows.Services;

namespace Huyi.Windows.Windows;

public sealed class TextPanelWindow : Window
{
    private readonly TextBox _textBox;

    public TextPanelWindow(string text, Rect near)
    {
        Title = "文字识别";
        Width = 520;
        Height = 320;
        Topmost = true;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Left = near.Right + 12;
        Top = near.Top;

        var root = new DockPanel { Margin = new Thickness(12) };
        _textBox = new TextBox
        {
            Text = text,
            AcceptsReturn = true,
            TextWrapping = TextWrapping.Wrap,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            FontSize = 14
        };

        var button = new Button
        {
            Content = "复制文字",
            Width = 104,
            Height = 30,
            Margin = new Thickness(0, 8, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Left
        };
        button.Click += (_, _) => Clipboard.SetText(_textBox.Text);

        DockPanel.SetDock(button, Dock.Bottom);
        root.Children.Add(button);
        root.Children.Add(_textBox);
        Content = root;
    }
}
