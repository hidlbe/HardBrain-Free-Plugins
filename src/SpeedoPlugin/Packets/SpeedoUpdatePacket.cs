using AssettoServer.Network.ClientMessages;

namespace SpeedoPlugin.Packets;

[OnlineEvent(Key = "speedoUpdate")]
public class SpeedoUpdatePacket : OnlineEvent<SpeedoUpdatePacket>
{
    [OnlineEventField(Name = "speedKmh")]
    public ushort SpeedKmh;

    [OnlineEventField(Name = "gear")]
    public sbyte Gear;

    [OnlineEventField(Name = "rpm")]
    public ushort Rpm;
}
