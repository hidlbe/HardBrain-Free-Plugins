using JetBrains.Annotations;
using YamlDotNet.Serialization;

namespace SpeedoPlugin;

[UsedImplicitly(ImplicitUseKindFlags.Assign, ImplicitUseTargetFlags.WithMembers)]
public class SpeedoConfiguration
{
    [YamlMember(Description = "Broadcast server-authoritative speeds to all clients")]
    public bool Enabled { get; init; } = true;

    [YamlMember(Description = "Server sync rate in Hz (8-20 recommended)")]
    public int UpdateRateHz { get; init; } = 12;

    [YamlMember(Description = "Show live speed tower for all connected drivers (disabled — removed from HUD)")]
    public bool ShowLiveTower { get; init; } = false;

    [YamlMember(Description = "Show gear and RPM under the speed readout")]
    public bool ShowGearRpm { get; init; } = true;

    [YamlMember(Description = "Speed units: kmh or mph")]
    public string Units { get; init; } = "kmh";
}
