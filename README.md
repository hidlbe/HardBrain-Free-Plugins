# HardBrain Free Plugins

**GitHub:** https://github.com/hidlbe/HardBrain-Free-Plugins  
**Website:** https://hardbrain.host

**مجاني بالكامل · بدون Pastebin · يعمل على AssettoServer 0.0.55+**

Server-pushed CSP scripts for Assetto Corsa online servers powered by [AssettoServer](https://github.com/compujuckel/AssettoServer).

| Plugin | What it does |
|--------|----------------|
| **HardbrainMenuPlugin** | In-game menu (M) — teleport, boost, repair, rewind, skins, time/weather UI, and more |
| **SpeedoPlugin** | Native speed HUD — gear / RPM / KMH — **drag to move**, **scroll to resize** |
| **PersonalTimePlugin** | Makes menu Time & Weather actually apply (per-player, no flicker) |

> The first two are the public “free scripts”. PersonalTime is included because the menu Time/Weather tabs need it.

## Hosting — KVM & game servers

Need a server for Assetto Corsa or anything else?

You can get **any KVM** and **game hosting** from us at **[hardbrain.host](https://hardbrain.host)** — panels, game servers, and full VPS/KVM setups.

تحتاج سيرفر لـ Assetto Corsa أو أي لعبة ثانية؟  
تقدر تطلب **أي KVM** و**استضافة ألعاب** من عندنا عبر **[hardbrain.host](https://hardbrain.host)**.

---

## بالعربية — الشرح الكامل

### ليش هذي البلجنز؟
كثير سيرفرات كانت تعتمد **Pastebin** عشان تسوي منيو أو سبيدو. هالطريقة:
- تنكسر إذا انحذف الرابط
- أبطأ وأقل أمان
- كل لاعب يحتاج إعداد يدوي أحيانًا

حلول HardBrain تدفع السكربتات **من السيرفر مباشرة** لكل اللاعبين:
1. تدخل السيرفر
2. تعمل **Reconnect** مرة
3. المنيو والسبيدو يظهرون تلقائي — **بدون Pastebin**

### 1) HardBrain Menu
- زر **M** يفتح المنيو
- Teleport / Fast Travel / Boost / Repair / Rewind
- تغيير السكن، الإعدادات، الوقت والطقس من التبويبات
- شريط اختصارات تحت الشاشة (M / N / T / B / V / R / C / X)

### 2) HardBrain Speedo
- عداد سرعة أصلي (Lua) — خفيف، بدون WebBrowser
- يعرض: **Gear** + **RPM** + **KMH/MPH** + ABS/TC
- **اسحب** البانل عشان تحركه
- **عجلة الماوس** فوقه عشان تكبره / تصغره
- المكان والحجم ينحفظون تلقائي
- بدون قائمة LIVE SPEEDS

### 3) PersonalTime (مرافق للمينيو)
- يستقبل أوامر الوقت/الطقس من المنيو
- يطبقها **لك أنت** (شخصي) بدون ما يغير جو السيرفر لباقي اللاعبين (إلا الأدمن)
- بدون وميض (flicker) — يستخدم weather decorator بدل إعادة إرسال عدوانية

### متطلبات
- AssettoServer **0.0.55** (net9) أو أحدث
- `EnableClientMessages: true`
- `MinimumCSPVersion: 2651` (أو أحدث)
- للوقت/الطقس: `EnableWeatherFx: true`
- احذف أي `[SCRIPT_x]` من `csp_extra_options.ini` اللي فيه pastebin

### التثبيت السريع
1. انسخ مجلدات `release/plugins/*` إلى `plugins/` في سيرفرك
2. عدّل `cfg/extra_cfg.yml` (انظر `docs/extra_cfg.example.yml`)
3. احذف سكربتات Pastebin من `cfg/csp_extra_options.ini`
4. أعد تشغيل السيرفر
5. اللاعب يعمل **Reconnect**

---

## English — Full documentation

### Why these plugins?
Pastebin-based online scripts break, lag, and are hard to maintain. These plugins **push Lua from the server** via AssettoServer’s `CSPServerScriptProvider`. Players only need to reconnect.

### HardbrainMenuPlugin
Pushes `hardbrain_menu.lua` to every client. Opens with **M**. Includes teleport, boost, repair, rewind, cosmetics, and time/weather UI tabs.

### SpeedoPlugin
Pushes `speedo.lua`. Local physics HUD (no network tower).  
**Drag** to move · **Mouse wheel** to resize · settings saved in `ac.storage`.

### PersonalTimePlugin
Companion for menu time/weather. Decorates `IWeatherImplementation` so personal overrides replace the global weather packet for that client (no flicker fight).

### Requirements
- AssettoServer **0.0.55+**
- `EnableClientMessages: true`
- `MinimumCSPVersion: 2651+`
- WeatherFX for personal time/weather: `EnableWeatherFx: true`
- Remove pastebin `[SCRIPT_*]` entries from `csp_extra_options.ini`

### Install
See [`docs/INSTALL.md`](docs/INSTALL.md) and [`docs/extra_cfg.example.yml`](docs/extra_cfg.example.yml).

Drop `release/plugins/{SpeedoPlugin,HardbrainMenuPlugin,PersonalTimePlugin}` into your server `plugins/` folder, enable them in `extra_cfg.yml`, restart, reconnect.

---

## Repository layout

```
release/plugins/     ← drop-in DLLs + lua (use this on your server)
src/                 ← C# + lua source
docs/                ← install guide, example config, Discord post
LICENSE              ← AGPL-3.0 (compatible with AssettoServer)
```

## Building from source

Requires the AssettoServer 0.0.55 solution (project references). Open the `.csproj` files inside a checkout of AssettoServer and `dotnet build -c Release`.

Prebuilt binaries for linux/win plugin hosts are under `release/plugins/`.

## License

AGPL-3.0 — same family as AssettoServer. Free to use on your servers. If you distribute modified versions, share the source.

## Credits

[HardBrain](https://hardbrain.host) · AssettoServer by compujuckel · CSP by x4fab
