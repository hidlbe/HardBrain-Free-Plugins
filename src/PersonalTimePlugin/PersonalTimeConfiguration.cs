using JetBrains.Annotations;
using YamlDotNet.Serialization;

namespace PersonalTimePlugin;

[UsedImplicitly(ImplicitUseKindFlags.Assign, ImplicitUseTargetFlags.WithMembers)]
public class PersonalTimeConfiguration
{
    [YamlMember(Description = "Allow each player to set personal time of day and weather from the Hardbrain menu")]
    public bool Enabled { get; init; } = true;
}
