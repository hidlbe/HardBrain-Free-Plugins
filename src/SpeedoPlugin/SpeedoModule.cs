using AssettoServer.Server.Plugin;
using Autofac;
using Microsoft.Extensions.Hosting;

namespace SpeedoPlugin;

public class SpeedoModule : AssettoServerModule<SpeedoConfiguration>
{
    protected override void Load(ContainerBuilder builder)
    {
        builder.RegisterType<SpeedoPlugin>()
            .AsSelf()
            .As<IHostedService>()
            .SingleInstance();
    }
}
