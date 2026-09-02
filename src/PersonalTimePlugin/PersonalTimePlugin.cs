using AssettoServer.Network.Tcp;
using AssettoServer.Server;
using AssettoServer.Server.Configuration;
using AssettoServer.Server.Weather;
using AssettoServer.Shared.Network.Packets.Outgoing;
using AssettoServer.Shared.Weather;
using Microsoft.Extensions.Hosting;
using PersonalTimePlugin.Packets;
using Serilog;

namespace PersonalTimePlugin;

public class PersonalTimePlugin : BackgroundService
{
    private readonly PersonalTimeConfiguration _config;
    private readonly PersonalTimeService _personalTime;
    private readonly WeatherManager _weatherManager;
    private readonly EntryCarManager _entryCarManager;
    private readonly ACServerConfiguration _serverConfiguration;

    public PersonalTimePlugin(
        PersonalTimeConfiguration config,
        PersonalTimeService personalTime,
        WeatherManager weatherManager,
        EntryCarManager entryCarManager,
        CSPClientMessageTypeManager cspClientMessageTypeManager,
        ACServerConfiguration serverConfiguration)
    {
        _config = config;
        _personalTime = personalTime;
        _weatherManager = weatherManager;
        _entryCarManager = entryCarManager;
        _serverConfiguration = serverConfiguration;

        cspClientMessageTypeManager.RegisterOnlineEvent<SetTimePacket>(OnSetTime);
        cspClientMessageTypeManager.RegisterOnlineEvent<SetWeatherPacket>(OnSetWeather);
        _entryCarManager.ClientDisconnected += OnClientDisconnected;
    }

    public override Task StartAsync(CancellationToken cancellationToken)
    {
        if (!_config.Enabled)
        {
            Log.Information("[PersonalTime] Disabled in configuration");
            return Task.CompletedTask;
        }

        if (!_serverConfiguration.Extra.EnableClientMessages)
        {
            throw new ConfigurationException(
                "PersonalTimePlugin requires EnableClientMessages: true in extra_cfg.yml");
        }

        if (!_serverConfiguration.Extra.EnableWeatherFx)
        {
            Log.Warning(
                "[PersonalTime] EnableWeatherFx is false — time/weather overrides will not render. Set EnableWeatherFx: true.");
        }

        Log.Information("[PersonalTime] Enabled — weather decorator (no flicker re-push)");
        return base.StartAsync(cancellationToken);
    }

    protected override Task ExecuteAsync(CancellationToken stoppingToken) => Task.CompletedTask;

    private void OnSetTime(ACTcpClient client, SetTimePacket packet)
    {
        if (!_config.Enabled)
            return;

        if (packet.Mode == "sync")
        {
            _personalTime.SyncTime(client.SessionId);
            Log.Debug("[PersonalTime] {Name} synced time to server", client.Name);
            _weatherManager.SendWeather(client);
            return;
        }

        if (packet.Mode != "set" || !int.TryParse(packet.Seconds, out var seconds))
            return;

        seconds = Math.Clamp(seconds, 0, 86399);
        _personalTime.SetTime(client.SessionId, seconds);
        Log.Debug("[PersonalTime] {Name} set personal time to {Seconds}s", client.Name, seconds);

        if (client.IsAdministrator)
        {
            // Clear personal so we don't send a second conflicting packet after SetTime broadcast.
            _personalTime.SyncTime(client.SessionId);
            _weatherManager.SetTime(seconds);
            Log.Information("[PersonalTime] Admin {Name} applied server time {Seconds}s", client.Name, seconds);
            return;
        }

        PushPersonal(client);
    }

    private void OnSetWeather(ACTcpClient client, SetWeatherPacket packet)
    {
        if (!_config.Enabled)
            return;

        if (packet.Mode == "sync")
        {
            _personalTime.SyncWeather(client.SessionId);
            Log.Debug("[PersonalTime] {Name} synced weather to server", client.Name);
            _weatherManager.SendWeather(client);
            return;
        }

        if (packet.Mode != "set" || !int.TryParse(packet.Type, out var typeValue))
            return;

        if (!Enum.IsDefined(typeof(WeatherFxType), typeValue))
            return;

        var weather = (WeatherFxType)typeValue;
        _personalTime.SetWeather(client.SessionId, weather);
        Log.Debug("[PersonalTime] {Name} set personal weather to {Weather}", client.Name, weather);

        if (client.IsAdministrator)
        {
            _personalTime.SyncWeather(client.SessionId);
            _weatherManager.SetCspWeather(weather, 8);
            Log.Information("[PersonalTime] Admin {Name} applied server weather {Weather}", client.Name, weather);
            return;
        }

        PushPersonal(client);
    }

    private void PushPersonal(ACTcpClient client)
    {
        if (!_personalTime.TryBuildPacket(
                client.SessionId,
                _weatherManager.CurrentWeather,
                _weatherManager.CurrentDateTime,
                out CSPWeatherUpdate packet))
        {
            return;
        }

        try
        {
            client.SendPacketUdp(in packet);
        }
        catch (Exception ex)
        {
            Log.Debug(ex, "[PersonalTime] Failed to push weather to {Name}", client.Name);
        }
    }

    private void OnClientDisconnected(ACTcpClient sender, EventArgs args)
    {
        _personalTime.Clear(sender.SessionId);
    }
}
