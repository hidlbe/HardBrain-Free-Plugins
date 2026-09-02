# Installation Guide — HardBrain Free Plugins

## 1. Server version
Use **AssettoServer 0.0.55** (or newer). Older 0.0.54 / net8 builds will not load these plugins.

## 2. Copy plugins
From this repo, copy:

```
release/plugins/SpeedoPlugin          →  <server>/plugins/SpeedoPlugin
release/plugins/HardbrainMenuPlugin   →  <server>/plugins/HardbrainMenuPlugin
release/plugins/PersonalTimePlugin    →  <server>/plugins/PersonalTimePlugin
```

Each folder must contain the `.dll`, `.deps.json`, `.runtimeconfig.json`, and (for menu/speedo) the `lua/` folder.

## 3. Enable in `cfg/extra_cfg.yml`

```yaml
EnableClientMessages: true
EnableWeatherFx: true
MinimumCSPVersion: 2651

EnablePlugins:
  - SpeedoPlugin
  - HardbrainMenuPlugin
  - PersonalTimePlugin

---
!SpeedoConfiguration
Enabled: true
ShowLiveTower: false
ShowGearRpm: true
Units: "kmh"

---
!HardbrainMenuConfiguration
Enabled: true

---
!PersonalTimeConfiguration
Enabled: true
```

Full example: [`extra_cfg.example.yml`](extra_cfg.example.yml)

## 4. Remove Pastebin scripts
Edit `cfg/csp_extra_options.ini` and **delete** any block like:

```ini
[SCRIPT_0]
SCRIPT = "https://pastebin.com/raw/...."
```

Keep other sections (e.g. `[EXTRA_RULES]`) as they are.

## 5. Restart & reconnect
1. Restart the server process  
2. Every player must **disconnect and reconnect** (or restart Content Manager) so CSP loads the new server scripts  

## Controls

| Key | Action |
|-----|--------|
| **M** | Open HardBrain menu |
| **Drag** on speedo | Move HUD |
| **Mouse wheel** on speedo | Resize HUD |
| Menu tabs | Teleport, boost, repair, time, weather, … |

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Menu / speedo missing | Reconnect; check `EnableClientMessages` and plugin loaded in logs |
| `No plugin found with name …` | DLL folder name must match `EnablePlugins` entry |
| Time/weather UI clicks but nothing changes | Enable `PersonalTimePlugin` + `EnableWeatherFx: true` |
| Weather flickers | Use the PersonalTime build that includes the weather decorator (this release) |
| Old pastebin menu still shows | Remove `[SCRIPT_*]` from `csp_extra_options.ini` and restart |
| Crash mentioning DWrite | This speedo build avoids DWrite; make sure you deployed the new `speedo.lua` |

## Logs to look for

```
[Speedo] Enabled — local HUD only...
[HardbrainMenu] Enabled — server-pushed menu for all players
[PersonalTime] Enabled — weather decorator (no flicker re-push)
Server startup completed
```
