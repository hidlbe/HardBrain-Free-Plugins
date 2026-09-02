using AssettoServer.Server.Plugin;
using AssettoServer.Server.Weather.Implementation;
using Autofac;
using Microsoft.Extensions.Hosting;

namespace PersonalTimePlugin;

public class PersonalTimeModule : AssettoServerModule<PersonalTimeConfiguration>
{
    protected override void Load(ContainerBuilder builder)
    {
        builder.RegisterType<PersonalTimeService>().AsSelf().SingleInstance();
        builder.RegisterDecorator<PersonalWeatherDecorator, IWeatherImplementation>();
        builder.RegisterType<PersonalTimePlugin>()
            .AsSelf()
            .As<IHostedService>()
            .SingleInstance();
    }
}
