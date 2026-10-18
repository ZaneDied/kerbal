local world = {}
local ui = require("ui")
local physics = require("physics")

local GAME_WIDTH = 1280
local GAME_HEIGHT = 720
local PIVOT_X = GAME_WIDTH / 2
local PIVOT_Y = 480
local PPM = 1 / physics.M_PER_PX

local rocketData = nil
local zoom = 1.0
local stars = {}

local mapMode = false
local moonAngle = 0
local timeWarp = 1

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function hasDecouplerBelow(targetPart, partsList)
    for _, p in ipairs(partsList) do
        if p ~= targetPart and math.abs(p.x + p.width / 2 - (targetPart.x + targetPart.width / 2)) <= 2 then
            if targetPart.y + targetPart.height == p.y and p.category == "decoupler" then
                return true
            end
        end
    end
    return false
end

local function drawEngineFairing(x, y, w, h)
    love.graphics.push()
    love.graphics.setColor(0.75, 0.78, 0.82)
    love.graphics.polygon("fill", x - 2, y, x + w + 2, y, x + w + 4, y + h + 6, x - 4, y + h + 6)
    love.graphics.setColor(0.5, 0.55, 0.6)
    love.graphics.line(x + w / 2, y, x + w / 2, y + h + 6)
    love.graphics.pop()
end

local function drawPartGraphic(template)
    local cat = template.category
    if cat == "cockpit" then
        love.graphics.setColor(0.85, 0.85, 0.9)
        love.graphics.rectangle("fill", 4, 0, 16, 4)
        love.graphics.rectangle("fill", 2, 4, 20, 8)
        love.graphics.rectangle("fill", 0, 12, 24, 20)
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("fill", 4, 0, 16, 2)
        love.graphics.setColor(0.65, 0.65, 0.7)
        love.graphics.rectangle("fill", 0, 30, 24, 2)
        love.graphics.setColor(0.1, 0.15, 0.2)
        love.graphics.rectangle("fill", 8, 16, 8, 8)
        love.graphics.setColor(0.3, 0.75, 0.95)
        love.graphics.rectangle("fill", 10, 18, 4, 4)
    elseif cat == "fuel" then
        love.graphics.setColor(0.85, 0.85, 0.9)
        love.graphics.rectangle("fill", 0, 0, 24, 40)
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, 3, 40)
        love.graphics.setColor(0.65, 0.65, 0.7)
        love.graphics.rectangle("fill", 21, 0, 3, 40)
        love.graphics.setColor(0.2, 0.2, 0.25)
        love.graphics.rectangle("fill", 0, 18, 24, 4)
    elseif cat == "miniFuel" then
        love.graphics.setColor(0.8, 0.83, 0.88)
        love.graphics.rectangle("fill", 0, 0, 16, 24)
        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, 2, 24)
        love.graphics.setColor(0.6, 0.63, 0.68)
        love.graphics.rectangle("fill", 14, 0, 2, 24)
        love.graphics.setColor(0.2, 0.2, 0.25)
        love.graphics.rectangle("fill", 0, 11, 16, 2)
    elseif cat == "decoupler" then
        love.graphics.setColor(0.3, 0.3, 0.35)
        love.graphics.rectangle("fill", 0, 0, 24, 12)
        love.graphics.setColor(0.8, 0.7, 0.2)
        love.graphics.rectangle("fill", 4, 4, 16, 4)
    elseif cat == "radialDec" then
        love.graphics.setColor(0.35, 0.35, 0.4)
        love.graphics.rectangle("fill", 0, 0, 10, 16)
        love.graphics.setColor(0.9, 0.75, 0.15)
        love.graphics.rectangle("fill", 2, 5, 6, 6)
    elseif cat == "cone" then
        love.graphics.setColor(0.85, 0.85, 0.9)
        love.graphics.polygon("fill", 12, 0, 24, 16, 0, 16)
        love.graphics.setColor(0.5, 0.55, 0.6)
        love.graphics.line(12, 0, 12, 16)
    elseif cat == "heatShield" then
        love.graphics.setColor(0.2, 0.2, 0.22)
        love.graphics.rectangle("fill", 0, 2, 24, 6)
        love.graphics.setColor(0.6, 0.15, 0.1)
        love.graphics.rectangle("fill", 0, 0, 24, 2)
    elseif cat == "engine" then
        love.graphics.setColor(0.25, 0.25, 0.3)
        love.graphics.rectangle("fill", 4, 0, 16, 8)
        love.graphics.setColor(0.7, 0.15, 0.15)
        love.graphics.polygon("fill", 4, 8, 20, 8, 24, 28, 0, 28)
    elseif cat == "miniEngine" then
        love.graphics.setColor(0.3, 0.3, 0.35)
        love.graphics.rectangle("fill", 4, 0, 8, 5)
        love.graphics.setColor(0.6, 0.2, 0.2)
        love.graphics.polygon("fill", 4, 5, 12, 5, 16, 16, 0, 16)
    elseif cat == "parachute" then
        love.graphics.setColor(0.9, 0.4, 0.1)
        love.graphics.rectangle("fill", 3, 0, 10, 3)
        love.graphics.rectangle("fill", 2, 3, 12, 5)
        love.graphics.setColor(0.85, 0.85, 0.9)
        love.graphics.rectangle("fill", 4, 8, 8, 4)
    end
