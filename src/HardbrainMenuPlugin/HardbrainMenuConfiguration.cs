using JetBrains.Annotations;
using YamlDotNet.Serialization;

namespace HardbrainMenuPlugin;

[UsedImplicitly(ImplicitUseKindFlags.Assign, ImplicitUseTargetFlags.WithMembers)]
public class HardbrainMenuConfiguration
{
    [YamlMember(Description = "Push the Hardbrain in-game menu (M/B/V) to all connected players")]
    public bool Enabled { get; init; } = true;
}
