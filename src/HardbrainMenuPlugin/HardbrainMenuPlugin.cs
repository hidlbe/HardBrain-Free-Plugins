using System.Reflection;
using AssettoServer.Server;
using AssettoServer.Server.Configuration;
using Microsoft.Extensions.Hosting;
using Serilog;

namespace HardbrainMenuPlugin;

public class HardbrainMenuPlugin : IHostedService
{
    private readonly HardbrainMenuConfiguration _config;
    private readonly CSPServerScriptProvider _scriptProvider;
    private readonly ACServerConfiguration _serverConfiguration;

    public HardbrainMenuPlugin(
        HardbrainMenuConfiguration config,
        CSPServerScriptProvider scriptProvider,
        ACServerConfiguration serverConfiguration)
    {
        _config = config;
        _scriptProvider = scriptProvider;
        _serverConfiguration = serverConfiguration;
    }

    public Task StartAsync(CancellationToken cancellationToken)
    {
        if (!_config.Enabled)
        {
            Log.Information("[HardbrainMenu] Disabled in configuration");
            return Task.CompletedTask;
        }

        if (!_serverConfiguration.Extra.EnableClientMessages)
        {
            throw new ConfigurationException(
                "HardbrainMenuPlugin requires EnableClientMessages: true in extra_cfg.yml");
        }

        var luaPath = Path.Combine(
            Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)!,
            "lua",
            "hardbrain_menu.lua");

        if (!File.Exists(luaPath))
        {
            throw new FileNotFoundException("Hardbrain menu Lua script was not found.", luaPath);
        }

        var luaScript = File.ReadAllText(luaPath);
        _scriptProvider.AddScript(
            new MemoryStream(System.Text.Encoding.UTF8.GetBytes(luaScript)),
            "hardbrain_menu.lua");

        Log.Information("[HardbrainMenu] Enabled — server-pushed menu for all players");
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}
