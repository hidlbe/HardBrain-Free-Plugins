using AssettoServer.Network.ClientMessages;

namespace PersonalTimePlugin.Packets;

[OnlineEvent(Key = "AS1980_SetTime")]
public class SetTimePacket : OnlineEvent<SetTimePacket>
{
    [OnlineEventField(Name = "mode", Size = 4)]
    public string Mode = "";

    [OnlineEventField(Name = "seconds", Size = 8)]
    public string Seconds = "";
}
