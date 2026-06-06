using System.Text;
using mywebapp.Data;

namespace mywebapp.Endpoints;

public static class SystemEndpoints
{
    public static void MapSystemEndpoints(this WebApplication app)
    {
        app.MapGet("/health/alive", () => Results.Text("OK", "text/plain"));

        app.MapGet("/health/ready", async (AppDbContext dbContext) =>
        {
            try
            {
                bool canConnect = await dbContext.Database.CanConnectAsync();
                if (canConnect)
                {
                    return Results.Text("OK", "text/plain");
                }
                return Results.Text("Database connection failed", "text/plain", statusCode: StatusCodes.Status500InternalServerError);
            }
            catch (Exception ex)
            {
                return Results.Text(ex.Message, "text/plain", statusCode: StatusCodes.Status500InternalServerError);
            }
        });

        app.MapGet("/", (HttpRequest request) =>
        {
            if (!HttpNegotiation.AllowsHtml(request))
            {
                return Results.StatusCode(StatusCodes.Status406NotAcceptable);
            }

            string html = @"
                <!doctype html>
                <html>
                <body>
                    <h1>mywebapp</h1>
                    <table border=""1"">
                        <thead>
                            <tr><th>method</th><th>path</th><th>description</th></tr>
                        </thead>
                        <tbody>
                            <tr><td>GET</td><td>/notes</td><td>notes list</td></tr>
                            <tr><td>POST</td><td>/notes</td><td>create note</td></tr>
                            <tr><td>GET</td><td>/notes/{id}</td><td>note details</td></tr>
                        </tbody>
                    </table>
                </body>
                </html>";

            return Results.Content(html, "text/html", Encoding.UTF8);
        });
    }
}
