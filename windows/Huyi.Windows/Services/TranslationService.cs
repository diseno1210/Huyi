using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Huyi.Windows.Models;

namespace Huyi.Windows.Services;

public sealed class TranslationService
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<IReadOnlyList<string>> TranslateAsync(
        IReadOnlyList<string> texts,
        TranslationDirection direction,
        AppSettings settings,
        CancellationToken cancellationToken = default)
    {
        var cleanTexts = texts.Select(text => text.Trim()).ToArray();
        if (cleanTexts.All(string.IsNullOrWhiteSpace))
        {
            return texts.ToArray();
        }

        try
        {
            return await TranslateBatchAsync(cleanTexts, direction, settings, cancellationToken);
        }
        catch
        {
            var results = new List<string>(cleanTexts.Length);
            foreach (var text in cleanTexts)
            {
                results.Add(string.IsNullOrWhiteSpace(text)
                    ? ""
                    : await TranslateSingleAsync(text, direction, settings, cancellationToken));
            }
            return results;
        }
    }

    private async Task<IReadOnlyList<string>> TranslateBatchAsync(
        IReadOnlyList<string> texts,
        TranslationDirection direction,
        AppSettings settings,
        CancellationToken cancellationToken)
    {
        var numbered = string.Join(Environment.NewLine, texts.Select((text, index) => $"{index + 1}. {text}"));
        var prompt = $"""
            Translate each numbered item from {SourceName(direction)} to {TargetName(direction)}.
            Return only the translations, one per line, with the same numbering. Do not add explanations.

            {numbered}
            """;

        var response = await RequestAsync(prompt, settings, cancellationToken);
        return ParseNumbered(response, texts.Count);
    }

    private async Task<string> TranslateSingleAsync(
        string text,
        TranslationDirection direction,
        AppSettings settings,
        CancellationToken cancellationToken)
    {
        var prompt = $"""
            Translate the following text from {SourceName(direction)} to {TargetName(direction)}.
            Return only the translated text. Do not add explanations.

            {text}
            """;

        return await RequestAsync(prompt, settings, cancellationToken);
    }

    private async Task<string> RequestAsync(
        string prompt,
        AppSettings settings,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(settings.LmStudioModel))
        {
            throw new InvalidOperationException("本地 AI 模型名为空。");
        }

        using var client = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(Math.Max(1, settings.LmStudioTimeoutSeconds))
        };

        using var request = new HttpRequestMessage(HttpMethod.Post, ChatCompletionsUrl(settings.LmStudioBaseUrl));
        request.Content = new StringContent(JsonSerializer.Serialize(new ChatCompletionRequest(
            settings.LmStudioModel,
            [
                new ChatMessage("system", "You are a translation engine. Output translated text only."),
                new ChatMessage("user", prompt)
            ],
            0
        ), JsonOptions), Encoding.UTF8, "application/json");

        if (!string.IsNullOrWhiteSpace(settings.LmStudioApiKey))
        {
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", settings.LmStudioApiKey);
        }

        using var response = await client.SendAsync(request, cancellationToken);
        var body = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"本地 AI 返回 HTTP {(int)response.StatusCode}：{body}");
        }

        var decoded = JsonSerializer.Deserialize<ChatCompletionResponse>(body, JsonOptions);
        var content = decoded?.Choices.FirstOrDefault()?.Message.Content.Trim();
        if (string.IsNullOrWhiteSpace(content))
        {
            throw new InvalidOperationException("本地 AI 没有返回译文。");
        }
        return content;
    }

    private static Uri ChatCompletionsUrl(string baseUrl)
    {
        var trimmed = baseUrl.Trim().TrimEnd('/');
        if (string.IsNullOrWhiteSpace(trimmed))
        {
            throw new InvalidOperationException("本地 AI Base URL 为空。");
        }

        return Uri.TryCreate($"{trimmed}/chat/completions", UriKind.Absolute, out var uri)
            ? uri
            : throw new InvalidOperationException("本地 AI Base URL 无效。");
    }

    private static IReadOnlyList<string> ParseNumbered(string response, int expectedCount)
    {
        var results = Enumerable.Repeat("", expectedCount).ToArray();
        var matched = 0;
        var regex = new Regex(@"^\s*(\d+)[\.\)、\)]\s*(.+)$", RegexOptions.Compiled);

        foreach (var line in response.Split('\n').Select(line => line.Trim()).Where(line => line.Length > 0))
        {
            var match = regex.Match(line);
            if (!match.Success || !int.TryParse(match.Groups[1].Value, out var index))
            {
                continue;
            }

            if (index < 1 || index > expectedCount)
            {
                continue;
            }

            results[index - 1] = match.Groups[2].Value.Trim();
            matched++;
        }

        if (matched != expectedCount || results.Any(string.IsNullOrWhiteSpace))
        {
            throw new InvalidOperationException("本地 AI 批量译文格式无法解析。");
        }

        return results;
    }

    private static string SourceName(TranslationDirection direction) =>
        direction == TranslationDirection.EnglishToChinese ? "English" : "Chinese";

    private static string TargetName(TranslationDirection direction) =>
        direction == TranslationDirection.EnglishToChinese ? "Simplified Chinese" : "English";

    private sealed record ChatCompletionRequest(string Model, IReadOnlyList<ChatMessage> Messages, double Temperature);
    private sealed record ChatMessage(string Role, string Content);
    private sealed record ChatCompletionResponse(IReadOnlyList<ChatChoice> Choices);
    private sealed record ChatChoice(ChatMessage Message);
}