end

function world.load()
    zoom = 1.0
    mapMode = false
    moonAngle = 0
    timeWarp = 1

    stars = {}
    for i = 1, 160 do
        stars[i] = { x = math.random() * GAME_WIDTH, y = math.random() * GAME_HEIGHT, s = 0.4 + math.random() * 0.6 }
    end

    rocketData = { parts = {}, stages = {} }
    if love.filesystem.getInfo("saved_rocket.lua") then
        local chunk = love.filesystem.load("saved_rocket.lua")
        if chunk then
            local ok, data = pcall(chunk)
            if ok and type(data) == "table" then rocketData = data end
        end
    end

    physics.load(rocketData)
end

function world.keypressed(key)
    if key == "m" then
        mapMode = not mapMode
    elseif key == "space" then
        physics.fireStage()
    elseif key == "z" then
        physics.update(0.0001, { throttleMax = true })
    elseif key == "x" then
        physics.update(0.0001, { throttleCut = true })
    elseif key == "r" then
        world.load()
    end
end

function world.mousepressed(x, y, button)
    if button == 1 and mapMode then
        local rx = GAME_WIDTH - 220
        local ry = 20
        if x >= rx + 10 and x <= rx + 95 and y >= ry + 32 and y <= ry + 62 then
            timeWarp = 1
        elseif x >= rx + 105 and x <= rx + 190 and y >= ry + 32 and y <= ry + 62 then
            timeWarp = 5
        end
    end
end

function world.wheelmoved(x, y)
    if not mapMode then
        if y > 0 then
            zoom = math.min(3.0, zoom + 0.1)
        elseif y < 0 then
            zoom = math.max(0.15, zoom - 0.1)
        end
    end
end

function world.update(dt)
    if mapMode then
        moonAngle = moonAngle + dt * 0.02 * timeWarp
    end

    local input = {}
    if not mapMode then
        input.throttleUp = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")
        input.throttleDown = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
        input.left = love.keyboard.isDown("a") or love.keyboard.isDown("left")
        input.right = love.keyboard.isDown("d") or love.keyboard.isDown("right")
    end
    physics.update(dt, input)
end

local function worldToScreen(wx, wy)
    return PIVOT_X + (wx - physics.x) * PPM, PIVOT_Y - (wy - physics.y) * PPM
end

local function drawParticles()
    for _, p in ipairs(physics.particles) do
        local sx, sy = worldToScreen(p.x, p.y)
        local r, g, b, a = 1, 1, 1, 1

        if p.life > 0.8 then
            r, g, b = 1, 1, 1
        elseif p.life > 0.5 then
            r, g, b = 1, 0.9, 0.35
        elseif p.life > 0.2 then
            r, g, b = 1, 0.45, 0.1
        else
            r, g, b = 0.8, 0.15, 0.15
            a = (p.life / 0.2) * 0.8
        end

        love.graphics.setColor(r, g, b, a)
        local sz = p.size or 2
        if sz <= 1 then
            love.graphics.points(math.floor(sx), math.floor(sy))
        else
            love.graphics.rectangle("fill", math.floor(sx), math.floor(sy), sz, sz)
        end
    end

    for _, p in ipairs(physics.airParticles) do
        local sx, sy = worldToScreen(p.x, p.y)
        local r, g, b, a = 1, 1, 1, p.life

        if p.temp > 0.8 then
            r, g, b = 1.0, 0.95, 0.7
        elseif p.temp > 0.5 then
            r, g, b = 1.0, 0.4, 0.0
        elseif p.temp > 0.25 then
            r, g, b = 1.0, 0.05, 0.1
            a = p.life * 0.9
        elseif p.temp > 0.05 then
            r, g, b = 0.5, 0.0, 0.0
            a = p.life * 0.7
        else
            r, g, b = 0.2, 0.4, 0.8
            a = p.life * 0.3
        end

        love.graphics.setColor(r, g, b, a)
        local sz = p.size or 2
        if sz <= 1 then
            love.graphics.points(math.floor(sx), math.floor(sy))
        else
            love.graphics.rectangle("fill", math.floor(sx), math.floor(sy), sz, sz)
        end
    end
end

