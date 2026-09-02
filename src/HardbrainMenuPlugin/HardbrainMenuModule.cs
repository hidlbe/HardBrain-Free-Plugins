using AssettoServer.Server.Plugin;
using Autofac;
using Microsoft.Extensions.Hosting;

namespace HardbrainMenuPlugin;

public class HardbrainMenuModule : AssettoServerModule<HardbrainMenuConfiguration>
{
    protected override void Load(ContainerBuilder builder)
    {
        builder.RegisterType<HardbrainMenuPlugin>()
            .AsSelf()
            .As<IHostedService>()
            .SingleInstance();
    }
}
