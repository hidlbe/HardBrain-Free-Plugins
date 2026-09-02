-- ============================================================
-- SpeedoPlugin — native HUD (no LIVE SPEEDS tower)
-- Drag to move · mouse wheel to resize · position saved
-- ============================================================

local UNITS_MPH = {{UNITS_MPH}}
local MPH_FACTOR = 0.621371

local BASE_W, BASE_H = 680, 130

local stor = ac.storage({
    x = -1,
    y = -1,
    scale = 1.0,
})

local dragging = false
local dragOff = vec2(0, 0)

local function displaySpeed(speedKmh)
    if UNITS_MPH then
        return math.floor(speedKmh * MPH_FACTOR + 0.5)
    end
    return math.floor(speedKmh + 0.5)
end

local function gearText(gear)
    gear = tonumber(gear) or 0
    if gear == 0 then return 'N' end
    if gear == -1 then return 'R' end
    return tostring(gear)
end

local function shiftLights(rpm, limiter)
    limiter = limiter or 8000
    if limiter <= 0 then limiter = 8000 end
    local ratio = math.max(0, math.min(1, rpm / limiter))
    return math.floor(ratio * 7 + 0.001)
end

local function assistOn(car, field)
    if not car then return false end
    local ok, v = pcall(function() return car[field] end)
    if not ok or v == nil then return false end
    local t = type(v)
    if t == 'boolean' then return v end
    if t == 'number' then return v > 0 end
    return false
end

local function drawArc(cx, cy, r, thickness, col)
    local segments = 28
    local startA = math.pi * 0.75
    local endA = math.pi * 0.25
    local span = endA - startA + math.pi * 2
    for i = 0, segments - 1 do
        local t0 = startA + span * (i / segments)
        local t1 = startA + span * ((i + 1) / segments)
        ui.drawLine(
            vec2(cx + math.cos(t0) * r, cy + math.sin(t0) * r),
            vec2(cx + math.cos(t1) * r, cy + math.sin(t1) * r),
            col, thickness)
    end
end

local function clampPos(x, y, w, h, screen)
    x = math.max(8, math.min(screen.x - w - 8, x))
    y = math.max(8, math.min(screen.y - h - 8, y))
    return x, y
end