local function drawGround()
    local groundY = PIVOT_Y + physics.y * PPM
    local reach = 4000

    love.graphics.setColor(0.18, 0.38, 0.22)
    love.graphics.rectangle("fill", PIVOT_X - reach, groundY, reach * 2, 8000)
    love.graphics.setColor(0.24, 0.48, 0.28)
    love.graphics.rectangle("fill", PIVOT_X - reach, groundY, reach * 2, 4)

    if groundY > GAME_HEIGHT + 500 then return end

    love.graphics.setColor(0.14, 0.3, 0.18)
    local spacing = 160
    local base = PIVOT_X - reach + ((-physics.x * PPM) % spacing)
    for gx = base, PIVOT_X + reach, spacing do
        love.graphics.rectangle("fill", gx, groundY + 8, 3, 30)
    end

    local padX = PIVOT_X - physics.x * PPM
    love.graphics.setColor(0.25, 0.27, 0.3)
    love.graphics.rectangle("fill", padX - 120, groundY, 240, 10, 2, 2)
    love.graphics.setColor(0.35, 0.37, 0.42)
    love.graphics.rectangle("fill", padX + 80, groundY - 220, 16, 220)
end

local function drawRocket()
    local f = physics.frame
    if not f or #physics.parts == 0 then return end

    love.graphics.push()
    love.graphics.translate(PIVOT_X, PIVOT_Y)
    love.graphics.rotate(physics.angle)
    love.graphics.translate(-f.cx, -f.bottom)

    for _, p in ipairs(physics.parts) do
        love.graphics.push()
        love.graphics.translate(p.x, p.y)
        drawPartGraphic(p)
        if p.category == "engine" and hasDecouplerBelow(p, physics.parts) then
            drawEngineFairing(0, 0, p.width, p.height)
        end
        love.graphics.pop()
    end

    local d = physics.chuteDeploy
    if d > 0.01 then
        local topY = f.top
        local cy = topY - 40 * d
        local rad = 40 * d
        love.graphics.setColor(0.95, 0.45, 0.15)
        love.graphics.arc("fill", f.cx, cy, rad, math.pi, 2 * math.pi)
        love.graphics.setColor(0.9, 0.9, 0.9)
        love.graphics.line(f.cx - rad, cy, f.cx - 3, topY)
        love.graphics.line(f.cx + rad, cy, f.cx + 3, topY)
        love.graphics.line(f.cx, cy, f.cx, topY)
    end
    love.graphics.pop()

    local heat = physics.heat
    if heat > 0.2 and physics.speed > 1 then
        local h = f.bottom - f.top
        local sa, ca = math.sin(physics.angle), math.cos(physics.angle)
        local dirx, diry = physics.vx / physics.speed, -physics.vy / physics.speed
        local cx = PIVOT_X + sa * h / 2 + dirx * (h / 2 + 4)
        local cy = PIVOT_Y - ca * h / 2 + diry * (h / 2 + 4)
        love.graphics.setBlendMode("add")
        for i = 1, 4 do
            love.graphics.setColor(1, 0.45, 0.1, 0.1 * heat)
            love.graphics.circle("fill", cx, cy, 14 + i * 9)
        end
        love.graphics.setBlendMode("alpha")
    end
end

local function drawDebris()
    local list = physics.debris or {}
    for _, d in ipairs(list) do
        local sx, sy = worldToScreen(d.x, d.y)
        love.graphics.push()
        love.graphics.translate(sx, sy)
        love.graphics.rotate(d.angle)
        for _, p in ipairs(d.parts) do
            love.graphics.push()
            love.graphics.translate(p.x, p.y)
            drawPartGraphic(p)
            love.graphics.pop()
        end
        love.graphics.pop()
    end
end

local function statusText()
    if physics.crashed then return "CRASHED - press [R]", 1, 0.4, 0.3 end
    if #physics.parts == 0 then return "NO ROCKET - build one in hangar [1]", 1, 0.6, 0.3 end
    if physics.onGround and not physics.launched then return "ON PAD - [Space] to launch", 0.9, 0.9, 0.5 end
    if physics.onGround then return "LANDED", 0.5, 1, 0.6 end
    return "IN FLIGHT", 0.4, 0.8, 1
end

