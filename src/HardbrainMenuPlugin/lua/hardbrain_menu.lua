-- Hardbrain Menu - keyboard-triggered server hub panel
--   M = open/close menu   B = instant boost   V = repair
--   N = FastTravel map (FastTravelPlugin)   T = teleport tab
--   C = chat bar   R = hold rewind   X = pit reset
-- Server-pushed by HardbrainMenuPlugin + PersonalTimePlugin.
-- Brand: Hardbrain Racing - https://cp.hardbrain.store
---------------------------------------------------------------

local PANEL_W, PANEL_H = 624, 608
local NAV = 138
-- Logo embedded directly (base64) so it ALWAYS renders ... no server URL / internet needed.
-- Re-embed by replacing plugins\FastTravelPlugin\wwwroot\logo1980.png then re-running the embed step.

---------------------------------------------------------------
-- Player-selectable accent colour (saved locally, per machine)
---------------------------------------------------------------
local PALETTE = {
  { name = "Purple",  c = rgbm(0.55, 0.36, 0.96, 1) },
  { name = "Blue",    c = rgbm(0.28, 0.62, 1.00, 1) },
  { name = "Cyan",   c = rgbm(0.20, 0.84, 0.95, 1) },
  { name = "Green",    c = rgbm(0.24, 0.84, 0.50, 1) },
  { name = "Gold",    c = rgbm(0.98, 0.76, 0.20, 1) },
  { name = "Orange", c = rgbm(0.98, 0.54, 0.15, 1) },
  { name = "Pink",    c = rgbm(0.96, 0.36, 0.62, 1) },
  { name = "Red",    c = rgbm(0.95, 0.32, 0.32, 1) },
}
local stor = ac.storage({ accentIdx = 1, driftEnabled = true, rulesAgreed = false, chatOpacity = 0.95, menuOpacity = 0.95, menuOfsX = 0, menuOfsY = 0, chatOfsX = 0, chatOfsY = 0, rec1 = "+1", rec2 = "GG", rec3 = "GL", perfMode = false, extraKeep = true })
if stor.chatOpacity < 0.35 then stor.chatOpacity = 0.95 end
if stor.menuOpacity < 0.35 then stor.menuOpacity = 0.95 end
if stor.accentIdx < 1 or stor.accentIdx > #PALETTE then stor.accentIdx = 1 end

