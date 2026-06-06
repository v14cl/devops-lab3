using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using mywebapp.Data;
using mywebapp.Models;
using System.Net;
using System.Text;

namespace mywebapp.Endpoints;

public static class NotesEndpoints
{
    public static void MapNotesEndpoints(this WebApplication app)
    {
        app.MapGet("/notes", async (HttpRequest request, AppDbContext dbContext) =>
        {
            var notes = await dbContext.Notes
                .OrderByDescending(note => note.CreatedAt)
                .Select(note => new { id = note.Id, title = note.Title })
                .ToListAsync();

            if (HttpNegotiation.PrefersHtml(request))
            {
                var sb = new StringBuilder("<!doctype html><html><body><table border=\"1\"><thead><tr><th>id</th><th>title</th></tr></thead><tbody>");
                foreach (var note in notes)
                {
                    sb.Append("<tr>");
                    sb.Append($"<td>{note.id}</td>");
                    sb.Append($"<td>{WebUtility.HtmlEncode(note.title)}</td>");
                    sb.Append("</tr>");
                }
                sb.Append("</tbody></table></body></html>");
                return Results.Content(sb.ToString(), "text/html");
            }

            return Results.Ok(notes);
        });

        app.MapGet("/notes/{id:long}", async (HttpRequest request, AppDbContext dbContext, long id) =>
        {
            var note = await dbContext.Notes.AsNoTracking().SingleOrDefaultAsync(item => item.Id == id);
            if (note == null) return Results.NotFound();

            if (HttpNegotiation.PrefersHtml(request))
            {
                var html = $@"
                    <!doctype html>
                    <html><body>
                    <table border=""1"">
                        <tr><th>id</th><td>{note.Id}</td></tr>
                        <tr><th>title</th><td>{WebUtility.HtmlEncode(note.Title)}</td></tr>
                        <tr><th>created_at</th><td>{note.CreatedAt:O}</td></tr>
                        <tr><th>content</th><td>{WebUtility.HtmlEncode(note.Content)}</td></tr>
                    </table>
                    </body></html>";
                return Results.Content(html, "text/html");
            }

            return Results.Ok(note);
        });

        app.MapPost("/notes", async (HttpRequest request, AppDbContext dbContext) =>
        {
            var dto = await CreateNoteDto.FromRequestAsync(request);
            var note = new Note
            {
                Title = string.IsNullOrWhiteSpace(dto.Title) ? "Untitled note" : dto.Title.Trim(),
                Content = dto.Content?.Trim() ?? string.Empty,
                CreatedAt = DateTime.UtcNow
            };

            dbContext.Notes.Add(note);
            await dbContext.SaveChangesAsync();

            if (HttpNegotiation.PrefersHtml(request))
            {
                var html = $@"
                    <!doctype html>
                    <html><body>
                    <table border=""1"">
                        <tr><th>id</th><td>{note.Id}</td></tr>
                        <tr><th>title</th><td>{WebUtility.HtmlEncode(note.Title)}</td></tr>
                        <tr><th>created_at</th><td>{note.CreatedAt:O}</td></tr>
                        <tr><th>content</th><td>{WebUtility.HtmlEncode(note.Content)}</td></tr>
                    </table>
                    </body></html>";
                return Results.Content(html, "text/html", statusCode: StatusCodes.Status201Created);
            }

            return Results.Created($"/notes/{note.Id}", note);
        });
    }
}

public class CreateNoteDto
{
    public string? Title { get; set; }
    public string? Content { get; set; }

    public static async Task<CreateNoteDto> FromRequestAsync(HttpRequest request)
    {
        if (request.HasFormContentType)
        {
            var form = await request.ReadFormAsync();
            return new CreateNoteDto
            {
                Title = form["title"].ToString(),
                Content = form["content"].ToString()
            };
        }

        if ((request.ContentLength ?? 0) == 0)
        {
            return new CreateNoteDto();
        }

        if (request.ContentType?.Contains("application/json", StringComparison.OrdinalIgnoreCase) == true)
        {
            return await request.ReadFromJsonAsync<CreateNoteDto>() ?? new CreateNoteDto();
        }

        return new CreateNoteDto
        {
            Title = request.Query["title"].ToString(),
            Content = request.Query["content"].ToString()
        };
    }
}
