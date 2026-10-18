local physics = {}

physics.G0 = 9.81
physics.PLANET_RADIUS = 600000
physics.SCALE_HEIGHT = 7500
physics.MAX_AIR_DENSITY = 1.225
physics.M_PER_PX = 2
physics.MAX_PARTICLES = 1500
physics.MAX_AIR_PARTICLES = 2500

local CD_A = 0.15
local CHUTE_CD_A = 150
local MAX_DRAG_DECEL = 80
local SAFE_LANDING_SPEED = 15
local MAX_DEBRIS = 40
local MAX_STEP = 1 / 120

local DRY = {
    cockpit = 400, fuel = 150, miniFuel = 60, engine = 500, miniEngine = 200,
    decoupler = 100, radialDec = 50, cone = 50, heatShield = 150, parachute = 40,
}
local FUEL = { fuel = 750, miniFuel = 300 }
local ENGINES = {
    engine     = { thrust = 45000, isp = 300 },
    miniEngine = { thrust = 14000, isp = 280 },
}

physics.parts = {}
physics.tanks = {}
physics.debris = {}
physics.particles = {}
physics.airParticles = {}
physics.frame = nil
physics.event = { text = "", time = 0 }
physics.angularVelocity = 0

local function reset()
    physics.x, physics.y = 0, 0
    physics.vx, physics.vy = 0, 0
    physics.angle = 0
    physics.angularVelocity = 0
    physics.throttle = 0
    physics.thrustN = 0
    physics.accel = 0
    physics.speed = 0
    physics.heat = 0
    physics.temperature = 300
    physics.chuteDeploy = 0
    physics.launched = false
    physics.crashed = false
    physics.onGround = true
    physics.nextStage = 3
    physics.mass, physics.dryMass, physics.fuelMass = 0, 0, 0
    physics.maxDeltaV, physics.currentDeltaV = 0, 0
    physics.avgIsp, physics.engineCount = 300, 0
    physics.parts, physics.tanks = {}, {}
    physics.debris, physics.particles, physics.airParticles = {}, {}, {}
    physics.frame = nil
    physics.event = { text = "", time = 0 }
end
reset()

function physics.getAirDensity(alt)
    return physics.MAX_AIR_DENSITY * math.exp(-math.max(alt, 0) / physics.SCALE_HEIGHT)
end

function physics.notify(text)
    physics.event = { text = text, time = 3 }
end

local function wrapAngle(a)
    return (a + math.pi) % (2 * math.pi) - math.pi
end

local function toWorld(lx, ly)
    local a = physics.angle
    return physics.x + lx * math.cos(a) + ly * math.sin(a),
           physics.y - lx * math.sin(a) + ly * math.cos(a)
end

local function computeFrame()
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, p in ipairs(physics.parts) do
        minX = math.min(minX, p.x)
        minY = math.min(minY, p.y)
        maxX = math.max(maxX, p.x + p.width)
        maxY = math.max(maxY, p.y + p.height)
    end
    if minX == math.huge then return nil end
    return { cx = (minX + maxX) / 2, bottom = maxY, top = minY, minX = minX, maxX = maxX, maxY = maxY }
end

