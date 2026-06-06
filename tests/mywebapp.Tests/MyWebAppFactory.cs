using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace mywebapp.Tests;

public sealed class MyWebAppFactory : WebApplicationFactory<Program>
{
    private readonly string _databaseName = $"mywebapp-tests-{Guid.NewGuid()}";
    private readonly Dictionary<string, string?> _previousEnvironment = [];

    public MyWebAppFactory()
    {
        SetEnvironment("Application__Host", "127.0.0.1");
        SetEnvironment("Application__Port", "0");
        SetEnvironment("Database__Provider", "InMemory");
        SetEnvironment("Database__Name", _databaseName);
        SetEnvironment("Database__AutoMigrate", "false");
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.ConfigureAppConfiguration((_, configuration) =>
        {
            configuration.AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Application:Host"] = "127.0.0.1",
                ["Application:Port"] = "0",
                ["Database:Provider"] = "InMemory",
                ["Database:Name"] = _databaseName,
                ["Database:AutoMigrate"] = "false"
            });
        });
    }

    protected override void Dispose(bool disposing)
    {
        base.Dispose(disposing);

        foreach (var (key, value) in _previousEnvironment)
        {
            Environment.SetEnvironmentVariable(key, value);
        }
    }

    private void SetEnvironment(string key, string value)
    {
        _previousEnvironment[key] = Environment.GetEnvironmentVariable(key);
        Environment.SetEnvironmentVariable(key, value);
    }
}
