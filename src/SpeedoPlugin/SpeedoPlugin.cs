using System.Reflection;
using AssettoServer.Server;
using AssettoServer.Server.Configuration;
using Microsoft.Extensions.Hosting;
using Serilog;

namespace SpeedoPlugin;

public class SpeedoPlugin : BackgroundService
{
    private readonly SpeedoConfiguration _config;
    private readonly CSPServerScriptProvider _scriptProvider;
    private readonly ACServerConfiguration _serverConfiguration;

    public SpeedoPlugin(
        SpeedoConfiguration config,
        CSPServerScriptProvider scriptProvider,
        ACServerConfiguration serverConfiguration)
    {
        _config = config;
        _scriptProvider = scriptProvider;
        _serverConfiguration = serverConfiguration;
    }

    public override Task StartAsync(CancellationToken cancellationToken)
    {
        if (!_config.Enabled)
        {
            Log.Information("[Speedo] Disabled in configuration");
            return Task.CompletedTask;
        }

        if (!_serverConfiguration.Extra.EnableClientMessages)
        {
            throw new ConfigurationException(
                "SpeedoPlugin requires EnableClientMessages: true in extra_cfg.yml");
        }

        var luaPath = Path.Combine(
            Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)!,
            "lua",
            "speedo.lua");

        if (!File.Exists(luaPath))
        {
            throw new FileNotFoundException(
                "Speedo Lua script was not found.",
                luaPath);
        }

        var luaScript = File.ReadAllText(luaPath)
            .Replace("{{UNITS_MPH}}", string.Equals(_config.Units, "mph", StringComparison.OrdinalIgnoreCase) ? "true" : "false");

        _scriptProvider.AddScript(
            new MemoryStream(System.Text.Encoding.UTF8.GetBytes(luaScript)),
            "speedo.lua");

        Log.Information(
            "[Speedo] Enabled — local HUD only, units={Units} (drag/scroll to move/resize)",
            _config.Units);

        return Task.CompletedTask;
    }

    protected override Task ExecuteAsync(CancellationToken stoppingToken) => Task.CompletedTask;
}
