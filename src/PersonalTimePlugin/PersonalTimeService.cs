using AssettoServer.Server.Weather;
using AssettoServer.Shared.Network.Packets.Outgoing;
using AssettoServer.Shared.Weather;
using NodaTime;

namespace PersonalTimePlugin;

public class PersonalTimeService
{
    private sealed class PlayerState
    {
        public bool PersonalTime;
        public int TimeSeconds;
        public bool PersonalWeather;
        public WeatherFxType WeatherType = WeatherFxType.Clear;
    }

    private readonly Dictionary<byte, PlayerState> _states = new();
    private readonly IWeatherTypeProvider _weatherTypeProvider;

    public PersonalTimeService(IWeatherTypeProvider weatherTypeProvider)
    {
        _weatherTypeProvider = weatherTypeProvider;
    }

    public bool HasOverride(byte sessionId) =>
        _states.TryGetValue(sessionId, out var state) && (state.PersonalTime || state.PersonalWeather);

    public void Clear(byte sessionId) => _states.Remove(sessionId);

    public void SetTime(byte sessionId, int seconds)
    {
        var state = GetState(sessionId);
        state.PersonalTime = true;
        state.TimeSeconds = Math.Clamp(seconds, 0, 86399);
    }

    public void SyncTime(byte sessionId)
    {
        if (_states.TryGetValue(sessionId, out var state))
            state.PersonalTime = false;
    }

    public void SetWeather(byte sessionId, WeatherFxType type)
    {
        var state = GetState(sessionId);
        state.PersonalWeather = true;
        state.WeatherType = type;
    }

    public void SyncWeather(byte sessionId)
    {
        if (_states.TryGetValue(sessionId, out var state))
            state.PersonalWeather = false;
    }

    public bool TryBuildPacket(
        byte sessionId,
        WeatherData baseWeather,
        ZonedDateTime baseDateTime,
        out CSPWeatherUpdate packet)
    {
        packet = default;

        if (!_states.TryGetValue(sessionId, out var state))
            return false;

        if (!state.PersonalTime && !state.PersonalWeather)
            return false;

        WeatherType weatherType;
        WeatherType upcomingType;
        float rainIntensity;
        float rainWetness;
        float rainWater;
        float humidity;
        ushort transitionValue;

        if (state.PersonalWeather)
        {
            weatherType = _weatherTypeProvider.GetWeatherType(state.WeatherType);
            upcomingType = weatherType;
            rainIntensity = weatherType.RainIntensity;
            rainWetness = weatherType.RainWetness;
            rainWater = weatherType.RainWater;
            humidity = weatherType.Humidity;
            transitionValue = ushort.MaxValue;
        }
        else
        {
            weatherType = baseWeather.Type;
            upcomingType = baseWeather.UpcomingType;
            rainIntensity = baseWeather.RainIntensity;
            rainWetness = baseWeather.RainWetness;
            rainWater = baseWeather.RainWater;
            humidity = baseWeather.Humidity;
            transitionValue = baseWeather.TransitionValue;
        }

        var dateTime = baseDateTime;
        if (state.PersonalTime)
        {
            dateTime = baseDateTime.Date
                .AtStartOfDayInZone(baseDateTime.Zone)
                .PlusSeconds(state.TimeSeconds);
        }

        packet = new CSPWeatherUpdate
        {
            UnixTimestamp = (ulong)dateTime.ToInstant().ToUnixTimeSeconds(),
            WeatherType = (byte)weatherType.WeatherFxType,
            UpcomingWeatherType = (byte)upcomingType.WeatherFxType,
            TransitionValue = transitionValue,
            TemperatureAmbient = (Half)baseWeather.TemperatureAmbient,
            TemperatureRoad = (Half)baseWeather.TemperatureRoad,
            TrackGrip = (Half)baseWeather.TrackGrip,
            WindDirectionDeg = (Half)baseWeather.WindDirection,
            WindSpeed = (Half)baseWeather.WindSpeed,
            Humidity = (Half)humidity,
            Pressure = (Half)baseWeather.Pressure,
            RainIntensity = (Half)rainIntensity,
            RainWetness = (Half)rainWetness,
            RainWater = (Half)rainWater
        };

        return true;
    }

    private PlayerState GetState(byte sessionId)
    {
        if (!_states.TryGetValue(sessionId, out var state))
        {
            state = new PlayerState();
            _states[sessionId] = state;
        }

        return state;
    }
}