function script.drawUI()
    if ac.isInReplayMode() then return end
    local car = ac.getCar(0)
    if not car then return end
    if ac.getUI().appsHidden then return end

    local screen = ac.getUI().windowSize
    local scale = math.max(0.55, math.min(1.85, tonumber(stor.scale) or 1.0))
    stor.scale = scale

    local W = math.floor(BASE_W * scale + 0.5)
    local H = math.floor(BASE_H * scale + 0.5)

    local x, y = tonumber(stor.x) or -1, tonumber(stor.y) or -1
    if x < 0 or y < 0 then
        x = (screen.x - W) * 0.5
        y = screen.y - H - 18
        stor.x, stor.y = x, y
    end
    x, y = clampPos(x, y, W, H, screen)

    local mp = ui.mousePos()
    local mDown = ui.mouseDown(ui.MouseButton.Left)

    -- Drag anywhere on the panel
    if mDown and not dragging then
        if mp.x >= x and mp.x <= x + W and mp.y >= y and mp.y <= y + H then
            dragging = true
            dragOff = vec2(mp.x - x, mp.y - y)
        end
    end
    if dragging then
        if mDown then
            x = mp.x - dragOff.x
            y = mp.y - dragOff.y
            x, y = clampPos(x, y, W, H, screen)
            stor.x, stor.y = x, y
        else
            dragging = false
        end
    end

    -- Scroll wheel over panel = resize
    local hovered = mp.x >= x and mp.x <= x + W and mp.y >= y and mp.y <= y + H
    if hovered and not dragging then
        local wheel = 0
        pcall(function() wheel = ac.getUI().mouseWheel or 0 end)
        if wheel ~= 0 then
            local cx = x + W * 0.5
            local cy = y + H * 0.5
            scale = math.max(0.55, math.min(1.85, scale + wheel * 0.08))
            stor.scale = scale
            W = math.floor(BASE_W * scale + 0.5)
            H = math.floor(BASE_H * scale + 0.5)
            x = cx - W * 0.5
            y = cy - H * 0.5
            x, y = clampPos(x, y, W, H, screen)
            stor.x, stor.y = x, y
        end
    end

    local speed = displaySpeed(car.speedKmh or 0)
    local rpm = math.floor(car.rpm or 0)
    local gear = gearText(car.gear)
    local limiter = car.rpmLimiter or car.rpmLimit or 8000
    local lights = shiftLights(car.rpm or 0, limiter)
    local abs = assistOn(car, 'absInAction')
    local tc = assistOn(car, 'tractionControlInAction')
    local unit = UNITS_MPH and 'MPH' or 'KMH'

    local purple = rgbm(0.72, 0.35, 0.96, 0.95)
    local white = rgbm(1, 1, 1, 1)
    local muted = rgbm(1, 1, 1, 0.45)

    ui.transparentWindow('hb_speedo', vec2(x, y), vec2(W, H), function()
        ui.drawRectFilled(vec2(0, 0), vec2(W, H), rgbm(0.06, 0.06, 0.08, 0.94), 14)
        ui.drawRect(vec2(0, 0), vec2(W, H), rgbm(1, 1, 1, 0.10), 14, nil, 1)

        local arcR = 46 * scale
        local arcT = math.max(3.5, 5 * scale)
        local leftCx, leftCy = 72 * scale, H * 0.55
        local rightCx, rightCy = W - 72 * scale, H * 0.55
        drawArc(leftCx, leftCy, arcR, arcT, purple)
        drawArc(rightCx, rightCy, arcR, arcT, purple)

        -- Gear (centered in left arc)
        ui.pushFont(ui.Font.Title)
        local gw = ui.measureText(gear).x
        ui.setCursor(vec2(leftCx - gw * 0.5, leftCy - 22 * scale))
        ui.textColored(gear, white)
        ui.popFont()

        -- Shift lights
        local cx = W * 0.5
        local dotY = 16 * scale
        local dotR = math.max(3.2, 4.5 * scale)
        for i = 1, 7 do
            local dx = cx - 36 * scale + (i - 1) * 12 * scale
            local hot = i >= 6 and lights >= i
            local on = lights >= i
            local c = on and (hot and rgbm(1, 0.35, 0.45, 1) or rgbm(0.95, 0.25, 0.35, 1)) or rgbm(1, 1, 1, 0.12)
            ui.drawCircleFilled(vec2(dx, dotY), dotR, c, 16)
        end

        -- RPM
        ui.pushFont(ui.Font.Small)
        local rpmLabel = 'RPM'
        local rl = ui.measureText(rpmLabel).x
        ui.setCursor(vec2(cx - rl * 0.5, 28 * scale))
        ui.textColored(rpmLabel, muted)
        ui.popFont()

        ui.pushFont(ui.Font.Title)
        local rpmStr = tostring(rpm)
        local rw = ui.measureText(rpmStr).x
        ui.setCursor(vec2(cx - rw * 0.5, 44 * scale))
        ui.textColored(rpmStr, white)
        ui.popFont()

        -- ABS / TC
        local absCol = abs and white or rgbm(1, 1, 1, 0.28)
        local tcCol = tc and white or rgbm(1, 1, 1, 0.28)
        ui.pushFont(ui.Font.Small)
        ui.setCursor(vec2(cx - 42 * scale, 92 * scale))
        ui.textColored('ABS', absCol)
        ui.sameLine(0, 18 * scale)
        ui.textColored('TC', tcCol)
        ui.popFont()

        -- Unit + speed (centered in right arc)
        ui.pushFont(ui.Font.Small)
        local uw = ui.measureText(unit).x
        ui.setCursor(vec2(rightCx - uw * 0.5, rightCy - 38 * scale))
        ui.textColored(unit, muted)
        ui.popFont()

        ui.pushFont(ui.Font.Title)
        local spStr = tostring(speed)
        local sw = ui.measureText(spStr).x
        ui.setCursor(vec2(rightCx - sw * 0.5, rightCy - 14 * scale))
        ui.textColored(spStr, white)
        ui.popFont()

        -- Resize corner hint (subtle)
        if hovered then
            ui.drawTriangleFilled(
                vec2(W - 4, H - 18),
                vec2(W - 4, H - 4),
                vec2(W - 18, H - 4),
                rgbm(1, 1, 1, 0.22))
        end
    end)
end

ac.log('[Speedo] Loaded — drag to move, scroll to resize (no live tower)')