-- ... Performance mode: reduce lag using ONLY runtime overrides ... nothing is written to the
-- player's saved CSP config; everything auto-reverts when the script unloads or on toggle-off.
-- Verified levers an online script may pull (shadows / post-processing / OTHER cars' smoke are NOT reachable):
--   overrideLODMultiplier .. disableVirtualMirror .. overrideTyreSmoke (own car only) ..
--   setDriverVisible + hideCarLabels (per car, re-applied each tick for new joiners) ..
--   setScriptFlamesIntensity .. disableExtraHUDElements
local perfHudMask = { "proximity", "ping", "damage" }
local function perfApplyPerCar(on)
  local sim = ac.getSim()
  if not sim then return end
  local skip = sim.focusedCar          -- never hide the local player's own driver / cockpit hands
  for i = 0, sim.carsCount - 1 do
    if i ~= skip then
      pcall(function()
        ac.setDriverVisible(i, not on)
        ac.hideCarLabels(i, on)
      end)
    end
  end
end
local function applyPerfMode(on)
  pcall(function()
    if on then
      ac.overrideLODMultiplier(0.5, 0.6)            -- distant track/cars drop to cheap LODs sooner
      ac.disableVirtualMirror(true)                 -- kill the extra virtual-mirror render pass
      for t = 0, 3 do ac.overrideTyreSmoke(t, 0, 0) end  -- kill YOUR OWN smoke cloud (biggest felt gain while drifting)
      ac.setScriptFlamesIntensity(0)                -- no exhaust-flame particles
      ac.disableExtraHUDElements(perfHudMask, true)
    else
      ac.overrideLODMultiplier(nil, nil)
      ac.disableVirtualMirror(false)
      for t = 0, 3 do ac.overrideTyreSmoke(t, math.nan, 0) end
      ac.setScriptFlamesIntensity(1)
      ac.disableExtraHUDElements(perfHudMask, false)
    end
    perfApplyPerCar(on)
  end)
end
-- grouped per-frame state (kept in ONE table to stay under LuaJIT's 200-locals-per-chunk limit)
local uSt = {
  perfInit = false, perfTick = 0, extraTick = 0, timeApplied = false, gripTick = 0, localFxTick = 0,
  timeHour = 15.0, timePending = false, timeSynced = true, selWeather = -1,
  notifNextAt = 45, notifStart = -100, notifIdx = 0,
}

local CW  = rgbm.colors.white
local CDm = rgbm(0.58, 0.62, 0.70, 1)
local CC  = rgbm(0.36, 0.80, 1.00, 1)
local CY  = rgbm(0.96, 0.76, 0.22, 1)
local CR  = rgbm(0.92, 0.30, 0.32, 1)
local COR = rgbm(0.97, 0.55, 0.12, 1)
local CGR = rgbm(0.25, 0.85, 0.50, 1)
local CPU = rgbm(0.58, 0.38, 0.96, 1)
local DK  = rgbm(0.04, 0.05, 0.07, 1)
local ACC = PALETTE[stor.accentIdx].c

local function placeCarOnGround(x, z, fwd, el)
  el = el or 0.8
  local cH = 5000
  local d = physics.raycastTrack(vec3(x, cH, z), vec3(0, -1, 0), cH + 20)
  local f = vec3(fwd.x, 0, fwd.z)
  if f:length() < 1e-3 then f = vec3(0, 0, 1) else f = f:normalize() end
  -- setCarPosition orients the car to FACE -dir, so pass -f to keep it facing `fwd`
  local dir = vec3(-f.x, 0, -f.z)
  if d ~= -1 then
    physics.setCarVelocity(0, vec3(0, 0, 0))
    physics.setCarPosition(0, vec3(x, cH - d + el, z), dir)
  else
    physics.setCarVelocity(0, vec3(0, 0, 0))
    physics.setCarPosition(0, vec3(x, ac.getCar(0).position.y + 1, z), dir)
  end
end

local CD = 3
local GT = 10
local tmr = { r = 0, l = CD }
local ghostT, ghostOn = 0, false
local selI, tpM, grp = -1, 1, 1.0
-- traction: grp 1.0 = full grip, 0.0 = maximum slip. Maps to physics grip decrease (0..0.5).
local function applyGrip() pcall(function() physics.setGripDecrease(0, ac.Wheel.All, (1 - grp) * 0.5) end) end
local BOOST_TARGET = 250
local BOOST_CD = 5
local boostTimer = 0
local pulseT = 0
local activeTab = 5
local menuOpen = false
local menuDragging, menuDragStart, menuOfsStart = false, vec2(0, 0), vec2(0, 0)
local chatDragging, chatDragStart, chatOfsStart = false, vec2(0, 0), vec2(0, 0)

local tcOn, absOn, autoShiftOn = false, false, false
local turboLvl = 5
local headlightsOn, highBeamsOn = false, false
local selTurn = 0
local extraState = { false, false, false, false, false, false }

-- Drift meter state
local driftActive, driftMult, driftRun = false, 1, 0
local driftTotal, driftBest = 0, 0
local driftMultTime, driftBreak, driftCurAngle, driftShown = 0, 0, 0, 0
local driftYaw, driftSpins, driftSessionSpins = 0, 0, 0

-- Flashback (rewind) state ... hold R
local rewHist = {}
local REW_MAX = 300
local REW_INT = 0.05
local REW_KEY = ui.KeyIndex.R
local rewTimer = 0
local rewinding = false
local rewIdx = 0

-- Custom chat: renders Arabic correctly (vanilla chat mangles/reverses it) + quick phrases
local chatLog = {}
local CHAT_MAX = 60
local chatBarOpen = false
local chatBarJustOpened = false
local chatInput = ""
local chatInputGen = 0
local chatBarLastCount = 0

-- Rules / Discord-link welcome screen
local rulesOpen = false
local rulesInit = false
local linkCode = nil
local isLinked = false
local QUICK_PHRASES = {
  "Good luck!", "Nice drift!", "See you at the line", "GG",
  "Clean lap!", "Thanks for the race",
}
local EMOJIS = {
  ":)", ":D", "xD", "GG", "GL", "HF", "WP", "NT", "BRB", "AFK", "LOL", "OMG",
  "GLHF", "WP!", "NT!", "EZ", "RIP", "F", "Pog", "W", "L", "GOAT", "CLUTCH", "SICK",
  "DRIFT", "CLEAN", "FAST", "SLOW", "PIT", "RACE", "!!!", "???", "100", "OK", "NO", "YES",
}
local function useEmoji(em)
  chatInput = chatInput .. em
  chatInputGen = chatInputGen + 1
  local a, b, c = stor.rec1, stor.rec2, stor.rec3
  if em == a then return end
  if em == b then stor.rec1 = em; stor.rec2 = a; return end
  if em == c then stor.rec1 = em; stor.rec2 = a; stor.rec3 = b; return end
  stor.rec1 = em; stor.rec2 = a; stor.rec3 = b
end
-- Translate common English SERVER lines (ReportPlugin etc.) for the custom chat.
local SERVER_TR = {
  { "No replay submitted", "No replay clip saved - press Ctrl+Shift+S in Content Manager to capture evidence." },
  { "Replay received", "Replay clip received by the server." },
  { "Use /report", "Use /report in chat or open the report panel from the menu." },
  { "Please wait a moment before submitting", "Please wait before submitting another report." },
  { "Your report has been submitted", "Your report has been submitted. Staff will review it." },
  { "You have been kicked", "You have been removed from the server." },
  { "You have been banned", "You have been banned from this server." },
  { "shutting down", "Server is shutting down - thanks for racing with Hardbrain!" },
}
local function translateServer(m)
  local carN, drv = m:match("^Car (%d+) is now driven by (.+)$")
  if carN then return "Car " .. carN .. " is now driven by " .. drv end
  for _, e in ipairs(SERVER_TR) do
    if m:find(e[1], 1, true) then return e[2] end
  end
  return m
end
ac.onChatMessage(function(message, carIdx)
  local msg = tostring(message)
  -- Discord link code pushed by the server plugin -> show it inside the rules screen (renders Arabic), never as raw chat
  local code = msg:match("%$AS1980_CODE:([%w]+)")
  if code then
    linkCode = code
    isLinked = false
    rulesOpen = true
    return true
  end
  if msg:find("%$AS1980_LINKED") then
    isLinked = true
    linkCode = nil
    return true
  end
  if msg:find("%$AS1980_GETCODE") then return true end  -- suppress our own request echo
  -- Tagged message from the plugin: "$AS1980_MSG:<color>|<emoji>|<tag>|<name>|<message>" -> name colored by Discord role
  local mcol, memo, mtag, mnm, mtxt = msg:match("^%$AS1980_MSG:([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
  if mnm then
    local rr, gg, bb = mcol:match("#?(%x%x)(%x%x)(%x%x)")
    local color = rr and rgbm(tonumber(rr, 16) / 255, tonumber(gg, 16) / 255, tonumber(bb, 16) / 255, 1) or nil
    local disp = mnm .. (mtag ~= "" and ("  " .. mtag) or "") .. (memo ~= "" and (" " .. memo) or "")
    chatLog[#chatLog + 1] = { name = disp, text = mtxt, srv = false, color = color, rawName = mnm, t = pulseT }
    while #chatLog > CHAT_MAX do table.remove(chatLog, 1) end
    return true
  end
  -- Hide admin-command noise (e.g. the comfy_admin client app spamming /ballast, /set... while not logged in as admin)
  if msg:find("not an administrator") or msg:find("Unrecognized command") then return true end
  local srv = not carIdx or carIdx < 0
  local name = srv and "Hardbrain Racing" or (ac.getDriverName(carIdx) or ("Driver " .. tostring(carIdx)))
  chatLog[#chatLog + 1] = { name = name, text = translateServer(msg), srv = srv, rawName = (not srv) and name or nil, t = pulseT }
  while #chatLog > CHAT_MAX do table.remove(chatLog, 1) end
  return true
end)
-- Hardbrain Racing welcome (shows on join in the custom chat)
chatLog[#chatLog + 1] = { name = "Hardbrain Racing", text = "Welcome to Hardbrain Racing! Press M for menu, C for chat - discord.gg/hardbrain", srv = true, t = 0 }

-- Keep the top system-message strip CLEAR (reserved for something important later).
-- Hide the default English join/leave lines AND suppress the plugin's internal $AS1980_MSG marker
-- if it ever leaks into the top strip (it's parsed & shown properly in the custom chat instead).
for _, rx in ipairs({ "onnected", "joined the server", "left the server", "has left", "AS1980_", "%$AS1980" }) do
  pcall(function() ac.blockSystemMessages(rx) end)
end

-- Report/complaint state - the button shows in the menu rail 30s after joining
local reportOpen = false
local reportInput = ""
local reportInputGen = 0

---------------------------------------------------------------
-- Helpers
---------------------------------------------------------------
local function dwBox(t, s, x, y, w, h, c)
  ui.setCursor(vec2(x, y))
  ui.dwriteTextAligned(t, s, ui.Alignment.Center, ui.Alignment.Center, vec2(w, h), false, c or CW)
end
local function dwRightBox(t, s, x, y, w, h, c)
  ui.setCursor(vec2(x, y))
  ui.dwriteTextAligned(t, s, ui.Alignment.End, ui.Alignment.Center, vec2(w, h), false, c or CW)
end
local function dwLeftBox(t, s, x, y, w, h, c)
  ui.setCursor(vec2(x, y))
  ui.dwriteTextAligned(t, s, ui.Alignment.Start, ui.Alignment.Center, vec2(w, h), false, c or CW)
end
local function sectionTitle(t, X, Y, W)
  dwRightBox(t, 15, X, Y, W, 22, CW)
  ui.drawRectFilled(vec2(X + W - 32, Y + 24), vec2(X + W, Y + 26), ACC, 1)
end
local function drawArcProgress(cx, cy, r, prog, col, dotR)
  local segs = 64
  local n = math.floor(segs * math.min(math.max(prog, 0), 1))
  for i = 0, n do
    local a = -math.pi * 0.5 + (i / segs) * math.pi * 2
    ui.drawCircleFilled(vec2(cx + math.cos(a) * r, cy + math.sin(a) * r), dotR or 2, col, 6)
  end
end
local function bigButton(x, y, w, h, label, col, id)
  ui.setCursor(vec2(x, y))
  local cl = ui.invisibleButton(id or ("##b" .. label), vec2(w, h))
  local hov = ui.itemHovered()
  local c = hov and rgbm(col.r * 1.14, col.g * 1.14, col.b * 1.14, 1) or col
  ui.drawRectFilled(vec2(x, y), vec2(x + w, y + h), c, 9)
  if hov then ui.drawRect(vec2(x, y), vec2(x + w, y + h), rgbm(1, 1, 1, 0.35), 9, nil, 1) end
  dwBox(label, 13, x, y, w, h, DK)
  return cl
end
local function segToggle(x, y, w, h, opts, sel)
  ui.drawRectFilled(vec2(x, y), vec2(x + w, y + h), rgbm(1, 1, 1, 0.05), 9)
  ui.drawRect(vec2(x, y), vec2(x + w, y + h), rgbm(1, 1, 1, 0.08), 9, nil, 1)
  local n = #opts
  local iw = w / n
  local res = sel
  for i = 1, n do
    local ix = x + (i - 1) * iw
    ui.setCursor(vec2(ix, y))
    local cl = ui.invisibleButton("##sg" .. i .. opts[i], vec2(iw, h))
    if sel == i then
      ui.drawRectFilled(vec2(ix + 3, y + 3), vec2(ix + iw - 3, y + h - 3), rgbm(ACC.r, ACC.g, ACC.b, 0.9), 7)
    end
    dwBox(opts[i], 12, ix, y, iw, h, sel == i and DK or CDm)
    if cl then res = i end
  end
  return res
end

-- Real "ghost" mode: disable collisions locally AND tell other players to pass
-- through us too (so it can't be abused to ram people during boost/rewind/teleport).
local ghostSupported = physics.disableCarCollisions ~= nil
local ghostEvent = ac.OnlineEvent({
  ac.StructItem.key('AS1980_Ghost'),
  on = ac.StructItem.boolean(),
}, function(sender, data)
  if sender == nil then return end
  if ghostSupported then pcall(function() physics.disableCarCollisions(sender.index, data.on) end) end
end)
local function ghostStart(sec)
  sec = sec or 3
  if sec > ghostT then ghostT = sec end
  if not ghostOn then
    ghostOn = true
    if ghostSupported then pcall(function() physics.disableCarCollisions(0, true) end) end
    pcall(function() ghostEvent({ on = true }) end)
  end
end
local function ghostEnd()
  if ghostOn then
    if ghostSupported then pcall(function() physics.disableCarCollisions(0, false) end) end
    pcall(function() ghostEvent({ on = false }) end)
  end
  ghostOn = false; ghostT = 0
end
local function TPB(car)
  local d = car.look
  physics.setCarVelocity(0, vec3(0, 0, 0))
  physics.setCarPosition(0, car.position + vec3(0, 0.1, 0) - d * 8, -d)
  ghostStart()
end
local function TPS(car)
  local d = car.look
  physics.setCarPosition(0, car.position + vec3(0, 0.1, 0) - d * 8, -d)
  physics.setCarVelocity(0, car.velocity or vec3(0, 0, 0))
  ghostStart()
end

---------------------------------------------------------------
-- Skins
---------------------------------------------------------------
local _carDir = ac.getFolder(ac.FolderID.ContentCars) .. '/' .. ac.getCarID(0)
local _carSkins = {}
local _currentSkin = ac.getCarSkinID(0)
io.scanDir(_carDir .. '/skins', '*', function(fileName)
  table.insert(_carSkins, { name = fileName })
end)
local _originalSkin = ac.getCarSkinID(0)

local function applySkinDir(carNode, dir)
  local files = io.scanDir(dir, '*')
  if not files or #files == 0 then return end
  local map = {}
  for i = 1, #files do
    local f = files[i]
    local l = tostring(f):lower()
    if l ~= 'preview.jpg' and l ~= 'preview.png'
       and not l:match('%.json$') and not l:match('%.ini$') then
      map[f] = dir .. '/' .. f
    end
  end
  if next(map) ~= nil then carNode:applySkin(map) end
end

local function doApplySkin(skinName, carIndex)
  local theCar = ac.getCar(carIndex or 0)
  if not theCar then return end
  local carName = ac.getCarID(carIndex or 0)
  local carNode = ac.findNodes('carRoot:' .. theCar.index)
  local dir = ac.getFolder(ac.FolderID.ContentCars) .. '/' .. carName .. '/skins/' .. skinName
  -- Apply the CHOSEN skin straight onto the car. NO "original skin" base layer:
  -- that base only got partly covered by skins that don't ship every texture, so the
  -- default (white) showed through and a picked skin (e.g. red) looked white. Prefer
  -- CSP's folder-based skinning (maps every texture right); fall back to the manual map.
  carNode:resetSkin()
  if not pcall(function() carNode:applySkin(dir) end) then
    applySkinDir(carNode, dir)
  end
end

local _syncSkin = ac.OnlineEvent({
  skin = ac.StructItem.string(100),
  oldSkin = ac.StructItem.string(0),
}, function(sender, data)
  if sender == nil then return end
  doApplySkin(data.skin, sender.index)
end)

---------------------------------------------------------------
-- Personal Time / Weather — ac_apps bridge (HardbrainLocalFx)
-- Online script cannot call setWeatherTimeOffset; writes ac.storage
-- and calls _G hooks when the CSP app is loaded on the client.
---------------------------------------------------------------
local fxBridge = ac.storage({
  hb_rev = 0,
  hb_timeHour = 15.0,
  hb_weatherId = -1,
  hb_timeSync = 1,
  hb_weatherSync = 1,
})

local function bumpFx()
  fxBridge.hb_rev = (fxBridge.hb_rev or 0) + 1
end

local sendTime, syncTime, sendWeather, syncWeather
do
local SetTime = ac.OnlineEvent({
  ac.StructItem.key('AS1980_SetTime'),
  mode = ac.StructItem.string(4),
  seconds = ac.StructItem.string(8),
}, function(sender, data) end)

local TRACK_TIME_SHIFT = {}
local function trackTimeShift()
  local s = 0
  pcall(function() s = TRACK_TIME_SHIFT[ac.getTrackID()] or 0 end)
  return s
end

sendTime = function()
  local sec = (math.floor(uSt.timeHour * 3600) + trackTimeShift()) % 86400
  pcall(function() SetTime({ mode = 'set', seconds = tostring(sec) }) end)
  uSt.timeSynced = false
  fxBridge.hb_timeHour = uSt.timeHour
  fxBridge.hb_timeSync = 0
  bumpFx()
  if _G.Hardbrain_applyTime then pcall(_G.Hardbrain_applyTime, uSt.timeHour) end
end
syncTime = function()
  pcall(function() SetTime({ mode = 'sync', seconds = '0' }) end)
  uSt.timeSynced = true
  fxBridge.hb_timeSync = 1
  bumpFx()
  if _G.Hardbrain_syncTime then pcall(_G.Hardbrain_syncTime) end
end

local SetWeather = ac.OnlineEvent({
  ac.StructItem.key('AS1980_SetWeather'),
  mode = ac.StructItem.string(4),
  type = ac.StructItem.string(4),
}, function(sender, data) end)

sendWeather = function(id)
  pcall(function() SetWeather({ mode = 'set', type = tostring(id) }) end)
  uSt.selWeather = id
  fxBridge.hb_weatherId = id
  fxBridge.hb_weatherSync = 0
  bumpFx()
  if _G.Hardbrain_applyWeather then pcall(_G.Hardbrain_applyWeather, id) end
end
syncWeather = function()
  pcall(function() SetWeather({ mode = 'sync', type = '0' }) end)
  uSt.selWeather = -1
  fxBridge.hb_weatherId = -1
  fxBridge.hb_weatherSync = 1
  bumpFx()
  if _G.Hardbrain_syncWeather then pcall(_G.Hardbrain_syncWeather) end
end
end -- weather/time scope

local WEATHERS = {
  { id = 15, name = "Clear" },
  { id = 16, name = "Light Clouds" },
  { id = 17, name = "Mid Clouds" },
  { id = 18, name = "Heavy Clouds" },
  { id = 19, name = "Overcast" },
  { id = 20, name = "Fog" },
  { id = 6,  name = "Light Rain" },
  { id = 7,  name = "Rain" },
  { id = 1,  name = "Storm" },
  { id = 9,  name = "Light Snow" },
  { id = 10, name = "Snow" },
}

---------------------------------------------------------------
-- Boost + Repair actions (also bound to B / V keys)
---------------------------------------------------------------
local function doBoost()
  if boostTimer > 0 then return end
  local car = ac.getCar(0)
  if not car then return end
  local fwd = vec3(car.look.x, 0, car.look.z)
  if fwd:length() < 1e-3 then fwd = vec3(0, 0, 1) else fwd = fwd:normalize() end
  physics.setCarVelocity(0, fwd * (BOOST_TARGET / 3.6))
  boostTimer = BOOST_CD
  ghostStart(3)
end

local repairAt = -10
local function repairCar()
  local c = ac.getCar(0)
  pcall(function() physics.setCarBodyDamage(0, vec4(0, 0, 0, 0)) end)
  pcall(function() physics.setCarEngineLife(0, 1000) end)
  pcall(function() physics.resetColliderWears(0) end)
  if c then
    pcall(function() placeCarOnGround(c.position.x, c.position.z, c.look, 0.6) end)
  end
  repairAt = pulseT
  ghostStart(5) -- 5s no-collision protection right after repairing
end

---------------------------------------------------------------
-- Map globals
---------------------------------------------------------------
local ms = {}
local p3, d3, p2, d2, dx2 = vec3(), vec3(), vec2(), vec2(), vec2()
local pad = vec2(60, 60)
local ofs = -pad * 0.5
local tts = 8
local f1 = true
if ac.getPatchVersionCode() >= 2000 then
  map = ac.getFolder(ac.FolderID.ContentTracks) .. '/' .. ac.getTrackFullID('/') .. '/map.png'
  cmap = map; ui.decodeImage(map)
  ini = ac.getFolder(ac.FolderID.ContentTracks) .. "/" .. ac.getTrackFullID("/") .. "/data/map.ini"
  for a, b in ac.INIConfig.load(ini):serialize():gmatch("([_%a]+)=([-%d.]+)") do ms[a] = tonumber(b) end
  imsz = ui.imageSize(map)
  coff = vec2(ms.X_OFFSET, ms.Z_OFFSET)
end

---------------------------------------------------------------
-- Tabs + icons
---------------------------------------------------------------
local TABS = {
  { id = 1,  label = "Teleport" },
  { id = 2,  label = "Track Map" },
  { id = 3,  label = "Car Skins" },
  { id = 14, label = "Car Extras" },
  { id = 4,  label = "Assists" },
  { id = 5,  label = "Speed Boost" },
  { id = 6,  label = "Time of Day" },
  { id = 7,  label = "Weather" },
  { id = 9,  label = "Repair" },
  { id = 10, label = "Menu Color" },
  { id = 11, label = "Drift Meter" },
  { id = 12, label = "Performance" },
  { id = 13, label = "Discord Link" },
  { id = 16, label = "Replay Clip" },
  { id = 15, label = "Social Links" },
}

local function navIcon(id, x, y, s, c)
  local cx, cy = x + s * 0.5, y + s * 0.5
  if id == 1 then
    ui.drawCircle(vec2(cx, cy), s * 0.4, c, 16, 1.5)
    ui.drawCircleFilled(vec2(cx, cy), s * 0.12, c, 8)
  elseif id == 2 then
    ui.drawRect(vec2(x + s * 0.15, y + s * 0.22), vec2(x + s * 0.85, y + s * 0.78), c, 3, nil, 1.5)
    ui.drawLine(vec2(cx, y + s * 0.22), vec2(cx, y + s * 0.78), c, 1)
    ui.drawLine(vec2(x + s * 0.15, cy), vec2(x + s * 0.85, cy), c, 1)
  elseif id == 3 then
    ui.drawCircleFilled(vec2(cx, cy), s * 0.34, c, 16)
    ui.drawCircleFilled(vec2(cx - s * 0.12, cy - s * 0.1), s * 0.08, rgbm(1, 1, 1, 0.5), 8)
  elseif id == 4 then
    ui.drawCircle(vec2(cx, cy), s * 0.4, c, 18, 1.6)
    ui.drawCircle(vec2(cx, cy), s * 0.13, c, 10, 1.4)
    ui.drawLine(vec2(cx, y + s * 0.1), vec2(cx, y + s * 0.28), c, 1.6)
    ui.drawLine(vec2(x + s * 0.1, cy), vec2(x + s * 0.28, cy), c, 1.6)
    ui.drawLine(vec2(x + s * 0.9, cy), vec2(x + s * 0.72, cy), c, 1.6)
  elseif id == 5 then
    ui.drawTriangleFilled(vec2(cx - s * 0.06, y + s * 0.18), vec2(cx + s * 0.22, y + s * 0.46), vec2(cx - s * 0.02, y + s * 0.5), c)
    ui.drawTriangleFilled(vec2(cx + s * 0.06, y + s * 0.5), vec2(cx - s * 0.22, y + s * 0.82), vec2(cx + s * 0.02, y + s * 0.5), c)
  elseif id == 6 then
    ui.drawCircle(vec2(cx, cy), s * 0.42, c, 20, 1.6)
    ui.drawLine(vec2(cx, cy), vec2(cx, cy - s * 0.26), c, 1.6)
    ui.drawLine(vec2(cx, cy), vec2(cx + s * 0.20, cy + s * 0.04), c, 1.6)
  elseif id == 7 then
    ui.drawCircleFilled(vec2(cx - s * 0.18, cy + s * 0.06), s * 0.16, c, 12)
    ui.drawCircleFilled(vec2(cx + s * 0.16, cy + s * 0.06), s * 0.15, c, 12)
    ui.drawCircleFilled(vec2(cx, cy - s * 0.08), s * 0.19, c, 12)
    ui.drawRectFilled(vec2(cx - s * 0.3, cy + s * 0.02), vec2(cx + s * 0.3, cy + s * 0.24), c, 4)
  elseif id == 8 then
    ui.drawRectFilled(vec2(x + s * 0.12, cy - s * 0.02), vec2(x + s * 0.88, cy + s * 0.18), c, 3)
    ui.drawRectFilled(vec2(x + s * 0.28, cy - s * 0.22), vec2(x + s * 0.72, cy), c, 3)
    ui.drawCircleFilled(vec2(x + s * 0.3, cy + s * 0.2), s * 0.09, c, 10)
    ui.drawCircleFilled(vec2(x + s * 0.7, cy + s * 0.2), s * 0.09, c, 10)
  elseif id == 9 then
    ui.drawLine(vec2(x + s * 0.24, y + s * 0.78), vec2(x + s * 0.6, y + s * 0.42), c, 2.6)
    ui.drawCircle(vec2(x + s * 0.7, y + s * 0.3), s * 0.16, c, 14, 2.6)
  elseif id == 10 then
    ui.drawCircle(vec2(cx, cy), s * 0.4, c, 18, 1.5)
    ui.drawCircleFilled(vec2(cx - s * 0.14, cy - s * 0.1), s * 0.07, c, 8)
    ui.drawCircleFilled(vec2(cx + s * 0.14, cy - 0.08 * s), s * 0.07, c, 8)
    ui.drawCircleFilled(vec2(cx, cy + s * 0.16), s * 0.07, c, 8)
  elseif id == 11 then
    ui.drawRect(vec2(x + s * 0.3, y + s * 0.34), vec2(x + s * 0.74, y + s * 0.58), c, 3, nil, 1.6)
    ui.drawLine(vec2(x + s * 0.12, y + s * 0.72), vec2(x + s * 0.5, y + s * 0.72), c, 1.5)
    ui.drawLine(vec2(x + s * 0.18, y + s * 0.84), vec2(x + s * 0.58, y + s * 0.84), c, 1.5)
  elseif id == 12 then
    -- lightning bolt (performance)
    ui.drawLine(vec2(cx + s * 0.12, y + s * 0.14), vec2(cx - s * 0.14, cy + s * 0.02), c, 2.2)
    ui.drawLine(vec2(cx - s * 0.14, cy + s * 0.02), vec2(cx + s * 0.06, cy + s * 0.02), c, 2.2)
    ui.drawLine(vec2(cx + s * 0.06, cy + s * 0.02), vec2(cx - s * 0.12, y + s * 0.86), c, 2.2)
  elseif id == 13 then
    -- link / chain (discord)
    ui.drawCircle(vec2(cx - s * 0.11, cy - s * 0.11), s * 0.2, c, 16, 2)
    ui.drawCircle(vec2(cx + s * 0.11, cy + s * 0.11), s * 0.2, c, 16, 2)
  elseif id == 14 then
    -- extras (plus in a ring)
    ui.drawCircle(vec2(cx, cy), s * 0.4, c, 18, 1.4)
    ui.drawLine(vec2(cx, cy - s * 0.2), vec2(cx, cy + s * 0.2), c, 2)
    ui.drawLine(vec2(cx - s * 0.2, cy), vec2(cx + s * 0.2, cy), c, 2)
  elseif id == 15 then
    -- socials (share nodes)
    ui.drawCircleFilled(vec2(x + s * 0.28, cy), s * 0.1, c, 10)
    ui.drawCircleFilled(vec2(x + s * 0.72, y + s * 0.28), s * 0.1, c, 10)
    ui.drawCircleFilled(vec2(x + s * 0.72, y + s * 0.72), s * 0.1, c, 10)
    ui.drawLine(vec2(x + s * 0.32, cy - s * 0.03), vec2(x + s * 0.68, y + s * 0.3), c, 1.4)
    ui.drawLine(vec2(x + s * 0.32, cy + s * 0.03), vec2(x + s * 0.68, y + s * 0.7), c, 1.4)
  elseif id == 16 then
    -- clip / film (play button in a frame)
    ui.drawRect(vec2(x + s * 0.18, y + s * 0.24), vec2(x + s * 0.82, y + s * 0.76), c, 4, nil, 1.6)
    ui.drawTriangleFilled(vec2(cx - s * 0.08, cy - s * 0.13), vec2(cx - s * 0.08, cy + s * 0.13), vec2(cx + s * 0.14, cy), c)
  end
end

---------------------------------------------------------------
-- Tab content (region-based: X, Y, W, H)
---------------------------------------------------------------
local function drawTeleport(X, Y, W, H)
  sectionTitle("Teleport to Player", X, Y, W)
  local btnH = 34
  local btnY = Y + H - btnH
  local togH = 30
  local togY = btnY - 10 - togH
  local listY = Y + 34
  local listH = (togY - 10) - listY
  ui.setCursor(vec2(X, listY))
  ui.drawRectFilled(vec2(X, listY), vec2(X + W, listY + listH), rgbm(1, 1, 1, 0.03), 10)
  ui.childWindow("##plist", vec2(W, listH), function()
    local ww = ui.windowWidth() - 16   -- reserve room for the scrollbar so names don't overlap it
    local k = 0
    for i = 1, ac.getSim().carsCount - 1 do
      local c = ac.getCar(i)
      local n = ac.getDriverName(i)
      if (c.isConnected or c.isAIControlled) and n ~= "Hardbrain" then
        local ry = k * 40 + 4
        ui.setCursor(vec2(4, ry))
        local cl = ui.invisibleButton("##pl" .. i, vec2(ww - 14, 36))
        local hov = ui.itemHovered()
        local sel = selI == i
        if sel then
          ui.drawRectFilled(vec2(4, ry), vec2(ww - 10, ry + 36), rgbm(ACC.r, ACC.g, ACC.b, 0.16), 8)
          ui.drawRectFilled(vec2(ww - 13, ry + 8), vec2(ww - 10, ry + 28), ACC, 2)
        elseif hov then
          ui.drawRectFilled(vec2(4, ry), vec2(ww - 10, ry + 36), rgbm(1, 1, 1, 0.05), 8)
        end
        ui.drawRectFilled(vec2(10, ry + 9), vec2(56, ry + 27), rgbm(0, 0, 0, 0.35), 6)
        dwBox(tostring(math.floor(c.speedKmh or 0)), 11, 10, ry + 9, 46, 18, CY)
        dwRightBox(n, 13, 62, ry, ww - 74, 36, sel and CW or rgbm(0.82, 0.85, 0.9, 1))
        if cl then selI = i end
        k = k + 1
      end
    end
    if k == 0 then dwBox("No other players online", 12, 0, 14, ww, 20, CDm) end
    ui.dummy(vec2(1, k * 40 + 8))
  end)
  tpM = segToggle(X, togY, W, togH, { "Behind", "Same Speed" }, tpM)
  local can = selI >= 1 and tmr.r <= 0
  if bigButton(X, btnY, W, btnH, "Teleport", can and ACC or rgbm(0.28, 0.30, 0.36, 1), "##tpgo") and can then
    local c = ac.getCar(selI)
    if c and c.isConnected then
      if tpM == 2 then TPS(c) else TPB(c) end
      tmr.r = tmr.l
    end
  end
end

local function drawGrip(X, Y, W, H)
  sectionTitle("Traction & Assists", X, Y, W)
  ui.setCursor(vec2(X, Y + 32))
  ui.childWindow("##ctrlwin", vec2(W, H - 32), function()
    local ww = ui.windowWidth() - 20
    local yy = 2
    local function divider() ui.drawLine(vec2(0, yy), vec2(ww, yy), rgbm(1, 1, 1, 0.08), 1); yy = yy + 12 end
    local function subTitle(t) dwRightBox(t, 12, 0, yy, ww, 16, ACC); yy = yy + 22 end
    local function cell(bx, by, bw2, hgt, label, sub, on)
      ui.setCursor(vec2(bx, by))
      local cl = ui.invisibleButton("##c" .. label .. math.floor(by) .. math.floor(bx), vec2(bw2, hgt))
      local hov = ui.itemHovered()
      ui.drawRectFilled(vec2(bx, by), vec2(bx + bw2, by + hgt), on and rgbm(ACC.r, ACC.g, ACC.b, 0.85) or (hov and rgbm(1, 1, 1, 0.1) or rgbm(1, 1, 1, 0.05)), 8)
      if sub then
        dwBox(label, 13, bx, by + 4, bw2, 18, on and DK or CW)
        dwBox(sub, 10, bx, by + 23, bw2, 14, on and rgbm(0, 0, 0, 0.6) or CDm)
      else
        dwBox(label, 13, bx, by, bw2, hgt, on and DK or CW)
      end
      return cl
    end
    local a3 = (ww - 12) / 3

    subTitle("Traction (grip vs drift)")
    dwBox(grp >= 0.85 and "Grip" or (grp <= 0.25 and "Drift" or "Mixed"), 15, 0, yy - 22, 90, 18, CY)
    ui.setCursor(vec2(0, yy)); ui.setNextItemWidth(ww)
    local ng = ui.slider("##grp", grp, 0.0, 1.0, "")
    if math.abs(ng - grp) > 0.001 then grp = ng; applyGrip() end
    yy = yy + 30
    local g3 = (ww - 12) / 3
    if cell(0, yy, g3, 34, "Drift", nil, grp <= 0.25) then grp = 0.0; applyGrip() end
    if cell(g3 + 6, yy, g3, 34, "Mixed", nil, grp > 0.25 and grp < 0.85) then grp = 0.6; applyGrip() end
    if cell(2 * (g3 + 6), yy, g3, 34, "Grip", nil, grp >= 0.85) then grp = 1.0; applyGrip() end
    yy = yy + 40
    divider()

    subTitle("Driving Assists (local only)")
    if cell(0, yy, a3, 44, "TC", tcOn and "ON" or "OFF", tcOn) then tcOn = not tcOn; pcall(function() physics.setAssists({ tractionControl = tcOn and 'factory' or 'off' }) end) end
    if cell(a3 + 6, yy, a3, 44, "ABS", absOn and "ON" or "OFF", absOn) then absOn = not absOn; pcall(function() physics.setAssists({ abs = absOn and 'factory' or 'off' }) end) end
    if cell(2 * (a3 + 6), yy, a3, 44, "Auto Shift", autoShiftOn and "ON" or "OFF", autoShiftOn) then autoShiftOn = not autoShiftOn; pcall(function() physics.setCarAutoShifter(0, autoShiftOn) end) end
    yy = yy + 50

    local adj = false; pcall(function() adj = ac.isTurboWastegateAdjustable(0) end)
    if adj then
      divider()
      subTitle("Turbo Wastegate")
      dwBox(string.format("%d/10", math.floor(turboLvl + 0.5)), 14, 0, yy - 22, 60, 16, CY)
      ui.setCursor(vec2(0, yy)); ui.setNextItemWidth(ww)
      local nt = ui.slider("##turbo", turboLvl, 0, 10, "")
      if math.abs(nt - turboLvl) > 0.02 then turboLvl = nt; pcall(function() ac.setTurboWastegate(turboLvl / 10) end) end
      yy = yy + 34
    end
    divider()

    subTitle("Headlights")
    local h2 = (ww - 6) / 2
    if cell(0, yy, h2, 44, "Low Beam", headlightsOn and "ON" or "OFF", headlightsOn) then headlightsOn = not headlightsOn; pcall(function() ac.setHeadlights(headlightsOn) end) end
    if cell(h2 + 6, yy, h2, 44, "High Beam", highBeamsOn and "ON" or "OFF", highBeamsOn) then highBeamsOn = not highBeamsOn; pcall(function() ac.setHighBeams(highBeamsOn) end) end
    yy = yy + 50
    divider()

    subTitle("Turn Signals")
    local a4 = (ww - 18) / 4
    local function sig(idx, mode, kind)
      local bx = idx * (a4 + 6)
      ui.setCursor(vec2(bx, yy))
      local cl = ui.invisibleButton("##sig" .. mode, vec2(a4, 40))
      local on = selTurn == mode
      local hov = ui.itemHovered()
      local col = on and DK or CW
      ui.drawRectFilled(vec2(bx, yy), vec2(bx + a4, yy + 40), on and rgbm(ACC.r, ACC.g, ACC.b, 0.85) or (hov and rgbm(1, 1, 1, 0.1) or rgbm(1, 1, 1, 0.05)), 8)
      local cx, cy = bx + a4 * 0.5, yy + 20
      if kind == "left" then
        ui.drawTriangleFilled(vec2(cx - 10, cy), vec2(cx + 6, cy - 10), vec2(cx + 6, cy + 10), col)
      elseif kind == "right" then
        ui.drawTriangleFilled(vec2(cx + 10, cy), vec2(cx - 6, cy - 10), vec2(cx - 6, cy + 10), col)
      elseif kind == "haz" then
        ui.drawLine(vec2(cx, cy - 11), vec2(cx - 12, cy + 9), col, 2)
        ui.drawLine(vec2(cx, cy - 11), vec2(cx + 12, cy + 9), col, 2)
        ui.drawLine(vec2(cx - 12, cy + 9), vec2(cx + 12, cy + 9), col, 2)
        ui.drawLine(vec2(cx, cy - 3), vec2(cx, cy + 3), col, 2)
        ui.drawCircleFilled(vec2(cx, cy + 6), 1.5, col, 6)
      else
        dwBox("OFF", 13, bx, yy, a4, 40, col)
      end
      if cl then selTurn = mode; pcall(function() ac.setTurningLights(mode) end) end
    end
    sig(0, 1, "left")
    sig(1, 2, "right")
    sig(2, 3, "haz")
    sig(3, 0, "off")
    yy = yy + 46
    -- (car extras moved to their own dedicated "Car Extras" tab)

    ui.dummy(vec2(1, yy))
  end)
end

local function drawBoost(X, Y, W, H)
  local car = ac.getCar(0)
  local spd = car and math.floor(car.speedKmh) or 0
  local cardH = 78
  local R = 50
  local stackH = cardH + 28 + R * 2 + 34
  local sy = Y + math.max(0, (H - stackH) * 0.5)
  ui.drawRectFilled(vec2(X, sy), vec2(X + W, sy + cardH), rgbm(1, 1, 1, 0.05), 12)
  ui.drawRect(vec2(X, sy), vec2(X + W, sy + cardH), rgbm(ACC.r, ACC.g, ACC.b, 0.25), 12, nil, 1)
  dwBox("CURRENT SPEED", 10, X, sy + 8, W, 12, CDm)
  dwBox(tostring(spd), 38, X, sy + 20, W, 40, CC)
  dwBox("km/h", 10, X, sy + 58, W, 12, CDm)
  local pct = math.min(spd / BOOST_TARGET, 1)
  local by = sy + cardH - 8
  ui.drawRectFilled(vec2(X + 14, by), vec2(X + W - 14, by + 3), rgbm(0, 0, 0, 0.4), 2)
  if pct > 0 then ui.drawRectFilled(vec2(X + 14, by), vec2(X + 14 + (W - 28) * pct, by + 3), pct >= 1 and CGR or COR, 2) end
  local bcx = X + W * 0.5
  local bcy = sy + cardH + 28 + R
  ui.setCursor(vec2(bcx - R, bcy - R))
  local cl = ui.invisibleButton("##bst", vec2(R * 2, R * 2))
  local hov = ui.itemHovered()
  ui.drawCircle(vec2(bcx, bcy), R + 6, rgbm(1, 1, 1, 0.08), 52, 2)
  if boostTimer > 0 then
    ui.drawCircleFilled(vec2(bcx, bcy), R, rgbm(1, 1, 1, 0.06), 52)
    drawArcProgress(bcx, bcy, R + 6, 1 - boostTimer / BOOST_CD, CPU, 2.4)
    dwBox(string.format("%.1f", boostTimer), 28, bcx - R, bcy - 20, R * 2, 30, CW)
    dwBox("Cooldown", 11, bcx - R, bcy + 14, R * 2, 12, CDm)
  else
    local pulse = 0.88 + 0.12 * math.sin(pulseT * 4)
    for s = 4, 1, -1 do ui.drawCircleFilled(vec2(bcx, bcy), R + s * 3, rgbm(COR.r, COR.g, COR.b, 0.06 / s), 52) end
    local col = hov and rgbm(1, 0.72, 0.24, 1) or rgbm(COR.r * pulse, COR.g * pulse, COR.b * pulse, 1)
    ui.drawCircleFilled(vec2(bcx, bcy), R, col, 52)
    ui.drawCircle(vec2(bcx, bcy), R, rgbm(1, 1, 1, 0.28), 52, 2)
    dwBox("BOOST", 16, bcx - R, bcy - 8, R * 2, 18, DK)
    if cl then doBoost() end
  end
  dwBox(string.format("Target %d km/h  -  press B", BOOST_TARGET), 12, X, bcy + R + 14, W, 16, CC)
end

local function drawSkin(X, Y, W, H)
  sectionTitle("Car Skins", X, Y, W)
  local byH = 30
  local byY = Y + H - byH
  local gridY = Y + 34
  local gridH = (byY - 8) - gridY
  ui.setCursor(vec2(X, gridY))
  ui.childWindow("##skg", vec2(W, gridH), function()
    local ww = ui.windowWidth() - 14
    if #_carSkins == 0 then dwBox("No skins found", 13, 0, 14, ww, 20, CY); return end
    local cols = 2
    local cw = (ww - 8 - (cols - 1) * 6) / cols
    local ch = cw * 0.5
    for i, skin in ipairs(_carSkins) do
      local col = (i - 1) % cols
      local row = math.floor((i - 1) / cols)
      local cx = 3 + col * (cw + 6)
      local cyy = row * (ch + 20)
      local sel = _currentSkin == skin.name
      ui.setCursor(vec2(cx, cyy))
      local cl = ui.invisibleButton("##sk" .. i, vec2(cw, ch + 16))
      local hov = ui.itemHovered()
      local pp = _carDir .. '/skins/' .. skin.name .. '/preview.jpg'
      if ui.isImageReady(pp) then
        ui.setCursor(vec2(cx, cyy)); ui.image(pp, vec2(cw, ch))
      else
        ui.decodeImage(pp)
        ui.drawRectFilled(vec2(cx, cyy), vec2(cx + cw, cyy + ch), rgbm(1, 1, 1, 0.05), 8)
        dwBox("...", 12, cx, cyy, cw, ch, CDm)
      end
      if sel then ui.drawRect(vec2(cx, cyy), vec2(cx + cw, cyy + ch), ACC, 8, nil, 2.5)
      elseif hov then ui.drawRect(vec2(cx, cyy), vec2(cx + cw, cyy + ch), rgbm(1, 1, 1, 0.4), 8, nil, 1.5)
      else ui.drawRect(vec2(cx, cyy), vec2(cx + cw, cyy + ch), rgbm(1, 1, 1, 0.12), 8, nil, 1) end
      dwBox(skin.name, 9, cx, cyy + ch + 1, cw, 14, sel and ACC or CDm)
      if cl and skin.name ~= _currentSkin then
        doApplySkin(skin.name, 0)
        pcall(function() _syncSkin({ skin = skin.name, oldSkin = _currentSkin }, true) end)
        _currentSkin = skin.name
      end
    end
    ui.dummy(vec2(1, math.ceil(#_carSkins / 2) * (ch + 20) + 4))
  end)
  local bw = (W - 8) / 2
  if bigButton(X, byY, bw, byH, "Default Skin", rgbm(0.28, 0.30, 0.34, 1), "##skdef") then
    doApplySkin(_originalSkin, 0)
    pcall(function() _syncSkin({ skin = _originalSkin, oldSkin = _currentSkin }, true) end)
    _currentSkin = _originalSkin
  end
  if bigButton(X + bw + 8, byY, bw, byH, "Random Skin", ACC, "##skrnd") then
    local r = _carSkins[math.random(#_carSkins)]
    if r then
      doApplySkin(r.name, 0)
      pcall(function() _syncSkin({ skin = r.name, oldSkin = _currentSkin }, true) end)
      _currentSkin = r.name
    end
  end
end

local function drawMap(X, Y, W, H)
  sectionTitle("Track Map", X, Y, W)
  dwRightBox("Double-click map to teleport - scroll to zoom - green = you, red = others", 10, X, Y + 24, W - 40, 12, CDm)
  local mY = Y + 40
  local mH = H - 40
  ui.setCursor(vec2(X, mY))
  ui.childWindow("##mapc", vec2(W, mH), function()
    if ac.getPatchVersionCode() < 2000 then dwBox("CSP 2000+", 14, 0, 10, ui.windowWidth(), 20, CR); return end
    if f1 then
      msc = math.min((ui.windowWidth() - pad.x) / imsz.x, (ui.windowHeight() - pad.y) / imsz.y)
      csc = msc / ms.SCALE_FACTOR; sz = imsz * msc
      if ui.isImageReady(cmap) then f1 = false end
    end
    ui.drawImage(cmap, -ofs, -ofs + sz)
    if ui.windowHovered() and ac.getUI().mouseWheel ~= 0 then
      local w = ac.getUI().mouseWheel
      if (w < 0 and sz.x + pad.x > ui.windowWidth() and sz.y + pad.y > ui.windowHeight()) or w > 0 then
        local old = sz; msc = msc * (1 + w * 0.15)
        sz = imsz * msc; csc = msc / ms.SCALE_FACTOR
        ofs = ofs + (sz - old) * (ofs + ui.mouseLocalPos()) / old
      else
        ofs = -pad * 0.5
        msc = math.min((ui.windowWidth() - pad.x) / imsz.x, (ui.windowHeight() - pad.y) / imsz.y)
        sz = imsz * msc; csc = msc / ms.SCALE_FACTOR
      end
    end
    for i = ac.getSim().carsCount - 1, 1, -1 do
      local c = ac.getCar(i)
      if c.isConnected and not c.isHidingLabels then
        p2:set(c.position.x, c.position.z):add(coff):scale(csc):add(-ofs)
        d2:set(c.look.x, c.look.z); dx2:set(c.look.z, -c.look.x)
        ui.drawTriangleFilled(p2 + d2 * tts, p2 - d2 * tts - dx2 * tts * 0.75, p2 - d2 * tts + dx2 * tts * 0.75, rgbm(255, 0, 0, 255))
      end
    end
    p3 = ac.getCameraPosition()
    p2:set(p3.x, p3.z):add(coff):scale(csc):add(-ofs)
    d3 = ac.getCameraForward(); d2 = vec2(d3.x, d3.z):normalize(); dx2:set(d3.z, -d3.x):normalize()
    local sc = ghostOn and rgbm(0, 255, 255, 255) or rgbm(0, 255, 0, 255)
    ui.drawTriangleFilled(p2 + d2 * tts, p2 - d2 * tts - dx2 * tts * 0.75, p2 - d2 * tts + dx2 * tts * 0.75, sc)
    if ui.mouseDoubleClicked(ui.MouseButton.Left) and ui.windowHovered() and tmr.r <= 0 then
      local cp = (ui.mouseLocalPos() + ofs) / csc - coff
      placeCarOnGround(cp.x, cp.y, ac.getCameraForward(), 0.8)
      ghostStart(); tmr.r = tmr.l
    end
    ui.invisibleButton('###md', ui.windowSize())
    if ui.mouseDown() and ui.itemHovered() then ofs = ofs - ui.mouseDelta() end
  end)
end

local function drawTime(X, Y, W, H)
  local stackH = 40 + 60 + 40 + 46 + 36
  local sy = Y + math.max(0, (H - stackH) * 0.5)
  sectionTitle("Personal Time", X, sy, W); sy = sy + 40
  local hh = math.floor(uSt.timeHour) % 24
  local mm = math.floor((uSt.timeHour % 1) * 60)
  dwBox(string.format("%02d:%02d", hh, mm), 46, X, sy, W, 52, uSt.timeSynced and CDm or CC); sy = sy + 60
  ui.setCursor(vec2(X, sy)); ui.setNextItemWidth(W)
  local nt = ui.slider("##tmsl", uSt.timeHour, 0, 24, "")
  if math.abs(nt - uSt.timeHour) > 0.001 then
    uSt.timeHour = nt
    uSt.timePending = true
    uSt.timeSynced = false
    fxBridge.hb_timeHour = uSt.timeHour
    fxBridge.hb_timeSync = 0
    bumpFx()
    if _G.Hardbrain_applyTime then pcall(_G.Hardbrain_applyTime, uSt.timeHour) end
  end
  if uSt.timePending and not ui.itemActive() then sendTime(); uSt.timePending = false end
  sy = sy + 40
  local presets = { { "Dawn", 1.0 }, { "Morning", 6.5 }, { "Noon", 13.0 }, { "Dusk", 18.5 } }
  local bw = (W - 18) / 4
  for i = 1, 4 do
    local bx = X + (i - 1) * (bw + 6)
    ui.setCursor(vec2(bx, sy))
    local cl = ui.invisibleButton("##tp" .. i, vec2(bw, 34))
    local hov = ui.itemHovered()
    ui.drawRectFilled(vec2(bx, sy), vec2(bx + bw, sy + 34), hov and rgbm(1, 1, 1, 0.12) or rgbm(1, 1, 1, 0.05), 8)
    dwBox(presets[i][1], 13, bx, sy, bw, 34, CW)
    if cl then uSt.timeHour = presets[i][2]; sendTime() end
  end
  sy = sy + 46
  if bigButton(X, sy, W, 36, "Sync Server Time", uSt.timeSynced and rgbm(0.28, 0.30, 0.36, 1) or ACC, "##tsync") then
    syncTime()
  end
end

local function drawWeather(X, Y, W, H)
  sectionTitle("Personal Weather", X, Y, W)
  local byH = 34
  local byY = Y + H - byH
  local listY = Y + 34
  local listH = (byY - 10) - listY
  ui.setCursor(vec2(X, listY))
  ui.drawRectFilled(vec2(X, listY), vec2(X + W, listY + listH), rgbm(1, 1, 1, 0.03), 10)
  ui.childWindow("##wlist", vec2(W, listH), function()
    local ww = ui.windowWidth() - 14  -- leave room for the scrollbar so text/markers don't overlap it
    for i, w in ipairs(WEATHERS) do
      local ry = (i - 1) * 38 + 3
      ui.setCursor(vec2(3, ry))
      local cl = ui.invisibleButton("##w" .. w.id, vec2(ww - 12, 34))
      local hov = ui.itemHovered()
      local sel = uSt.selWeather == w.id
      if sel then
        ui.drawRectFilled(vec2(3, ry), vec2(ww - 9, ry + 34), rgbm(ACC.r, ACC.g, ACC.b, 0.16), 8)
        ui.drawRectFilled(vec2(ww - 12, ry + 7), vec2(ww - 9, ry + 27), ACC, 2)
      elseif hov then
        ui.drawRectFilled(vec2(3, ry), vec2(ww - 9, ry + 34), rgbm(1, 1, 1, 0.05), 8)
      end
      dwRightBox(w.name, 14, 10, ry, ww - 20, 34, sel and CW or rgbm(0.82, 0.85, 0.9, 1))
      if cl then sendWeather(w.id) end
    end
    ui.dummy(vec2(1, #WEATHERS * 38 + 6))
  end)
  if bigButton(X, byY, W, byH, "Sync Server Weather", uSt.selWeather < 0 and rgbm(0.28, 0.30, 0.36, 1) or ACC, "##wsync") then
    syncWeather()
  end
end

local function drawRepair(X, Y, W, H)
  sectionTitle("Instant Repair", X, Y, W)
  local R = 58
  local bcx = X + W * 0.5
  local bcy = Y + H * 0.5
  ui.setCursor(vec2(bcx - R, bcy - R))
  local cl = ui.invisibleButton("##repair", vec2(R * 2, R * 2))
  local hov = ui.itemHovered()
  local recent = (pulseT - repairAt) < 2
  for s = 4, 1, -1 do ui.drawCircleFilled(vec2(bcx, bcy), R + s * 3, rgbm(CGR.r, CGR.g, CGR.b, 0.06 / s), 48) end
  local col = recent and rgbm(0.35, 0.95, 0.6, 1) or (hov and rgbm(0.3, 0.88, 0.55, 1) or rgbm(0.22, 0.75, 0.45, 1))
  ui.drawCircleFilled(vec2(bcx, bcy), R, col, 48)
  ui.drawCircle(vec2(bcx, bcy), R, rgbm(1, 1, 1, 0.3), 48, 2)
  ui.drawLine(vec2(bcx - 16, bcy - 2), vec2(bcx + 6, bcy - 24), DK, 5)
  ui.drawCircle(vec2(bcx + 12, bcy - 30), 8, DK, 14, 5)
  dwBox("REPAIR", 15, bcx - R, bcy + 14, R * 2, 20, DK)
  if cl then repairCar() end
  if recent then
    dwBox("Car repaired successfully", 15, X, bcy + R + 22, W, 22, CGR)
  else
    dwBox("Repair (press V) cooldown - wait before using again", 11, X, bcy + R + 22, W, 18, CDm)
  end
end

local function drawColor(X, Y, W, H)
  sectionTitle("Accent Color", X, Y, W)
  local y = Y + 40
  local cols = 4
  local sw = (W - (cols - 1) * 10) / cols
  local sh = 46
  for i, p in ipairs(PALETTE) do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local cx = X + col * (sw + 10)
    local cy = y + row * (sh + 26)
    ui.setCursor(vec2(cx, cy))
    local cl = ui.invisibleButton("##pal" .. i, vec2(sw, sh))
    local hov = ui.itemHovered()
    ui.drawRectFilled(vec2(cx, cy), vec2(cx + sw, cy + sh), p.c, 10)
    if stor.accentIdx == i then
      ui.drawRect(vec2(cx - 2, cy - 2), vec2(cx + sw + 2, cy + sh + 2), CW, 12, nil, 2.5)
    elseif hov then
      ui.drawRect(vec2(cx, cy), vec2(cx + sw, cy + sh), rgbm(1, 1, 1, 0.5), 10, nil, 1.5)
    end
    dwBox(p.name, 12, cx, cy + sh + 2, sw, 16, stor.accentIdx == i and CW or CDm)
    if cl then stor.accentIdx = i; ACC = p.c end
  end
  -- menu transparency (separate from the chat's)
  local sy = y + 2 * (sh + 26) + 6
  dwRightBox(string.format("Menu opacity (%d%%)", math.floor(stor.menuOpacity * 100 + 0.5)), 13, X, sy, W, 18, CW)
  ui.setCursor(vec2(X, sy + 24))
  ui.setNextItemWidth(W)
  stor.menuOpacity = ui.slider("##menuopac", stor.menuOpacity, 0.35, 1.0, "%.2f")
  dwBox("Saved locally on your PC", 11, X, Y + H - 22, W, 16, CDm)
end

local function drawPerf(X, Y, W, H)
  sectionTitle("Performance Mode", X, Y, W)
  local y = Y + 40
  ui.setCursor(vec2(X, y))
  local cl = ui.invisibleButton("##perftgl", vec2(W, 60))
  local on = stor.perfMode
  ui.drawRectFilled(vec2(X, y), vec2(X + W, y + 60), on and rgbm(0.16, 0.62, 0.40, 0.92) or rgbm(1, 1, 1, 0.06), 12)
  dwRightBox(on and "Performance ON - tap to disable" or "Performance OFF - tap to enable", 18, X + 16, y + 9, W - 32, 24, on and DK or CW)
  dwRightBox(on and "Performance ON - disables heavy UI effects" or "Performance OFF - full UI effects enabled for best visuals", 12, X + 16, y + 34, W - 32, 16, on and rgbm(0, 0, 0, 0.6) or CDm)
  if cl then stor.perfMode = not stor.perfMode; applyPerfMode(stor.perfMode) end
  local ly = y + 78
  local items = {
    "Disables menu blur and heavy shadows",
    "Reduces chat animation and particle effects",
    "Turns off drift meter overlay + ghost trail",
    "Lowers map refresh rate for more stable FPS",
  }
  for i, t in ipairs(items) do
    local iy = ly + (i - 1) * 30
    ui.drawCircleFilled(vec2(X + W - 6, iy + 11), 3, on and CGR or CDm, 8)
    dwRightBox(t, 13, X, iy, W - 18, 22, on and CW or CDm)
  end
  dwBox("Tip: enable if your FPS drops in crowded sessions", 11, X, Y + H - 40, W, 16, CGR)
  dwBox("Settings are saved locally on your PC", 10, X, Y + H - 22, W, 14, CDm)
end

local function drawDrift(X, Y, W, H)
  sectionTitle("Drift Scoring", X, Y, W)
  local y = Y + 40
  ui.setCursor(vec2(X, y))
  local cl = ui.invisibleButton("##drifttgl", vec2(W, 52))
  local on = stor.driftEnabled
  ui.drawRectFilled(vec2(X, y), vec2(X + W, y + 52), on and rgbm(ACC.r, ACC.g, ACC.b, 0.85) or rgbm(1, 1, 1, 0.06), 10)
  dwRightBox(on and "Drift meter ON" or "Drift meter OFF", 16, X + 14, y + 6, W - 28, 22, on and DK or CW)
  dwRightBox(on and "Drift scoring active" or "Drift meter hidden - toggle to show live score overlay", 11, X + 14, y + 28, W - 28, 16, on and rgbm(0, 0, 0, 0.6) or CDm)
  if cl then stor.driftEnabled = not stor.driftEnabled end
  y = y + 68
  local hw = (W - 12) * 0.5
  ui.drawRectFilled(vec2(X, y), vec2(X + hw, y + 60), rgbm(1, 1, 1, 0.04), 10)
  dwBox("Session Score", 11, X, y + 8, hw, 14, CDm)
  dwBox(tostring(driftTotal), 26, X, y + 22, hw, 30, CY)
  ui.drawRectFilled(vec2(X + hw + 12, y), vec2(X + W, y + 60), rgbm(1, 1, 1, 0.04), 10)
  dwBox("Best Run", 11, X + hw + 12, y + 8, hw, 14, CDm)
  dwBox(tostring(driftBest), 26, X + hw + 12, y + 22, hw, 30, CGR)
  y = y + 74
  dwRightBox(string.format("Total spins (full 360): %d", driftSessionSpins), 13, X, y, W, 18, CY)
  y = y + 24
  dwRightBox("Angle + speed = drift points (x1 to x5) - clean 360 spin = +500", 11, X, y, W, 16, CDm)
  if bigButton(X, Y + H - 38, W, 34, "Reset Scores", rgbm(0.28, 0.30, 0.36, 1), "##driftreset") then
    driftTotal = 0; driftBest = 0; driftSessionSpins = 0
  end
end

local function drawLink(X, Y, W, H)
  sectionTitle("Discord Account Link", X, Y, W)
  local y = Y + 42
  dwRightBox("Link your Discord to unlock role colors and tags in chat on all Hardbrain servers.", 13, X, y, W, 40, rgbm(0.82, 0.86, 0.92, 1))
  y = y + 48
  if bigButton(X, y, W, 34, "Open Discord Link Room", rgbm(0.35, 0.40, 0.95, 1), "##openlinkroom") then
    pcall(function() os.openURL("https://discord.com/channels/654214921751625738/1492590912608534879") end)
  end
  y = y + 44
  if linkCode then
    local kh = 176
    ui.drawRectFilled(vec2(X, y), vec2(X + W, y + kh), rgbm(CC.r, CC.g, CC.b, 0.12), 12)
    ui.drawRect(vec2(X, y), vec2(X + W, y + kh), CC, 12, nil, 1.5)
    dwBox("Your Link Code", 13, X, y + 12, W, 18, CC)
    dwBox(linkCode, 32, X, y + 32, W, 40, CW)
    dwRightBox("Your code:", 13, X + 14, y + 80, W - 28, 18, CY)
    dwRightBox("1) Join the Hardbrain Discord server", 12, X + 14, y + 102, W - 28, 18, rgbm(0.82, 0.86, 0.92, 1))
    dwRightBox("2) In the link channel, type:", 12, X + 14, y + 122, W - 28, 18, rgbm(0.82, 0.86, 0.92, 1))
    dwBox("/link " .. linkCode, 19, X, y + 142, W, 24, CY)
    y = y + kh + 12
  elseif isLinked then
    local kh = 72
    ui.drawRectFilled(vec2(X, y), vec2(X + W, y + kh), rgbm(0.16, 0.5, 0.3, 0.22), 12)
    ui.drawRect(vec2(X, y), vec2(X + W, y + kh), CGR, 12, nil, 1.5)
    dwBox("Discord linked successfully", 16, X, y + 14, W, 22, CGR)
    dwBox("Your Discord roles now show in chat", 11, X, y + 42, W, 16, CDm)
    y = y + kh + 12
  else
    local kh = 100
    ui.drawRectFilled(vec2(X, y), vec2(X + W, y + kh), rgbm(1, 1, 1, 0.05), 12)
    dwRightBox("Join Hardbrain Discord and use /link with the code below to unlock role colors in chat.", 12, X + 12, y + 12, W - 24, 42, rgbm(0.82, 0.86, 0.92, 1))
    if bigButton(X + 12, y + kh - 46, W - 24, 36, "Get Link Code", ACC, "##getcode") then
      pcall(function() ac.sendChatMessage("$AS1980_GETCODE") end)
    end
    y = y + kh + 12
  end
  dwBox("Hardbrain Discord:  discord.gg/hardbrain", 12, X, Y + H - 24, W, 16, CC)
end

-- car extras (EXTRA_A..) ... detected live per car; index 0 = extraA, 1 = extraB, ...
local EXTRA_FIELDS = { "extraA", "extraB", "extraC", "extraD", "extraE", "extraF", "extraG", "extraH", "extraI", "extraJ", "extraK", "extraL", "extraM", "extraN", "extraO", "extraP", "extraQ", "extraR", "extraS", "extraT" }
local extraDesired = {}  -- index -> bool: the player's chosen state, re-applied so extras survive repair/rewind/teleport
local function drawExtras(X, Y, W, H)
  sectionTitle("Car Extras", X, Y, W)
  local y = Y + 40
  local avail = {}
  for i = 0, 19 do
    local ok, a = pcall(function() return ac.isExtraSwitchAvailable(i, false) end)
    if ok and a then avail[#avail + 1] = i end
  end
  if #avail == 0 then
    ui.drawRectFilled(vec2(X, y + 20), vec2(X + W, y + 92), rgbm(1, 1, 1, 0.04), 10)
    dwBox("This car has no configurable extras", 14, X, y + 34, W, 22, CW)
    dwBox("This car has no configurable extras (some mods add extras in the data folder)", 11, X, y + 60, W, 16, CDm)
    return
  end
  dwRightBox(string.format("Extras available on this car: %d - tap ON/OFF to toggle", #avail), 12, X, y, W, 18, CY)
  y = y + 24
  -- keep-extras toggle: re-applies your choice so extras don't reset on repair/rewind/teleport
  ui.setCursor(vec2(X, y))
  local kcl = ui.invisibleButton("##extrakeep", vec2(W, 34))
  local kon = stor.extraKeep
  ui.drawRectFilled(vec2(X, y), vec2(X + W, y + 34), kon and rgbm(0.16, 0.5, 0.3, 0.55) or rgbm(1, 1, 1, 0.06), 8)
  dwRightBox(kon and "Keep extras ON after repair/teleport/rewind" or "Extras reset with repair (toggle to keep)", 12, X + 12, y + 8, W - 24, 18, kon and CW or CDm)
  if kcl then stor.extraKeep = not stor.extraKeep end
  y = y + 42
  local car = nil
  pcall(function() car = ac.getCar(ac.getSim().focusedCar) end)
  ui.setCursor(vec2(X, y))
  ui.childWindow("##extraslist", vec2(W, Y + H - y - 6), function()
    local cw = ui.windowWidth()
    local rowH = 44
    for idx, i in ipairs(avail) do
      local ry = (idx - 1) * (rowH + 6)
      local on = extraDesired[i]
      if on == nil and car then pcall(function() on = car[EXTRA_FIELDS[i + 1]] and true or false end) end
      on = on or false
      local nm = nil
      pcall(function() nm = ac.getExtraSwitchName(i) end)
      if not nm or nm == "" then nm = "Extra " .. tostring(i + 1) end
      ui.setCursor(vec2(0, ry))
      local cl = ui.invisibleButton("##extra" .. i, vec2(cw, rowH))
      ui.drawRectFilled(vec2(0, ry), vec2(cw, ry + rowH), on and rgbm(ACC.r, ACC.g, ACC.b, 0.85) or rgbm(1, 1, 1, 0.06), 10)
      dwRightBox(nm, 15, 14, ry + 4, cw - 100, rowH - 8, on and DK or CW)
      local px = cw - 82
      ui.drawRectFilled(vec2(px, ry + 11), vec2(px + 64, ry + rowH - 11), on and rgbm(0.1, 0.5, 0.3, 1) or rgbm(1, 1, 1, 0.1), 20)
      dwBox(on and "ON" or "OFF", 11, px, ry + 11, 64, rowH - 22, on and CW or CDm)
      if cl then extraDesired[i] = not on; pcall(function() ac.setExtraSwitch(i, extraDesired[i]) end) end
    end
    ui.setCursor(vec2(0, #avail * 50 + 4)); ui.dummy(vec2(1, 1))
  end)
end

local SOCIALS = {
  { name = "Hardbrain Discord", handle = "discord.gg/hardbrain", url = "https://discord.gg/hardbrain", col = rgbm(0.35, 0.40, 0.95, 1) },
  { name = "Hardbrain Panel", handle = "cp.hardbrain.store", url = "https://cp.hardbrain.store/", col = rgbm(0.95, 0.75, 0.20, 1) },
  { name = "Hardbrain Racing", handle = "hardbrain.store", url = "https://hardbrain.store/", col = rgbm(0.20, 0.84, 0.50, 1) },
}
local function drawSocials(X, Y, W, H)
  sectionTitle("Social Links", X, Y, W)
  local y = Y + 40
  dwRightBox("Tap a row to open the link in your browser", 12, X, y, W, 18, CDm)
  y = y + 26
  local rowH = 46
  for i, s in ipairs(SOCIALS) do
    local ry = y + (i - 1) * (rowH + 6)
    ui.setCursor(vec2(X, ry))
    local cl = ui.invisibleButton("##soc" .. i, vec2(W, rowH))
    local hov = ui.itemHovered()
    ui.drawRectFilled(vec2(X, ry), vec2(X + W, ry + rowH), hov and rgbm(s.col.r, s.col.g, s.col.b, 0.92) or rgbm(1, 1, 1, 0.06), 10)
    ui.drawRectFilled(vec2(X, ry), vec2(X + 6, ry + rowH), s.col, 10)
    dwRightBox(s.name, 15, X + 16, ry + 5, W - 30, 20, CW)
    dwRightBox(s.handle, 12, X + 16, ry + 26, W - 30, 16, hov and rgbm(1, 1, 1, 0.85) or CDm)
    if cl then pcall(function() os.openURL(s.url) end) end
  end
end

local function drawReplay(X, Y, W, H)
  sectionTitle("Replay Evidence", X, Y, W)
  local y = Y + 42
  dwRightBox("Save replay clips as evidence when reporting - required for staff to act", 13, X, y, W, 20, rgbm(0.82, 0.86, 0.92, 1))
  y = y + 30
  ui.drawRectFilled(vec2(X, y), vec2(X + W, y + 168), rgbm(CC.r, CC.g, CC.b, 0.10), 12)
  ui.drawRect(vec2(X, y), vec2(X + W, y + 168), CC, 12, nil, 1.2)
  dwRightBox("1) Save a replay clip in Content Manager:", 13, X + 14, y + 12, W - 28, 18, CY)
  dwBox("Ctrl + Shift + S", 18, X, y + 34, W, 26, CW)
  dwRightBox("2) Clips are saved to this folder:", 13, X + 14, y + 68, W - 28, 18, CY)
  dwBox("Documents / Assetto Corsa / replay / clips", 12, X, y + 90, W, 20, rgbm(0.82, 0.86, 0.92, 1))
  dwRightBox("2) Clips save to Documents/Assetto Corsa/replay/clips", 13, X + 14, y + 120, W - 28, 18, CY)
  dwRightBox("3) Attach the clip when reporting on Discord", 12, X + 14, y + 144, W - 28, 18, CGR)
  y = y + 180
  dwRightBox("Tip: bind Ctrl+Shift+S in Content Manager settings for quick capture", 12, X, y, W, 18, CDm)
  y = y + 22
  dwRightBox("Or enable replay clip hotkey in CSP (Miscellaneous)", 12, X, y, W, 18, CDm)
end

---------------------------------------------------------------
-- Menu shell (invoice style): header + right rail + content + footer
---------------------------------------------------------------
local function keycap(i, letter, label)
  local x = 14 + (i - 1) * 88
  ui.drawRectFilled(vec2(x, 15), vec2(x + 24, 39), rgbm(0.13, 0.11, 0.18, 1), 7)
  ui.drawRect(vec2(x, 15), vec2(x + 24, 39), rgbm(1, 1, 1, 0.14), 7, nil, 1)
  dwBox(letter, 13, x, 15, 24, 24, CW)
  dwLeftBox(label, 12, x + 28, 15, 56, 24, CDm)
end

local function drawMenu()
  local W, H = PANEL_W, PANEL_H
  ui.drawRectFilled(vec2(0, 0), vec2(W, H), rgbm(0.07, 0.08, 0.11, stor.menuOpacity), 16)
  ui.drawRectFilled(vec2(0, 0), vec2(W, 54), rgbm(1, 1, 1, 0.02), 16)
  ui.drawRect(vec2(0.5, 0.5), vec2(W - 0.5, H - 0.5), rgbm(ACC.r, ACC.g, ACC.b, 0.5), 16, nil, 1.4)
  ui.drawLine(vec2(0, 54), vec2(W, 54), rgbm(1, 1, 1, 0.06), 1)

  -- Header: keycaps (left) + brand (right)
  keycap(1, "M", "Menu")
  keycap(2, "N", "Travel")
  keycap(3, "B", "Boost")
  keycap(4, "V", "Repair")
  dwRightBox("Hardbrain", 21, W - 168, 8, 140, 24, CW)
  ui.drawCircleFilled(vec2(W - 20, 20), 4, ACC, 10)
  dwRightBox("Racing Hub", 11, W - 168, 32, 140, 14, ACC)

  -- Right rail
  ui.drawLine(vec2(W - NAV, 58), vec2(W - NAV, H - 38), rgbm(1, 1, 1, 0.07), 1)
  local itemH = 26
  local ny0 = 66
  for i, tab in ipairs(TABS) do
    local iy = ny0 + (i - 1) * (itemH + 3)
    local rx = W - NAV + 8
    local rw = NAV - 16
    ui.setCursor(vec2(rx, iy))
    local cl = ui.invisibleButton("##nv" .. tab.id, vec2(rw, itemH))
    local hov = ui.itemHovered()
    local sel = activeTab == tab.id
    if sel then
      ui.drawRectFilled(vec2(rx, iy), vec2(rx + rw, iy + itemH), rgbm(ACC.r, ACC.g, ACC.b, 0.16), 10)
      ui.drawRectFilled(vec2(rx + rw - 3, iy + 7), vec2(rx + rw, iy + itemH - 7), ACC, 2)
    elseif hov then
      ui.drawRectFilled(vec2(rx, iy), vec2(rx + rw, iy + itemH), rgbm(1, 1, 1, 0.05), 10)
    end
    navIcon(tab.id, rx + rw - 27, iy + (itemH - 20) * 0.5, 20, sel and ACC or CDm)
    dwRightBox(tab.label, 13, rx, iy, rw - 32, itemH, sel and CW or CDm)
    if cl then activeTab = tab.id end
  end

  -- report button (shows 30s after joining), just under the tab list
  if pulseT > 30 then
    local ry = ny0 + #TABS * (itemH + 3) + 6
    ui.setCursor(vec2(W - NAV + 8, ry))
    local rcl = ui.invisibleButton("##reportbtn", vec2(NAV - 16, 30))
    local rhov = ui.itemHovered()
    ui.drawRectFilled(vec2(W - NAV + 8, ry), vec2(W - 8, ry + 30), rhov and rgbm(0.9, 0.24, 0.26, 0.95) or rgbm(0.85, 0.22, 0.24, 0.42), 8)
    dwRightBox("Report", 13, W - NAV + 8, ry, NAV - 20, 30, CW)
    if rcl then reportOpen = true; menuOpen = false end
  end

  -- Footer
  ui.drawLine(vec2(0, H - 34), vec2(W, H - 34), rgbm(1, 1, 1, 0.06), 1)
  dwLeftBox("Press M - Menu", 11, 16, H - 30, 220, 14, rgbm(0.5, 0.47, 0.58, 1))
  dwRightBox("cp.hardbrain.store", 9, W - 128, H - 30, 112, 14, CDm)

  -- Content area (left of rail)
  local CX = 16
  local CY0 = 66
  local rightEdge = (W - NAV) - 12
  local CWid = rightEdge - CX
  if ghostOn then
    ui.drawRectFilled(vec2(CX, CY0), vec2(CX + CWid, CY0 + 20), rgbm(ACC.r, ACC.g, ACC.b, 0.12), 7)
    dwBox(string.format("Ghost  %.1fs", ghostT), 11, CX, CY0, CWid, 20, CC)
    CY0 = CY0 + 24
  end
  if tmr.r > 0 then
    ui.drawRectFilled(vec2(CX, CY0), vec2(CX + CWid, CY0 + 20), rgbm(CY.r, CY.g, CY.b, 0.12), 7)
    dwBox(string.format("Teleport CD  %.1fs", tmr.r), 11, CX, CY0, CWid, 20, CY)
    CY0 = CY0 + 24
  end
  local CHt = (H - 38) - CY0 - 6

  if activeTab == 1 then drawTeleport(CX, CY0, CWid, CHt)
  elseif activeTab == 2 then drawMap(CX, CY0, CWid, CHt)
  elseif activeTab == 3 then drawSkin(CX, CY0, CWid, CHt)
  elseif activeTab == 4 then drawGrip(CX, CY0, CWid, CHt)
  elseif activeTab == 5 then drawBoost(CX, CY0, CWid, CHt)
  elseif activeTab == 6 then drawTime(CX, CY0, CWid, CHt)
  elseif activeTab == 7 then drawWeather(CX, CY0, CWid, CHt)
  elseif activeTab == 9 then drawRepair(CX, CY0, CWid, CHt)
  elseif activeTab == 10 then drawColor(CX, CY0, CWid, CHt)
  elseif activeTab == 11 then drawDrift(CX, CY0, CWid, CHt)
  elseif activeTab == 12 then drawPerf(CX, CY0, CWid, CHt)
  elseif activeTab == 13 then drawLink(CX, CY0, CWid, CHt)
  elseif activeTab == 14 then drawExtras(CX, CY0, CWid, CHt)
  elseif activeTab == 15 then drawSocials(CX, CY0, CWid, CHt)
  elseif activeTab == 16 then drawReplay(CX, CY0, CWid, CHt)
  end

  -- move the menu by dragging any EMPTY area (does NOT block buttons/tabs/sliders)
  if ui.windowHovered() and ui.mouseDown(ui.MouseButton.Left) and not ui.anyItemActive() and not menuDragging then
    menuDragging = true
    menuDragStart = ui.mousePos()
    menuOfsStart = vec2(stor.menuOfsX, stor.menuOfsY)
  end
  if menuDragging then
    if ui.mouseDown(ui.MouseButton.Left) then
      local mp = ui.mousePos()
      stor.menuOfsX = menuOfsStart.x + (mp.x - menuDragStart.x)
      stor.menuOfsY = menuOfsStart.y + (mp.y - menuDragStart.y)
    else
      menuDragging = false
    end
  end
end

---------------------------------------------------------------
-- Bottom HUD: logo + "press M" badge (fades out as the car moves)
---------------------------------------------------------------
local function drawLogoAt(cx, cy, maxW, maxH, alpha)
  if LOGO_TEX then
    local sz = ui.imageSize(LOGO_TEX)
    if sz and sz.x > 1 and sz.y > 1 then
      local sc = math.min(maxW / sz.x, maxH / sz.y)
      local w, h = sz.x * sc, sz.y * sc
      ui.drawImage(LOGO_TEX, vec2(cx - w * 0.5, cy - h * 0.5), vec2(cx + w * 0.5, cy + h * 0.5), rgbm(1, 1, 1, alpha))
      return
    end
  end
  ui.pushDWriteFont('Segoe UI;Weight=Bold')
  dwBox("HB", 26, cx - maxW * 0.5, cy - maxH * 0.5, maxW, maxH, rgbm(1, 1, 1, alpha * 0.45))
  ui.popDWriteFont()
end

local function drawKeyBadge(cx, cy, letter, label, alpha, pw)
  pw = pw or 200
  local ph = 38
  local x0, y0 = cx - pw * 0.5, cy - ph * 0.5
  ui.drawRectFilled(vec2(x0, y0), vec2(x0 + pw, y0 + ph), rgbm(0.05, 0.055, 0.08, 0.82 * alpha), 13)
  ui.drawRect(vec2(x0, y0), vec2(x0 + pw, y0 + ph), rgbm(ACC.r, ACC.g, ACC.b, 0.55 * alpha), 13, nil, 1.4)
  local kb = 26
  local kx = x0 + pw - 10 - kb
  ui.drawRectFilled(vec2(kx, y0 + 7), vec2(kx + kb, y0 + ph - 7), rgbm(ACC.r, ACC.g, ACC.b, 0.92 * alpha), 7)
  dwBox(letter, 14, kx, y0 + 7, kb, ph - 14, rgbm(0.04, 0.05, 0.07, alpha))
  dwRightBox(label, 15, x0 + 12, y0, (kx - 8) - (x0 + 12), ph, rgbm(1, 1, 1, alpha))
end

local HUD_KEYS = { { "M", "Open Menu" }, { "N", "Fast Travel" }, { "T", "Teleport Tab" }, { "B", "Boost" }, { "V", "Repair" }, { "R", "Rewind" }, { "C", "Chat" }, { "X", "Pit Reset" } }
local function drawBottomHud(sim)
  if ac.getUI().appsHidden or sim.focusedCar ~= 0 then return end
  local speed = 0
  pcall(function() speed = ac.getCar(0).speedKmh end)
  local alpha = math.min(math.max((2.5 - speed) / 2.5, 0), 1)
  if alpha <= 0.02 then return end   -- hidden while moving (speed fade)
  local bw, bh = 1070, 156
  local x0 = (sim.windowWidth - bw) * 0.5
  local y0 = sim.windowHeight - bh - 12
  ui.transparentWindow("hud1980", vec2(x0, y0), vec2(bw, bh), function()
    -- visible when the car is stopped; fades out only while driving via the speed-based 'alpha'
    -- (the outer 'if alpha <= 0.02 then return end' already hides it once you're moving).
    drawLogoAt(bw * 0.5, 46, 300, 76, alpha)
    local n = #HUD_KEYS
    local pw, gap = 120, 9
    local total = pw * n + gap * (n - 1)
    local sx = (bw - total) * 0.5
    for i = 1, n do
      drawKeyBadge(sx + (i - 1) * (pw + gap) + pw * 0.5, 124, HUD_KEYS[i][1], HUD_KEYS[i][2], alpha, pw)
    end
  end)
end

---------------------------------------------------------------
-- Custom chat log (correct Arabic) + quick-phrase bar (key C)
---------------------------------------------------------------
local hoverInfo = nil  -- set when a chat name is hovered; drawn as a tooltip in script.drawUI
local function carByName(nm)
  if not nm or nm == "" then return nil end
  local sim = ac.getSim()
  if not sim then return nil end
  for i = 0, sim.carsCount - 1 do
    local dn = nil
    pcall(function() dn = ac.getDriverName(i) end)
    if dn == nm then return i end
  end
  return nil
end
local function drawChatLog(sim)
  if #chatLog == 0 then return end
  if chatBarOpen and not uSt.chatMin then return end   -- show the floating log when the bar is minimized or closed
  local recent = {}
  for i = #chatLog, math.max(1, #chatLog - 7), -1 do
    if pulseT - chatLog[i].t < 16 then table.insert(recent, 1, chatLog[i]) end
  end
  if #recent == 0 then return end
  local w = 640
  local nameW = 224
  local textW = w - nameW - 24
  -- reserve the REAL wrapped height per message (measured at the exact width/size used to draw below)
  -- fixes overlap: the old byte-length guess under-counted lines for Latin/URLs, so text bled onto the next row
  local hs, total = {}, 8
  for i, m in ipairs(recent) do
    local sz = ui.measureDWriteText(m.text, 15, textW)
    hs[i] = math.max(22, math.ceil(sz.y) + 4)
    total = total + hs[i]
  end
  local cy0 = sim.windowHeight - total - 200
  ui.transparentWindow("chatlog1980", vec2(16, cy0), vec2(w, total), function()
    -- auto-hide: reveal while the mouse is over the chat, or a message just arrived; otherwise fade
    -- out. mouseLocalPos (mouse relative to THIS window) is reliable even on a no-input transparent
    -- window; the window stays present so moving the mouse over the area brings the chat back.
    local lp = ui.mouseLocalPos()
    local over = lp.x >= -6 and lp.x <= (w + 6) and lp.y >= -6 and lp.y <= (total + 6)
    local target = (over or (pulseT - chatLog[#chatLog].t < 4)) and 1 or 0
    uSt.chatReveal = (uSt.chatReveal or 1) + (target - (uSt.chatReveal or 1)) * 0.14
    local rv = uSt.chatReveal
    ui.drawRectFilled(vec2(0, 0), vec2(w, total), rgbm(0, 0, 0, 0.32 * rv), 10)
    local yy = 4
    for i, m in ipairs(recent) do
      local age = pulseT - m.t
      local a = (age > 13 and math.max(0, 1 - (age - 13) / 3) or 1) * rv
      local nc = m.color and rgbm(m.color.r, m.color.g, m.color.b, a) or (m.srv and rgbm(CY.r, CY.g, CY.b, a) or rgbm(ACC.r, ACC.g, ACC.b, a))
      dwRightBox(m.name, 14, w - nameW - 8, yy, nameW, 22, nc)
      ui.setCursor(vec2(8, yy))
      ui.dwriteTextAligned(m.text, 15, ui.Alignment.End, ui.Alignment.Start, vec2(textW, hs[i]), true, rgbm(1, 1, 1, a))
      yy = yy + hs[i]
    end
  end)
end

local function drawChatBar(sim)
  if not chatBarOpen then return end
  if uSt.chatMin then
    -- minimized to a small tab: HOVER it to bring the full chat back (no need to press C again)
    local hw, hh = 116, 28
    local hx = (uSt.chatMidX or (sim.windowWidth * 0.5)) - hw * 0.5
    local hy = (uSt.chatBotY or (sim.windowHeight - 120)) - hh
    hx = math.max(0, math.min(sim.windowWidth - hw, hx))
    hy = math.max(0, math.min(sim.windowHeight - hh, hy))
    ui.transparentWindow("chatmin1980", vec2(hx, hy), vec2(hw, hh), true, true, function()
      local hov = ui.windowHovered()
      ui.drawRectFilled(vec2(0, 0), vec2(hw, hh), rgbm(0.07, 0.075, 0.1, hov and 0.95 or 0.55), 9)
      ui.drawRect(vec2(0.5, 0.5), vec2(hw - 0.5, hh - 0.5), rgbm(ACC.r, ACC.g, ACC.b, hov and 0.9 or 0.4), 9, nil, 1.2)
      dwBox("Show Chat", 13, 0, 4, hw, 18, hov and CW or CDm)
      if hov then uSt.chatMin = false; uSt.chatBarIdle = pulseT end   -- mouse over the tab restores it
    end)
    return
  end
  local cols = 4
  local rows = math.ceil(#QUICK_PHRASES / cols)
  local gridH = rows * 48
  local histH = 186
  local topY = 32
  local emojiH = 140
  local bw = 760
  local pw = uSt.showPlayers and 224 or 0   -- attached side panel width for the members list
  local bh = topY + histH + 10 + emojiH + gridH + 54
  local x0 = (sim.windowWidth - bw) * 0.5 + stor.chatOfsX
  local y0 = sim.windowHeight - bh - 120 + stor.chatOfsY
  x0 = math.max(-bw + 80, math.min(sim.windowWidth - 80 - pw, x0)) -- keep on screen
  y0 = math.max(0, math.min(sim.windowHeight - 60, y0))
  uSt.chatMidX = x0 + bw * 0.5; uSt.chatBotY = y0 + bh   -- remembered so the minimized tab sits at the bar's bottom-center
  ui.transparentWindow("chatbar1980", vec2(x0, y0), vec2(bw + pw, bh), true, true, function()
    ui.drawRectFilled(vec2(0, 0), vec2(bw, bh), rgbm(0.07, 0.075, 0.1, stor.chatOpacity), 14)
    ui.drawRect(vec2(0.5, 0.5), vec2(bw - 0.5, bh - 0.5), rgbm(ACC.r, ACC.g, ACC.b, 0.5), 14, nil, 1.4)
    dwBox("Press Enter to send - right-click a name to teleport", 13, 0, 8, bw, 20, CDm)
    dwBox("Teleport", 11, 12, 7, 52, 18, CDm)
    ui.setCursor(vec2(66, 6))
    ui.setNextItemWidth(120)
    stor.chatOpacity = ui.slider("##chatopac", stor.chatOpacity, 0.35, 1.0, "%.2f")
    if bigButton(bw - 136, 4, 126, 22, uSt.showPlayers and "Hide Players" or "Show Players", uSt.showPlayers and rgbm(0.6, 0.32, 0.34, 1) or rgbm(0.2, 0.5, 0.36, 1), "##pltoggle") then uSt.showPlayers = not uSt.showPlayers end

    -- Scrollable history (all messages, correct Arabic)
    ui.drawRectFilled(vec2(10, topY), vec2(bw - 10, topY + histH), rgbm(0, 0, 0, 0.28), 10)
    ui.setCursor(vec2(10, topY))
    ui.childWindow("##chathist", vec2(bw - 20, histH), function()
      local cw = ui.windowWidth() - 18   -- reserve room for the scrollbar so names don't overlap it
      local nameW = 224
      local textW = cw - nameW - 20
      local yy = 0
      for i, m in ipairs(chatLog) do
        -- variable height: long messages wrap DOWN into extra lines instead of overflowing
        local sz = ui.measureDWriteText(m.text, 15, textW)
        local hh = math.max(24, math.ceil(sz.y) + 6)
        -- click a player's name to @mention them in the input box
        if not m.srv then
          ui.setCursor(vec2(cw - nameW - 6, yy))
          if ui.invisibleButton("##men" .. i, vec2(nameW, hh)) then
            chatInput = chatInput .. "@" .. m.name .. " "
            chatInputGen = chatInputGen + 1
          end
          if ui.itemClicked(ui.MouseButton.Right) then   -- right-click a chat name = teleport to them
            pcall(function() local ci = carByName(m.rawName); if ci then TPS(ac.getCar(ci)) end end)
          end
          if ui.itemHovered() then
            ui.drawRectFilled(vec2(cw - nameW - 6, yy + 1), vec2(cw - 4, yy + hh - 1), rgbm(ACC.r, ACC.g, ACC.b, 0.16), 4)
            pcall(function()
              local ci = carByName(m.rawName)
              if ci then
                local car = ac.getCar(ci)
                if car then hoverInfo = { name = m.rawName, spd = math.floor((car.speedKmh or 0) + 0.5), ping = car.ping or -1, t = pulseT } end
              end
            end)
          end
        end
        dwRightBox(m.name, 13, cw - nameW - 4, yy, nameW - 4, 20, m.color or (m.srv and CY or ACC))
        ui.setCursor(vec2(6, yy))
        ui.dwriteTextAligned(m.text, 15, ui.Alignment.End, ui.Alignment.Start, vec2(textW, hh), true, CW)
        yy = yy + hh
      end
      -- mark the TRUE content bottom, then keep newest in view
      ui.setCursor(vec2(0, yy + 4))
      ui.dummy(vec2(1, 1))
      if chatBarJustOpened or #chatLog > chatBarLastCount then ui.setScrollHereY(1); chatBarJustOpened = false end
      chatBarLastCount = #chatLog
    end)

    -- members SIDE PANEL (attached to the right): real players only (AI filtered via isHidingLabels)
    --    left-click = @mention .. right-click = teleport to them at their speed (TPS)
    if pw > 0 then
      local px = bw + 6
      ui.drawRectFilled(vec2(px, topY), vec2(bw + pw - 4, bh - 12), rgbm(0.06, 0.07, 0.1, 0.6), 12)
      ui.drawRect(vec2(px, topY), vec2(bw + pw - 4, bh - 12), rgbm(ACC.r, ACC.g, ACC.b, 0.5), 12, nil, 1.2)
      dwBox("Online Players", 14, px, topY + 6, pw - 10, 18, CY)
      dwRightBox("Left-click: mention - Right-click: teleport", 10, px + 4, topY + 26, pw - 14, 14, CDm)
      ui.setCursor(vec2(px + 6, topY + 46))
      ui.childWindow("##plistwin", vec2(pw - 16, bh - topY - 62), function()
        local sim2 = ac.getSim()
        local n = 0
        if sim2 then
          for i = 0, sim2.carsCount - 1 do
            local nm = ac.getDriverName(i)
            local c = ac.getCar(i)
            if nm and nm ~= "" and c and c.isConnected and not c.isHidingLabels and i ~= (sim2.focusedCar or -1) then
              local ry = n * 32
              ui.setCursor(vec2(0, ry))
              local cl = ui.invisibleButton("##plm" .. i, vec2(pw - 34, 30))
              local rc = ui.itemClicked(ui.MouseButton.Right)
              if ui.itemHovered() then ui.drawRectFilled(vec2(0, ry), vec2(pw - 34, ry + 30), rgbm(ACC.r, ACC.g, ACC.b, 0.16), 6) end
              ui.drawCircleFilled(vec2(9, ry + 15), 3, CGR, 8)
              dwRightBox(nm, 14, 18, ry + 5, pw - 64, 20, CW)
              if cl then chatInput = chatInput .. "@" .. nm .. " "; chatInputGen = chatInputGen + 1 end
              if rc then pcall(function() TPS(c) end) end
              n = n + 1
            end
          end
          if n == 0 then dwBox("No players online", 12, 0, 10, pw - 26, 20, CDm) end
        end
        ui.setCursor(vec2(0, n * 32 + 4)); ui.dummy(vec2(1, 1))
      end)
    end

    -- Emoji area: 3 most-used (top) + all emojis (scrollable). Click inserts into your message.
    local recY = topY + histH + 6
    local recs = { stor.rec1, stor.rec2, stor.rec3 }
    for i = 1, 3 do
      local rw = 56
      local rx = 10 + (i - 1) * (rw + 6)
      ui.setCursor(vec2(rx, recY))
      local rc = ui.invisibleButton("##rec" .. i, vec2(rw, 38))
      ui.drawRectFilled(vec2(rx, recY), vec2(rx + rw, recY + 38), ui.itemHovered() and rgbm(ACC.r, ACC.g, ACC.b, 0.6) or rgbm(1, 1, 1, 0.09), 8)
      dwBox(recs[i] ~= "" and recs[i] or "..", 22, rx, recY, rw, 38, CW)
      if rc and recs[i] ~= "" then useEmoji(recs[i]) end
    end
    dwRightBox("Recently used", 11, 200, recY + 12, bw - 212, 16, CDm)

    local allY = recY + 44
    ui.drawRectFilled(vec2(10, allY), vec2(bw - 10, allY + 90), rgbm(0, 0, 0, 0.22), 8)
    ui.setCursor(vec2(10, allY))
    ui.childWindow("##allemoji", vec2(bw - 20, 90), function()
      local cw = ui.windowWidth()
      local ecols = 13
      local gw = (cw - 8 - (ecols - 1) * 4) / ecols
      for i, em in ipairs(EMOJIS) do
        local col = (i - 1) % ecols
        local row = math.floor((i - 1) / ecols)
        local ex = 4 + col * (gw + 4)
        local ey = 4 + row * (gw + 4)
        ui.setCursor(vec2(ex, ey))
        local ec = ui.invisibleButton("##ae" .. i, vec2(gw, gw))
        if ui.itemHovered() then ui.drawRectFilled(vec2(ex, ey), vec2(ex + gw, ey + gw), rgbm(ACC.r, ACC.g, ACC.b, 0.5), 6) end
        dwBox(em, 19, ex, ey, gw, gw, CW)
        if ec then useEmoji(em) end
      end
      ui.setCursor(vec2(0, math.ceil(#EMOJIS / ecols) * (gw + 4) + 6))
      ui.dummy(vec2(1, 1))
    end)

    -- Quick phrases (sending keeps the bar open)
    local phraseY = topY + histH + 10 + emojiH
    local pw = (bw - 20 - (cols - 1) * 10) / cols
    for i, ph in ipairs(QUICK_PHRASES) do
      local px = 10 + ((i - 1) % cols) * (pw + 10)
      local py = phraseY + math.floor((i - 1) / cols) * 48
      ui.setCursor(vec2(px, py))
      local cl = ui.invisibleButton("##qp" .. i, vec2(pw, 40))
      local hov = ui.itemHovered()
      ui.drawRectFilled(vec2(px, py), vec2(px + pw, py + 40), hov and rgbm(ACC.r, ACC.g, ACC.b, 0.9) or rgbm(1, 1, 1, 0.06), 9)
      dwBox(ph, 15, px, py, pw, 40, hov and DK or CW)
      if cl then pcall(function() ac.sendChatMessage(ph) end) end
    end

    -- Text input with a LIVE correct-Arabic preview that GROWS upward as the message gets longer
    local iy = phraseY + gridH + 8
    local prevW = bw - 140
    local th = 38
    if chatInput ~= "" then
      local sz = ui.measureDWriteText(chatInput, 16, prevW)
      th = math.max(38, math.min(124, math.ceil(sz.y) + 14))
    end
    local top = iy + 38 - th
    ui.setCursor(vec2(16, iy + 5))
    ui.setNextItemWidth(bw - 134)
    local nt, changed, entered = ui.inputText("##chatin" .. chatInputGen, chatInput, ui.InputTextFlags.RetainSelection)
    if changed then chatInput = nt end
    ui.drawRectFilled(vec2(10, top), vec2(bw - 116, iy + 38), rgbm(0.11, 0.115, 0.14, 1), 9)
    ui.drawRect(vec2(10, top), vec2(bw - 116, iy + 38), rgbm(1, 1, 1, 0.1), 9, nil, 1)
    if chatInput ~= "" then
      ui.setCursor(vec2(18, top + 4))
      ui.dwriteTextAligned(chatInput, 16, ui.Alignment.End, ui.Alignment.Start, vec2(prevW, th - 8), true, CW)
    else
      dwRightBox("Type your message...", 13, 18, iy, bw - 140, 38, CDm)
    end
    if bigButton(bw - 108, iy, 98, 38, "Send", chatInput ~= "" and ACC or rgbm(0.3, 0.3, 0.36, 1), "##chatsend") or (entered and chatInput ~= "") then
      if chatInput ~= "" then pcall(function() ac.sendChatMessage(chatInput) end); chatInput = ""; chatInputGen = chatInputGen + 1 end
    end

    -- move the chat window by dragging any EMPTY area (does NOT block buttons/input)
    if ui.windowHovered() and ui.mouseDown(ui.MouseButton.Left) and not ui.anyItemActive() and not chatDragging then
      chatDragging = true
      chatDragStart = ui.mousePos()
      chatOfsStart = vec2(stor.chatOfsX, stor.chatOfsY)
    end
    if chatDragging then
      if ui.mouseDown(ui.MouseButton.Left) then
        local mp = ui.mousePos()
        stor.chatOfsX = chatOfsStart.x + (mp.x - chatDragStart.x)
        stor.chatOfsY = chatOfsStart.y + (mp.y - chatDragStart.y)
      else
        chatDragging = false
      end
    end
    -- AUTO-HIDE (vanilla-style): keep the bar alive while the mouse is over it, while a message is
    -- being typed, or while dragging. mouseLocalPos is relative to THIS window so the bounds also
    -- cover the child areas (history / emoji / members). NOTE: 'pw' was reassigned above to the
    -- phrase width, so recompute the side-panel width here for the bounds.
    local sidePw = uSt.showPlayers and 224 or 0
    local lp = ui.mouseLocalPos()
    local overBar = lp.x >= -14 and lp.x <= (bw + sidePw + 14) and lp.y >= -14 and lp.y <= (bh + 14)
    if overBar or chatInput ~= "" or chatDragging then
      uSt.chatBarIdle = pulseT
    end
  end)
  -- move the mouse away (and stop typing) and the bar shrinks to its tab after ~3s (hover the tab to restore)
  if chatBarOpen and (pulseT - (uSt.chatBarIdle or pulseT)) > 3 then uSt.chatMin = true end
end

---------------------------------------------------------------
-- Input (M / B / V keys)
---------------------------------------------------------------
local function inputCheck()
  local sim = ac.getSim()
  local busy = ui.anyItemFocused() or ui.anyItemActive()
  if sim.isPaused then return end
  if ui.keyboardButtonPressed(ui.KeyIndex.M, false) and not busy then
    menuOpen = not menuOpen
  end
  if ui.keyboardButtonPressed(ui.KeyIndex.T, false) and not busy then   -- T = jump straight to the teleport tab
    menuOpen = true; activeTab = 1
  end
  if ui.keyboardButtonPressed(ui.KeyIndex.B, false) and not busy then
    doBoost()
  end
  if ui.keyboardButtonPressed(ui.KeyIndex.V, false) and not busy then
    repairCar()
  end
  if ui.keyboardButtonPressed(ui.KeyIndex.C, false) and not busy then
    chatBarOpen = not chatBarOpen
    if chatBarOpen then chatBarJustOpened = true; uSt.chatBarIdle = pulseT; uSt.chatMin = false end  -- open full, start grace
  end
  if ui.keyboardButtonPressed(ui.KeyIndex.X, false) and not busy then
    pcall(function() physics.teleportCarTo(0, ac.SpawnSet.Pits) end)
    ghostStart(3)
  end
end

---------------------------------------------------------------
-- Drift meter ... slide angle from car.localVelocity, builds an x1..x5 combo
---------------------------------------------------------------
local function driftUpdate(dt)
  if not stor.driftEnabled then
    driftActive = false
    if driftShown > 0 then driftShown = driftShown - dt end
    return
  end
  local car = ac.getCar(0)
  if not car then return end
  local lv = car.localVelocity
  local spd = car.speedKmh or 0
  local ang = math.deg(math.atan2(lv.x, math.max(math.abs(lv.z), 0.5)))
  driftCurAngle = ang
  local mag = math.abs(ang)
  local drifting = spd > 25 and mag > 12 and mag < 85
  if drifting then
    driftBreak = 0
    if not driftActive then driftActive = true; driftMult = 1; driftRun = 0; driftMultTime = 0; driftYaw = 0; driftSpins = 0 end
    driftRun = driftRun + mag * (spd / 60) * driftMult * dt * 0.6
    local av = car.localAngularVelocity
    driftYaw = driftYaw + (av and av.y or 0) * dt
    local sp = math.floor(math.abs(driftYaw) / (2 * math.pi))
    if sp > driftSpins then
      driftSessionSpins = driftSessionSpins + (sp - driftSpins)
      driftRun = driftRun + (sp - driftSpins) * 500
      driftSpins = sp
    end
    driftMultTime = driftMultTime + dt
    if driftMult < 5 and driftMultTime >= 2.5 then driftMult = driftMult + 1; driftMultTime = 0 end
    driftShown = 1.5
  elseif driftActive then
    driftBreak = driftBreak + dt
    driftShown = 1.5
    if driftBreak > 1.0 then
      local run = math.floor(driftRun)
      driftTotal = driftTotal + run
      if run > driftBest then driftBest = run end
      driftActive = false; driftMult = 1; driftRun = 0
    end
  elseif driftShown > 0 then
    driftShown = driftShown - dt
  end
end

local function drawDriftHud(sim)
  if not stor.driftEnabled then return end
  if driftShown <= 0 and not driftActive then return end
  local a = driftActive and 1 or math.min(driftShown / 0.6, 1)
  local bw, bh = 440, 100
  local x0 = (sim.windowWidth - bw) * 0.5
  ui.transparentWindow("drift1980", vec2(x0, 22), vec2(bw, bh), function()
    dwBox(string.format("x%d", driftMult), 32, 0, 2, bw, 34, rgbm(ACC.r, ACC.g, ACC.b, a))
    dwBox(string.format("%d pts", math.floor(driftRun)), 16, 0, 38, bw, 20, rgbm(1, 1, 1, a))
    if driftSpins > 0 then dwLeftBox(string.format("Spin x%d", driftSpins), 15, 14, 8, 150, 22, rgbm(ACC.r, ACC.g, ACC.b, a)) end
    local by = 74
    local cx = bw * 0.5
    local hw = bw * 0.46
    ui.drawRectFilled(vec2(cx - hw, by), vec2(cx + hw, by + 7), rgbm(1, 1, 1, 0.12 * a), 3)
    ui.drawRectFilled(vec2(cx - 1.5, by - 5), vec2(cx + 1.5, by + 12), rgbm(1, 1, 1, 0.55 * a), 1)
    local frac = math.min(math.abs(driftCurAngle) / 80, 1)
    local col = driftActive and rgbm(ACC.r, ACC.g, ACC.b, a) or rgbm(0.55, 0.58, 0.66, a)
    if driftCurAngle >= 0 then
      ui.drawRectFilled(vec2(cx, by), vec2(cx + hw * frac, by + 7), col, 3)
    else
      ui.drawRectFilled(vec2(cx - hw * frac, by), vec2(cx, by + 7), col, 3)
    end
  end)
end

---------------------------------------------------------------
-- Flashback rewind ... hold R to scrub the car back through recorded history
---------------------------------------------------------------
local function rewindUpdate(dt)
  local car = ac.getCar(0)
  if not car then return end
  local held = ui.keyboardButtonDown(REW_KEY) and not menuOpen and not (ui.anyItemFocused() or ui.anyItemActive())
  if held and #rewHist >= 3 then
    if not rewinding then rewinding = true; rewIdx = #rewHist end
    rewIdx = rewIdx - (3.0 * dt / REW_INT)
    if rewIdx < 1 then rewIdx = 1 end
    local i0 = math.floor(rewIdx)
    local i1 = math.min(i0 + 1, #rewHist)
    local f = rewIdx - i0
    local e0, e1 = rewHist[i0], rewHist[i1]
    if e0 and e1 then
      physics.setCarVelocity(0, vec3(0, 0, 0))
      physics.setCarPosition(0, e0.p + (e1.p - e0.p) * f, vec3(-e0.look.x, 0, -e0.look.z))
    end
    ghostStart(0.6)
    return
  end
  if rewinding then
    local i = math.max(1, math.floor(rewIdx))
    local e = rewHist[i]
    if e then
      physics.setCarPosition(0, e.p, vec3(-e.look.x, 0, -e.look.z))
      physics.setCarVelocity(0, e.vel or vec3(0, 0, 0))
    end
    for k = #rewHist, i + 1, -1 do rewHist[k] = nil end
    rewinding = false
    ghostStart()
    return
  end
  rewTimer = rewTimer + dt
  if rewTimer >= REW_INT then
    rewTimer = rewTimer - REW_INT
    rewHist[#rewHist + 1] = { p = car.position:clone(), look = car.look:clone(), vel = (car.velocity or vec3()):clone() }
    while #rewHist > REW_MAX do table.remove(rewHist, 1) end
  end
end

local function drawRewindHud(sim)
  if not rewinding then return end
  local secBack = math.max(0, (#rewHist - rewIdx) * REW_INT)
  local bw, bh = 360, 92
  ui.transparentWindow("rewind1980", vec2((sim.windowWidth - bw) * 0.5, sim.windowHeight * 0.30), vec2(bw, bh), function()
    ui.drawRectFilled(vec2(0, 0), vec2(bw, bh), rgbm(0.05, 0.05, 0.07, 0.72), 14)
    ui.drawRect(vec2(0, 0), vec2(bw, bh), rgbm(ACC.r, ACC.g, ACC.b, 0.6), 14, nil, 1.4)
    dwBox("REWIND", 24, 0, 12, bw, 30, ACC)
    dwBox(string.format("%.1f seconds back", secBack), 15, 0, 48, bw, 22, CW)
  end)
end

---------------------------------------------------------------
function script.update(dt)
  if not uSt.perfInit then uSt.perfInit = true; applyPerfMode(stor.perfMode) end
  if stor.perfMode then
    uSt.perfTick = uSt.perfTick - dt
    if uSt.perfTick <= 0 then uSt.perfTick = 0.5; perfApplyPerCar(true) end   -- keep new joiners hidden too
  end
  if stor.extraKeep then
    uSt.extraTick = uSt.extraTick - dt
    if uSt.extraTick <= 0 then                                        -- re-apply chosen extras so they survive repair/rewind/teleport
      uSt.extraTick = 0.7
      for i, v in pairs(extraDesired) do pcall(function() ac.setExtraSwitch(i, v) end) end
    end
  end
  if not uSt.timeApplied and pulseT > 2 then
    uSt.timeApplied = true
  end
  if grp < 0.999 then                                                -- keep custom traction applied (survives car resets)
    uSt.gripTick = uSt.gripTick - dt
    if uSt.gripTick <= 0 then uSt.gripTick = 0.8; applyGrip() end
  end
  if tmr.r > 0 then tmr.r = tmr.r - dt end
  if ghostOn then ghostT = ghostT - dt; if ghostT <= 0 then ghostEnd() end end
  if boostTimer > 0 then boostTimer = boostTimer - dt end
  pulseT = pulseT + dt
  inputCheck()
  driftUpdate(dt)
  rewindUpdate(dt)
end

---------------------------------------------------------------
-- Rules / Discord-link welcome screen
---------------------------------------------------------------
local RULES_BAN = {
  "No cheating, hacks, or exploits of any kind",
  "No harassment, hate speech, or toxic behaviour",
  "No ramming, blocking, or intentional griefing",
  "No advertising other servers or services",
  "No inappropriate car names, skins, or chat content",
  "Respect staff decisions - appeals go through Discord",
  "Repeated violations result in permanent removal",
}
local RULES_ORG = {
  "Have fun and keep racing clean",
  "Help new drivers - Hardbrain is a community, not a battlefield",
  "Use /report or the menu report button if someone breaks the rules",
}
local AR_DIG = { "1.", "2.", "3.", "4.", "5.", "6.", "7.", "8.", "9." }
local function rulesRow(cx, cw, yy, n, t, col)
  ui.setCursor(vec2(cx + cw - 24, yy))
  ui.dwriteTextAligned(n, 15, ui.Alignment.Center, ui.Alignment.Center, vec2(24, 24), false, col)
  ui.setCursor(vec2(cx, yy))
  ui.dwriteTextAligned(t, 16, ui.Alignment.End, ui.Alignment.Center, vec2(cw - 30, 24), false, CW)
end
local function drawRulesScreen(sim)
  local sw, sh = sim.windowWidth, sim.windowHeight
  local W = 640
  local H = math.min(linkCode and 712 or 572, sh - 30)
  local x = math.floor((sw - W) * 0.5)
  local y = math.floor((sh - H) * 0.5)
  ui.transparentWindow("rules1980", vec2(0, 0), vec2(sw, sh), true, true, function()
    ui.drawRectFilled(vec2(-60, -60), vec2(sw + 60, sh + 60), rgbm(0, 0, 0, 0.86))
    ui.drawRectFilled(vec2(x, y), vec2(x + W, y + H), rgbm(0.06, 0.07, 0.09, 1), 16)
    ui.drawRect(vec2(x, y), vec2(x + W, y + H), CY, 16, nil, 2)
    ui.drawRectFilled(vec2(x, y), vec2(x + W, y + 6), CY, 16)

    local pad = 32
    local cx = x + pad
    local cw = W - pad * 2
    local yy = y + 22

    if LOGO_TEX then
      pcall(function() ui.drawImage(LOGO_TEX, vec2(x + W * 0.5 - 32, yy), vec2(x + W * 0.5 + 32, yy + 58)) end)
      yy = yy + 64
    end
    ui.setCursor(vec2(cx, yy))
    ui.dwriteTextAligned("Server Rules", 27, ui.Alignment.Center, ui.Alignment.Center, vec2(cw, 36), false, CY)
    ui.drawRectFilled(vec2(cx + cw * 0.5 - 40, yy + 38), vec2(cx + cw * 0.5 + 40, yy + 40), CY, 1)
    yy = yy + 48

    -- Greet the entering player by name, in red
    local pname = ""
    pcall(function() pname = ac.getDriverName(0) or "" end)
    if pname ~= "" then
      ui.setCursor(vec2(cx, yy))
      ui.dwriteTextAligned("Welcome, " .. pname, 18, ui.Alignment.Center, ui.Alignment.Center, vec2(cw, 24), false, CR)
      yy = yy + 32
    end

    for i, t in ipairs(RULES_BAN) do rulesRow(cx, cw, yy, AR_DIG[i], t, CY); yy = yy + 26 end
    yy = yy + 12

    ui.setCursor(vec2(cx, yy))
    ui.dwriteTextAligned("Community Guidelines", 19, ui.Alignment.End, ui.Alignment.Center, vec2(cw, 26), false, CC)
    ui.drawRectFilled(vec2(cx, yy + 28), vec2(cx + cw, yy + 30), rgbm(1, 1, 1, 0.10), 1)
    yy = yy + 38
    for i, t in ipairs(RULES_ORG) do rulesRow(cx, cw, yy, AR_DIG[i], t, CC); yy = yy + 26 end
    yy = yy + 10

    if linkCode then
      local kh = 140
      ui.drawRectFilled(vec2(cx, yy), vec2(cx + cw, yy + kh), rgbm(CC.r, CC.g, CC.b, 0.12), 10)
      ui.drawRect(vec2(cx, yy), vec2(cx + cw, yy + kh), CC, 10, nil, 1)
      ui.setCursor(vec2(cx + 14, yy + 9))
      ui.dwriteTextAligned("Link your Discord to Hardbrain", 16, ui.Alignment.End, ui.Alignment.Center, vec2(cw - 28, 20), false, CC)
      ui.setCursor(vec2(cx, yy + 32))
      ui.dwriteTextAligned("Your code: " .. linkCode, 24, ui.Alignment.Center, ui.Alignment.Center, vec2(cw, 30), false, CW)
      ui.setCursor(vec2(cx + 14, yy + 68))
      ui.dwriteTextAligned("In the Hardbrain Discord link channel, type:", 13, ui.Alignment.End, ui.Alignment.Center, vec2(cw - 28, 18), false, rgbm(0.82, 0.86, 0.92, 1))
      ui.setCursor(vec2(cx, yy + 88))
      ui.dwriteTextAligned("/link " .. linkCode, 17, ui.Alignment.Center, ui.Alignment.Center, vec2(cw, 22), false, CY)
      ui.setCursor(vec2(cx + 14, yy + 114))
      ui.dwriteTextAligned("Channel: link-account in discord.gg/hardbrain", 12, ui.Alignment.End, ui.Alignment.Center, vec2(cw - 28, 18), false, rgbm(0.62, 0.66, 0.74, 1))
      yy = yy + kh + 10
    end

    local bw, bh = 280, 46
    local bx = x + (W - bw) * 0.5
    local by = y + H - bh - 18
    if bigButton(bx, by, bw, bh, "I Agree - Enter Server", CY, "##agreeRules") then
      rulesOpen = false
    end
  end)
end

---------------------------------------------------------------
-- Periodic rules reminder ... fancy top toast, fades in/out every ~10 min
---------------------------------------------------------------
local function drawRulesNotification(sim)
  if pulseT >= uSt.notifNextAt then
    uSt.notifNextAt = pulseT + 600
    uSt.notifStart = pulseT
    uSt.notifIdx = uSt.notifIdx % (#RULES_BAN + #RULES_ORG) + 1
  end
  local age = pulseT - uSt.notifStart
  if age > 8 then return end
  local a = math.max(0, math.min(1, math.min(age / 0.5, (8 - age) / 0.7)))
  if a <= 0.02 then return end
  local rule = uSt.notifIdx <= #RULES_BAN and RULES_BAN[uSt.notifIdx] or RULES_ORG[uSt.notifIdx - #RULES_BAN]
  local W, H = 560, 58
  local x = math.floor((sim.windowWidth - W) * 0.5)
  local y = math.floor(24 + (1 - a) * -10) -- gentle slide-in from the top
  ui.transparentWindow("rulesnotif1980", vec2(x, y), vec2(W, H), function()
    ui.drawRectFilled(vec2(0, 0), vec2(W, H), rgbm(0.06, 0.07, 0.09, 0.93 * a), 13)
    ui.drawRect(vec2(0.5, 0.5), vec2(W - 0.5, H - 0.5), rgbm(CY.r, CY.g, CY.b, 0.85 * a), 13, nil, 1.5)
    ui.drawRectFilled(vec2(0, 0), vec2(6, H), rgbm(CY.r, CY.g, CY.b, a), 13)
    ui.setCursor(vec2(14, 8))
    ui.dwriteTextAligned("Hardbrain Racing Rules", 12, ui.Alignment.End, ui.Alignment.Center, vec2(W - 28, 15), false, rgbm(CY.r, CY.g, CY.b, a))
    ui.setCursor(vec2(14, 26))
    ui.dwriteTextAligned(rule, 18, ui.Alignment.End, ui.Alignment.Center, vec2(W - 28, 26), false, rgbm(1, 1, 1, a))
  end)
end

local function drawReport(sim)
  if not reportOpen then return end
  local bw, bh = 560, 392
  local x0 = (sim.windowWidth - bw) * 0.5
  local y0 = (sim.windowHeight - bh) * 0.5
  ui.transparentWindow("report1980", vec2(x0, y0), vec2(bw, bh), true, true, function()
    ui.drawRectFilled(vec2(0, 0), vec2(bw, bh), rgbm(0.08, 0.085, 0.12, 0.98), 14)
    ui.drawRect(vec2(0.5, 0.5), vec2(bw - 0.5, bh - 0.5), rgbm(0.85, 0.22, 0.24, 0.7), 14, nil, 1.5)
    dwBox("Submit Report", 20, 0, 14, bw, 26, CW)
    ui.drawRectFilled(vec2(16, 50), vec2(bw - 16, 120), rgbm(0.85, 0.22, 0.24, 0.10), 10)
    dwRightBox("Important: save a replay clip before submitting (Ctrl+Shift+S)", 13, 24, 56, bw - 48, 18, rgbm(1, 0.85, 0.6, 1))
    dwRightBox("Describe what happened - include player name, time, and rule broken", 12, 24, 80, bw - 48, 18, rgbm(0.82, 0.86, 0.92, 1))
    dwRightBox("False reports may result in action against your account", 12, 24, 100, bw - 48, 18, rgbm(0.82, 0.86, 0.92, 1))
    -- capture instructions (temporary until one-press auto-capture is built)
    ui.drawRectFilled(vec2(16, 128), vec2(bw - 16, 190), rgbm(0.95, 0.75, 0.2, 0.14), 10)
    ui.drawRect(vec2(16, 128), vec2(bw - 16, 190), rgbm(0.95, 0.75, 0.2, 0.6), 10, nil, 1.2)
    dwBox("How to capture evidence", 13, 16, 133, bw - 32, 18, rgbm(1, 0.85, 0.4, 1))
    dwRightBox("1) Press Ctrl + Shift + S in Content Manager to save a replay clip", 12, 24, 153, bw - 48, 18, CW)
    dwRightBox("2) Describe the incident below and submit", 12, 24, 171, bw - 48, 18, CW)
    local iy = 202
    ui.setCursor(vec2(24, iy + 6))
    ui.setNextItemWidth(bw - 48)
    local nt, changed, entered = ui.inputText("##reportin" .. reportInputGen, reportInput, ui.InputTextFlags.RetainSelection)
    if changed then reportInput = nt end
    ui.drawRectFilled(vec2(16, iy), vec2(bw - 16, iy + 44), rgbm(0.11, 0.115, 0.14, 1), 9)
    ui.drawRect(vec2(16, iy), vec2(bw - 16, iy + 44), rgbm(1, 1, 1, 0.1), 9, nil, 1)
    if reportInput ~= "" then
      dwRightBox(reportInput, 16, 24, iy + 3, bw - 64, 38, CW)
    else
      dwRightBox("Example: Player X rammed me at T1 at 14:32", 13, 24, iy + 3, bw - 64, 38, CDm)
    end
    local by = iy + 62
    local hw = (bw - 60) * 0.5
    if bigButton(24, by, hw, 42, "Send Report", reportInput ~= "" and rgbm(0.9, 0.24, 0.26, 1) or rgbm(0.3, 0.3, 0.36, 1), "##repsend") or (entered and reportInput ~= "") then
      if reportInput ~= "" then
        pcall(function()
          ac.sendChatMessage("/report " .. reportInput)
          ac.setMessage("Report sent", "Staff will review your report on Discord", nil, 4)
        end)
        reportInput = ""; reportInputGen = reportInputGen + 1
        reportOpen = false
      end
    end
    if bigButton(24 + hw + 12, by, hw, 42, "Cancel", rgbm(0.28, 0.30, 0.36, 1), "##repcancel") then
      reportOpen = false
    end
    dwBox("Reports reviewed by Hardbrain staff", 11, 0, bh - 26, bw, 16, CDm)
  end)
end

function script.drawUI()
  local sim = ac.getSim()

  if not rulesInit then
    rulesInit = true
    rulesOpen = true  -- show the rules on every join (per session), not just once
  end

  if not rulesOpen then drawRulesNotification(sim) end
  drawDriftHud(sim)
  drawRewindHud(sim)
  drawChatLog(sim)
  drawChatBar(sim)
  if hoverInfo and (pulseT - hoverInfo.t) < 0.15 then pcall(function()  -- hover tooltip: speed + ping (crash-safe)
    local mp = ui.mousePos()
    local tw, th = 244, 96
    local tx = math.min(mp.x + 16, sim.windowWidth - tw - 8)
    local ty = math.min(mp.y + 4, sim.windowHeight - th - 8)
    ui.transparentWindow("hovertip1980", vec2(tx, ty), vec2(tw, th), function()
      ui.drawRectFilled(vec2(0, 0), vec2(tw, th), rgbm(0.05, 0.06, 0.09, 0.96), 8)
      ui.drawRect(vec2(0.5, 0.5), vec2(tw - 0.5, th - 0.5), rgbm(ACC.r, ACC.g, ACC.b, 0.6), 8, nil, 1)
      dwRightBox(hoverInfo.name or "", 14, 8, 6, tw - 16, 20, CW)
      dwRightBox(string.format("Speed: %d km/h", hoverInfo.spd or 0), 12, 8, 28, tw - 16, 18, CY)
      dwRightBox(string.format("Ping: %d ms", hoverInfo.ping or -1), 12, 8, 48, tw - 16, 18, CGR)
      dwRightBox("Right-click player name = teleport to them", 11, 8, 70, tw - 16, 16, rgbm(0.7, 0.75, 0.85, 1))
    end)
  end) end

  if menuOpen then
    local sw = sim.windowWidth
    local sh = sim.windowHeight
    local px = math.floor((sw - PANEL_W) * 0.5) + stor.menuOfsX
    local py = math.floor((sh - PANEL_H) * 0.5) + stor.menuOfsY
    px = math.max(-PANEL_W + 80, math.min(sw - 80, px)) -- keep the menu on screen
    py = math.max(0, math.min(sh - 60, py))
    -- noPadding = true, inputs = true  ->  buttons/sliders are clickable
    ui.transparentWindow("menu1980", vec2(px, py), vec2(PANEL_W, PANEL_H), true, true, function()
      drawMenu()
    end)
  else
    drawBottomHud(sim)
  end

  drawReport(sim)

  if ghostOn then
    ui.transparentWindow("ghostHUD", vec2(10, 10), vec2(320, 50), function()
      ui.drawRectFilled(vec2(0, 0), vec2(320, 50), rgbm(0, 0, 0, 0.6), 8)
      ui.dwriteTextAligned(string.format("Ghost mode  %.1fs", ghostT),
        17, ui.Alignment.Center, ui.Alignment.Center, vec2(300, 40), false, CC)
    end)
  end

  if rulesOpen then drawRulesScreen(sim) end
end

ac.log("[Hardbrain] Menu (keyboard M/B/V) + PersonalTime/Weather loaded")