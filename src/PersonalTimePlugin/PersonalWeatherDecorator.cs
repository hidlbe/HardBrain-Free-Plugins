using AssettoServer.Network.Tcp;
using AssettoServer.Server;
using AssettoServer.Server.Weather;
using AssettoServer.Server.Weather.Implementation;
using AssettoServer.Shared.Network.Packets.Outgoing;
using NodaTime;

namespace PersonalTimePlugin;

/// <summary>
/// Wraps the stock weather sender so personal time/weather replace the
/// broadcast for that client instead of fighting it (which caused flicker).
/// </summary>
public class PersonalWeatherDecorator : IWeatherImplementation
{
    private readonly IWeatherImplementation _inner;
    private readonly PersonalTimeService _personalTime;
    private readonly EntryCarManager _entryCarManager;

    public PersonalWeatherDecorator(
        IWeatherImplementation inner,
        PersonalTimeService personalTime,
        EntryCarManager entryCarManager)
    {
        _inner = inner;
        _personalTime = personalTime;
        _entryCarManager = entryCarManager;
    }

    public void SendWeather(WeatherData weather, ZonedDateTime dateTime, ACTcpClient? client = null)
    {
        if (client != null)
        {
            if (TrySendPersonal(client, weather, dateTime))
                return;
            _inner.SendWeather(weather, dateTime, client);
            return;
        }

        // Per-client send: personal override OR default weather (never double-send).
        foreach (var car in _entryCarManager.EntryCars)
        {
            if (car.Client is not { HasSentFirstUpdate: true } c)
                continue;

            if (!TrySendPersonal(c, weather, dateTime))
                _inner.SendWeather(weather, dateTime, c);
        }
    }

    private bool TrySendPersonal(ACTcpClient client, WeatherData weather, ZonedDateTime dateTime)
    {
        if (!_personalTime.TryBuildPacket(client.SessionId, weather, dateTime, out CSPWeatherUpdate packet))
            return false;

        client.SendPacketUdp(in packet);
        return true;
    }
}