function world.draw()
    if mapMode then
        love.graphics.clear(0.02, 0.03, 0.06)

        love.graphics.setColor(1, 1, 1, 0.15)
        for i = 50, GAME_WIDTH, 100 do love.graphics.line(i, 0, i, GAME_HEIGHT) end
        for j = 50, GAME_HEIGHT, 100 do love.graphics.line(0, j, GAME_WIDTH, j) end

        local mapCenterX = GAME_WIDTH / 2
        local mapCenterY = GAME_HEIGHT / 2
        local moonOrbitRadius = 320

        love.graphics.setColor(0.4, 0.45, 0.55, 0.4)
        love.graphics.setLineWidth(1.5)
        love.graphics.circle("line", mapCenterX, mapCenterY, moonOrbitRadius)
        love.graphics.setLineWidth(1)

        love.graphics.setColor(0.2, 0.5, 0.8)
        love.graphics.circle("fill", mapCenterX, mapCenterY, 90)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("EARTH", mapCenterX - 20, mapCenterY - 8)

        local moonX = mapCenterX + math.cos(moonAngle) * moonOrbitRadius
        local moonY = mapCenterY + math.sin(moonAngle) * moonOrbitRadius
        love.graphics.setColor(0.7, 0.7, 0.75)
        love.graphics.circle("fill", moonX, moonY, 30)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("MOON", moonX - 18, moonY - 6)

        local craftOffset = 92 + physics.y / 4000
        local ang = physics.x / physics.PLANET_RADIUS
        local craftMapX = mapCenterX + math.sin(ang) * craftOffset
        local craftMapY = mapCenterY - math.cos(ang) * craftOffset
        love.graphics.setColor(1, 0.6, 0.2)
        love.graphics.circle("fill", craftMapX, craftMapY, 6)
        love.graphics.setColor(1, 1, 1)
        love.graphics.print("SPACECRAFT", craftMapX + 12, craftMapY - 6)

        love.graphics.setColor(0.12, 0.13, 0.16, 0.85)
        love.graphics.rectangle("fill", 20, 20, 300, 60, 6, 6)
        love.graphics.setColor(0.3, 0.35, 0.45)
        love.graphics.rectangle("line", 20, 20, 300, 60, 6, 6)
        love.graphics.setColor(0.9, 0.9, 0.95)
        love.graphics.print("TRACKING STATION (MAP VIEW)", 35, 32)
        love.graphics.setColor(0.7, 0.75, 0.8)
        love.graphics.print("Press [M] to return to Launchpad", 35, 52)
        return
    end

    local t = clamp(physics.y / 45000, 0, 1)
    love.graphics.clear(0.12 * (1 - t) + 0.005, 0.18 * (1 - t) + 0.005, 0.30 * (1 - t) + 0.015)

    if t > 0.1 then
        for _, st in ipairs(stars) do
            love.graphics.setColor(1, 1, 1, (t - 0.1) * st.s)
            love.graphics.rectangle("fill", st.x, st.y, 2, 2)
        end
    end

    love.graphics.push()
    love.graphics.translate(GAME_WIDTH / 2, GAME_HEIGHT / 2)
    love.graphics.scale(zoom, zoom)
    love.graphics.translate(-GAME_WIDTH / 2, -GAME_HEIGHT / 2)

    drawGround()
    drawParticles()
    drawDebris()
    drawRocket()

    love.graphics.pop()

    ui.draw(zoom, rocketData and rocketData.stages or {}, physics.currentDeltaV, physics.maxDeltaV)

    love.graphics.setColor(0.12, 0.13, 0.16, 0.85)
    love.graphics.rectangle("fill", 20, 100, 240, 196, 6, 6)
    love.graphics.setColor(0.3, 0.35, 0.45)
    love.graphics.rectangle("line", 20, 100, 240, 196, 6, 6)
    love.graphics.setColor(0.9, 0.9, 0.95)
    love.graphics.print("FLIGHT TELEMETRY", 35, 110)

    local alt = physics.y
    local altStr = alt >= 10000 and string.format("%.1f km", alt / 1000) or string.format("%.0f m", alt)
    love.graphics.setColor(0.4, 0.8, 1.0)
    love.graphics.print("Altitude: " .. altStr, 35, 132)
    love.graphics.print(string.format("Vertical: %.0f m/s", physics.vy), 35, 150)
    love.graphics.print(string.format("Speed: %.0f m/s", physics.speed), 35, 168)
    love.graphics.print(string.format("Throttle: %.0f%%", physics.throttle * 100), 35, 186)
    love.graphics.print(string.format("Mass: %.0f kg", physics.mass), 35, 204)
    love.graphics.print(string.format("Skin temp: %.0f K", physics.temperature), 35, 222)
    local nextStr = physics.nextStage >= 1 and ("Stage " .. (4 - physics.nextStage)) or "none"
    love.graphics.print("Next stage: " .. nextStr, 35, 240)
    local txt, r, g, b = statusText()
    love.graphics.setColor(r, g, b)
    love.graphics.print(txt, 35, 266)

    if physics.event.time > 0 then
        love.graphics.setColor(1, 1, 1, math.min(1, physics.event.time))
        love.graphics.printf(physics.event.text, 0, 120, GAME_WIDTH, "center")
    end
    love.graphics.setColor(1, 1, 1)
end

return world