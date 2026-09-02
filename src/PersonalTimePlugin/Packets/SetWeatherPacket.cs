using AssettoServer.Network.ClientMessages;

namespace PersonalTimePlugin.Packets;

[OnlineEvent(Key = "AS1980_SetWeather")]
public class SetWeatherPacket : OnlineEvent<SetWeatherPacket>
{
    [OnlineEventField(Name = "mode", Size = 4)]
    public string Mode = "";

    [OnlineEventField(Name = "type", Size = 4)]
    public string Type = "";
}