local function rebuildTanks()
    local tanks = {}
    for _, p in ipairs(physics.parts) do
        if p.fuelMax > 0 then tanks[#tanks + 1] = p end
    end
    table.sort(tanks, function(a, b) return a.y > b.y end)
    physics.tanks = tanks
end

local function recalcMass()
    local dry, fuel, ispSum, engines = 0, 0, 0, 0
    for _, p in ipairs(physics.parts) do
        dry = dry + p.dry
        fuel = fuel + p.fuel
        local e = ENGINES[p.category]
        if e then
            engines = engines + 1
            ispSum = ispSum + e.isp
        end
    end
    physics.dryMass, physics.fuelMass, physics.mass = dry, fuel, dry + fuel
    physics.engineCount = engines
    physics.avgIsp = engines > 0 and ispSum / engines or 300
    if engines > 0 and fuel > 0 and dry > 0 then
        physics.currentDeltaV = physics.avgIsp * physics.G0 * math.log(physics.mass / dry)
    else
        physics.currentDeltaV = 0
    end
end

local function burnFuel(amount)
    for _, t in ipairs(physics.tanks) do
        if amount <= 0 then break end
        local take = math.min(t.fuel, amount)
        t.fuel = t.fuel - take
        amount = amount - take
    end
end

local function lowestPointOffset()
    local f = physics.frame
    if not f then return 0 end
    local M = physics.M_PER_PX
    local s, c = math.sin(physics.angle), math.cos(physics.angle)
    local l, r = (f.minX - f.cx) * M, (f.maxX - f.cx) * M
    local top = (f.bottom - f.top) * M
    return math.min(-l * s, -r * s, -l * s + top * c, -r * s + top * c)
end

function physics.load(rocketData)
    reset()
    if rocketData and rocketData.parts then
        for _, sp in ipairs(rocketData.parts) do
            local cat = sp.category
            physics.parts[#physics.parts + 1] = {
                id = sp.id, category = cat,
                x = sp.x, y = sp.y, width = sp.width, height = sp.height,
                side = sp.side, stageIdx = sp.stageIdx, parentId = sp.parentId,
                dry = DRY[cat] or 100,
                fuel = FUEL[cat] or 0,
                fuelMax = FUEL[cat] or 0,
                engineOn = (sp.stageIdx == nil),
                deployed = false,
            }
        end
    end
    physics.frame = computeFrame()
    rebuildTanks()
    recalcMass()
    physics.maxDeltaV = physics.currentDeltaV
end

local function makeDebris(list, frame)
    local M = physics.M_PER_PX
    local minX, maxX, maxY = math.huge, -math.huge, -math.huge
    for _, p in ipairs(list) do
        minX = math.min(minX, p.x)
        maxX = math.max(maxX, p.x + p.width)
        maxY = math.max(maxY, p.y + p.height)
    end
    local pcx = (minX + maxX) / 2
    local wx, wy = toWorld((pcx - frame.cx) * M, (frame.bottom - maxY) * M)
    local a = physics.angle
    local d = {
        parts = {},
        x = wx, y = math.max(0, wy),
        vx = physics.vx - math.sin(a) * 4 + (math.random() - 0.5) * 2,
        vy = physics.vy - math.cos(a) * 4 + (math.random() - 0.5) * 2,
        angle = a, spin = (math.random() - 0.5) * 0.6,
    }
    for _, p in ipairs(list) do
        d.parts[#d.parts + 1] = {
            category = p.category, width = p.width, height = p.height,
            x = p.x - pcx, y = p.y - maxY, side = p.side,
        }
    end
    physics.debris[#physics.debris + 1] = d
    if #physics.debris > MAX_DEBRIS then table.remove(physics.debris, 1) end
    return d
end

local function updateDebris(dt)
    local g = physics.G0
    for _, d in ipairs(physics.debris) do
        if not d.rest then
            d.vy = d.vy - g * dt
            d.x = d.x + d.vx * dt
            d.y = d.y + d.vy * dt
            d.angle = d.angle + d.spin * dt
            if d.y <= 0 then
                d.y = 0
                if d.vy < -3 then
                    d.vy = -d.vy * 0.25
                    d.vx = d.vx * 0.6
                    d.spin = d.spin * 0.5
                else
                    d.vy = 0
                    local k = math.max(0, 1 - 6 * dt)
                    d.vx, d.spin = d.vx * k, d.spin * k
                    d.angle = wrapAngle(d.angle) * k
                    if math.abs(d.vx) < 0.05 and math.abs(d.angle) < 0.01 then d.rest = true end
                end
            end
        end
    end
end

local function isDescendant(p, rootId, byId)
    local cur, guard = p, 0
    while cur and guard < 50 do
        if cur.parentId == rootId then return true end
        cur = cur.parentId and byId[cur.parentId] or nil
        guard = guard + 1
    end
    return false
end

local function jettison(marked)
    if next(marked) == nil then return false end
    local oldFrame = physics.frame
    local kept, gone = {}, {}
    for _, p in ipairs(physics.parts) do
        if marked[p] then gone[#gone + 1] = p else kept[#kept + 1] = p end
    end
    if #kept == 0 or #gone == 0 then return false end

    makeDebris(gone, oldFrame)
    physics.parts = kept
    local newFrame = computeFrame()

    local M = physics.M_PER_PX
    physics.x, physics.y = toWorld((newFrame.cx - oldFrame.cx) * M,
                                   (oldFrame.bottom - newFrame.bottom) * M)
    physics.y = math.max(0, physics.y)
    physics.frame = newFrame
    rebuildTanks()
    recalcMass()
    return true
end

function physics.fireStage()
    local s = physics
    if s.crashed or #s.parts == 0 then return end

    if not s.launched then
        s.launched = true
        s.throttle = 1.0
        s.notify("Ignition!")
    end
    if s.nextStage < 1 then return end

    local n = s.nextStage
    s.nextStage = n - 1

    local byId = {}
    for _, p in ipairs(s.parts) do byId[p.id] = p end

    local marked = {}
    for _, p in ipairs(s.parts) do
        if p.stageIdx == n then
            local cat = p.category
            if ENGINES[cat] then
                p.engineOn = true
            elseif cat == "parachute" then
                p.deployed = true
                s.notify("Parachute deployed")
            elseif cat == "decoupler" then
                for _, q in ipairs(s.parts) do
                    if q.y >= p.y - 0.01 then marked[q] = true end
                end
            elseif cat == "radialDec" then
                marked[p] = true
                for _, q in ipairs(s.parts) do
                    if isDescendant(q, p.id, byId) then marked[q] = true end
                end
            end
        end
    end

    local changed = true
    while changed do
        changed = false
        for _, q in ipairs(s.parts) do
            if not marked[q] and q.parentId and marked[byId[q.parentId]] then
                marked[q] = true
                changed = true
            end
        end
    end

    if jettison(marked) then s.notify("Stage " .. (4 - n) .. " separated") end
end

local function crash()
    local s = physics
    local f = s.frame
    s.crashed = true
    s.throttle = 0
    s.thrustN = 0
    s.y = math.max(0, s.y)

    local cx, cy = toWorld(0, (f.bottom - f.top) * s.M_PER_PX / 2)
    cy = math.max(cy, 1)
    for _, p in ipairs(s.parts) do
        local d = makeDebris({ p }, f)
        d.vx = s.vx * 0.2 + (math.random() - 0.5) * 50
        d.vy = 8 + math.random() * 30
        d.spin = (math.random() - 0.5) * 8
    end
    for _ = 1, 70 do
        local ang = math.random() * math.pi
        local sp = 5 + math.random() * 45
        local life = 0.4 + math.random() * 0.7
        s.particles[#s.particles + 1] = {
            kind = "fire", x = cx, y = cy,
            vx = math.cos(ang) * sp, vy = math.sin(ang) * sp,
            life = life, maxLife = life, size = 5 + math.random() * 6,
        }
    end
    for _ = 1, 35 do
        local life = 1.5 + math.random() * 2
        s.particles[#s.particles + 1] = {
            kind = "smoke", x = cx + (math.random() - 0.5) * 20, y = cy,
            vx = (math.random() - 0.5) * 12, vy = 4 + math.random() * 12,
            life = life, maxLife = life, size = 8 + math.random() * 6,
        }
    end
    s.parts, s.tanks, s.frame = {}, {}, nil
    s.notify("Vehicle destroyed - press R to reset")
end

local function step(h)
    local s = physics
    if not s.frame then return end

    local thrustN, mdot = 0, 0
    if s.launched and s.throttle > 0 and s.fuelMass > 0 then
        for _, p in ipairs(s.parts) do
            local e = ENGINES[p.category]
            if e and p.engineOn then
                thrustN = thrustN + e.thrust * s.throttle
                mdot = mdot + e.thrust * s.throttle / (e.isp * s.G0)
            end
        end
        local want = mdot * h
        if want > s.fuelMass then
            thrustN = thrustN * (s.fuelMass / want)
            want = s.fuelMass
        end
        if want > 0 then
            burnFuel(want)
            recalcMass()
        end
    end
    s.thrustN = thrustN

    local m = s.mass
    local alt = math.max(0, s.y)
    local rho = s.getAirDensity(alt)
    local r = s.PLANET_RADIUS + alt
    local g = s.G0 * (s.PLANET_RADIUS / r) ^ 2
    local sinA, cosA = math.sin(s.angle), math.cos(s.angle)

    local ax = thrustN * sinA / m
    local ay = thrustN * cosA / m - g + (s.vx * s.vx) / r

    local hasChute = false
    for _, p in ipairs(s.parts) do
        if p.deployed then hasChute = true break end
    end
    if hasChute then
        s.chuteDeploy = math.min(1, s.chuteDeploy + h / 2.5)
    else
        s.chuteDeploy = 0
    end

    local speed = math.sqrt(s.vx * s.vx + s.vy * s.vy)
    if speed > 0.01 then
        local cda = CD_A + CHUTE_CD_A * s.chuteDeploy
        local dragA = 0.5 * rho * speed * speed * cda / m
        dragA = math.min(dragA, MAX_DRAG_DECEL, speed / h * 0.5)
        ax = ax - dragA * s.vx / speed
        ay = ay - dragA * s.vy / speed
    end
    s.accel = math.sqrt(ax * ax + ay * ay)

    s.vx = s.vx + ax * h
    s.vy = s.vy + ay * h
    s.x = s.x + s.vx * h
    s.y = s.y + s.vy * h

    local clearance = s.y + lowestPointOffset()
    if clearance <= 0 then
        s.y = s.y - clearance
        if not s.onGround then
            local impact = math.sqrt(s.vx * s.vx + s.vy * s.vy)
            local tilt = math.abs(wrapAngle(s.angle))
            if impact > SAFE_LANDING_SPEED
               or (tilt > 1.2 and impact > 2)
               or (tilt > 0.6 and impact > 6) then
                crash()
                return
            end
            s.notify("Touchdown")
        end
        if s.vy < 0 then s.vy = 0 end
        s.vx = s.vx * math.max(0, 1 - 10 * h)
        s.onGround = true
        if thrustN < m * g then
            s.angularVelocity = s.angularVelocity * 0.9
            s.angle = wrapAngle(s.angle) * math.max(0, 1 - 2.5 * h)
        end
    else
        s.onGround = false
    end
end

local function spawnExhaust(dt)
    local s = physics
    if s.thrustN <= 0 or not s.frame then return end
    local M, f = s.M_PER_PX, s.frame
    local rho = s.getAirDensity(s.y)
    local sinA, cosA = math.sin(s.angle), math.cos(s.angle)
    local expand = 1 + (1 - rho / s.MAX_AIR_DENSITY) * 0.8

    for _, p in ipairs(s.parts) do
        if p.engineOn and ENGINES[p.category] then
            local nx, ny = toWorld((p.x + p.width / 2 - f.cx) * M, (f.bottom - (p.y + p.height)) * M)
            local n = math.floor(320 * s.throttle * dt + math.random())
            for _ = 1, n do
                if #s.particles >= s.MAX_PARTICLES then return end
                local jx = (math.random() - 0.5) * p.width * M * 0.7
                local ev = 240 + math.random(0, 180)
                local spread = (math.random() - 0.5) * 0.4
                local life = 1.2
                local decay = 1.8 + math.random() * 1.5
                s.particles[#s.particles + 1] = {
                    kind = "exhaust",
                    x = nx + jx * cosA, y = ny - jx * sinA,
                    vx = s.vx - sinA * ev + cosA * spread * 90,
                    vy = s.vy - cosA * ev - sinA * spread * 90,
                    life = life, maxLife = life, decay = decay,
                    size = math.random(2, 4) * expand,
                }
            end
        end
    end
end

local function spawnAirParticles(dt)
    local s = physics
    local speed = s.speed
    local rho = s.getAirDensity(s.y)
    if speed < 5 or rho < 0.0005 then return end

    local spawnRate = math.floor(rho * (speed / 8))
    spawnRate = math.min(spawnRate, 120)

    local f = s.frame
    if f then
        local heading = s.angle
        local moveAngle = (speed > 0.1) and math.atan2(s.vy, s.vx) or (s.angle + math.pi/2)

        for i = 1, spawnRate do
            if #s.airParticles < s.MAX_AIR_PARTICLES then
                local spawnDist = 280 * s.M_PER_PX
                local sideOffset = (math.random() - 0.5) * 160 * s.M_PER_PX

                local spawnX = s.x - math.cos(moveAngle) * spawnDist - math.sin(heading) * sideOffset
                local spawnY = s.y - math.sin(moveAngle) * spawnDist + math.cos(heading) * sideOffset

                local windVx = s.vx - math.cos(moveAngle) * (speed * 0.25)
                local windVy = s.vy - math.sin(moveAngle) * (speed * 0.25)

                table.insert(s.airParticles, {
                    x = spawnX,
                    y = spawnY,
                    vx = windVx,
                    vy = windVy,
                    temp = 0.0,
                    hasHit = false,
                    life = 1.2,
                    size = math.random(1, 3),
                    decay = 0.3 + math.random() * 0.4
                })
            end
        end
    end
end

local function updateAirParticles(dt)
    local s = physics
    local f = s.frame

    for i = #s.airParticles, 1, -1 do
        local p = s.airParticles[i]
        local nextX = p.x + p.vx * dt
        local nextY = p.y + p.vy * dt

        local dx = nextX - s.x
        local dy = nextY - s.y
        local dist = math.sqrt(dx * dx + dy * dy)

        local localX = dx * math.cos(-s.angle) - dy * math.sin(-s.angle)
        local localY = dx * math.sin(-s.angle) + dy * math.cos(-s.angle)

        local isColliding = false
        local nx, ny = 0, 0

        local compressionHeat = 0.001
        local outwardPressure = 15 * s.M_PER_PX
        local slipFriction = 0.92

        if f then
            local boxMinX = f.minX - f.cx - 1
            local boxMaxX = f.maxX - f.cx + 1
            local boxMinY = f.top - f.bottom - 1
            local boxMaxY = 1

            if localX >= boxMinX and localX <= boxMaxX and localY >= boxMinY and localY <= boxMaxY then
                isColliding = true

                local dLeft = localX - boxMinX
                local dRight = boxMaxX - localX
                local dTop = localY - boxMinY
                local dBottom = boxMaxY - localY

                local minDist = math.min(dLeft, dRight, dTop, dBottom)
                local localNx, localNy = 0, 0

                if minDist == dLeft then
                    localNx = -1
                elseif minDist == dRight then
                    localNx = 1
                elseif minDist == dTop then
                    localNy = -1
                else
                    localNy = 1
                end

                nx = localNx * math.cos(s.angle) - localNy * math.sin(s.angle)
                ny = localNx * math.sin(s.angle) + localNy * math.cos(s.angle)
            end
        end

        if isColliding then
            local tx = -ny
            local ty = nx

            local vn = p.vx * nx + p.vy * ny
            local vt = p.vx * tx + p.vy * ty

            p.temp = math.min(1.0, p.temp + math.abs(vn) * compressionHeat)

            vn = outwardPressure 
            vt = vt * slipFriction 

            p.vx = (vn * nx) + (vt * tx)
            p.vy = (vn * ny) + (vt * ty)

            p.hasHit = true
        else
            p.x = nextX
            p.y = nextY
        end

        if p.hasHit then
            p.vx = p.vx * 0.96
            p.vy = p.vy * 0.96
            p.temp = math.max(0, p.temp - dt * 1.6)
        end

        p.life = p.life - p.decay * dt
        if p.life <= 0 or dist > 800 * s.M_PER_PX then
            table.remove(s.airParticles, i)
        end
    end
end

local function updateParticles(dt)
    local list = physics.particles
    for i = #list, 1, -1 do
        local p = list[i]
        p.life = p.life - (p.decay or 2.0) * dt
        if p.life <= 0 then
            table.remove(list, i)
        else
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            local drag = math.max(0, 1 - 1.5 * dt)
            p.vx, p.vy = p.vx * drag, p.vy * drag
            if p.kind == "smoke" then p.vy = p.vy + 3 * dt end
            if p.y < 0 then
                p.y = 0
                p.vy = 0
                p.vx = p.vx * 0.9
            end
        end
    end
end

function physics.update(dt, input)
    local s = physics
    dt = math.min(dt, 0.05)
    if dt <= 0 then return end
    input = input or {}

    if s.event.time > 0 then s.event.time = s.event.time - dt end

    if not s.crashed and s.frame then
        if input.throttleUp then s.throttle = math.min(1, s.throttle + 0.5 * dt) end
        if input.throttleDown then s.throttle = math.max(0, s.throttle - 0.5 * dt) end
        if input.throttleMax then s.throttle = 1 end
        if input.throttleCut then s.throttle = 0 end

        if not s.onGround then
            local turnTorque = 4.5
            if input.left then
                s.angularVelocity = s.angularVelocity - turnTorque * dt
            elseif input.right then
                s.angularVelocity = s.angularVelocity + turnTorque * dt
            else
                s.angularVelocity = s.angularVelocity * math.max(0, 1 - 3.5 * dt)
            end
            s.angle = s.angle + s.angularVelocity * dt
        else
            s.angularVelocity = s.angularVelocity * 0.8
            s.angle = wrapAngle(s.angle) * math.max(0, 1 - 2.5 * dt)
        end

        local steps = math.max(1, math.ceil(dt / MAX_STEP))
        local h = dt / steps
        for _ = 1, steps do
            step(h)
            if s.crashed then break end
        end
    end

    s.speed = math.sqrt(s.vx * s.vx + s.vy * s.vy)
    local rho = s.getAirDensity(s.y)
    local target = math.min(1, rho * s.speed ^ 3 / 4e8)
    s.heat = s.heat + (target - s.heat) * math.min(1, 3 * dt)
    s.temperature = 300 + s.heat * 2500

    updateDebris(dt)
    spawnExhaust(dt)
    spawnAirParticles(dt)
    updateParticles(dt)
    updateAirParticles(dt)
end

return physics