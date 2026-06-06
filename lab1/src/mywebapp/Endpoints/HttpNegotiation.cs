namespace mywebapp.Endpoints;

internal static class HttpNegotiation
{
    public static bool PrefersHtml(HttpRequest request)
    {
        var accept = request.Headers.Accept.ToString();
        return accept.Contains("text/html", StringComparison.OrdinalIgnoreCase);
    }

    public static bool AllowsHtml(HttpRequest request)
    {
        var accept = request.Headers.Accept.ToString();
        return string.IsNullOrWhiteSpace(accept)
               || accept.Contains("*/*", StringComparison.OrdinalIgnoreCase)
               || accept.Contains("text/html", StringComparison.OrdinalIgnoreCase);
    }
}
