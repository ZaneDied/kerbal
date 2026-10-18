local physics = {}

-- Physical Constants
physics.G0 = 9.81
physics.SCALE_HEIGHT = 7500
physics.MAX_AIR_DENSITY = 1.225

-- Simulation State Variables
physics.altitude = 0       -- Meters above sea level
physics.velocity = 0       -- m/s (vertical/flight speed)
physics.acceleration = 0   -- m/s^2
physics.mass = 0           -- Current total mass (kg)
physics.dryMass = 0        -- Structural mass (kg)
physics.fuelMass = 0       -- Remaining propellant (kg)
physics.maxDeltaV = 0      -- Total Delta-V budget
physics.currentDeltaV = 0  -- Remaining Delta-V budget
physics.temperature = 300  -- Surface skin temperature (Kelvin)

-- Particle System for Airflow & Re-entry Plasma
physics.airParticles = {}
physics.MAX_PARTICLES = 1500

function physics.load(rocketData)
    physics.altitude = 0
    physics.velocity = 0
    physics.acceleration = 0
    physics.temperature = 300
    physics.airParticles = {}

    -- Calculate masses and Delta-V from loaded rocket parts
    physics.wetMass = 0
    physics.dryMass = 0
    local effectiveIspSum = 0
    local engineCount = 0

    if rocketData and rocketData.parts then
        for _, p in ipairs(rocketData.parts) do
            local dry = 100
            local fuel = 0
            local isp = 300

            local cat = p.template and p.template.category or p.category
            if cat == "cockpit" then
                dry = 400
            elseif cat == "fuel" then
                dry = 150
                fuel = 750
            elseif cat == "miniFuel" then
                dry = 60
                fuel = 300
            elseif cat == "engine" then
                dry = 500
                isp = 300
                engineCount = engineCount + 1
                effectiveIspSum = effectiveIspSum + isp
            elseif cat == "miniEngine" then
                dry = 200
                isp = 280
                engineCount = engineCount + 1
                effectiveIspSum = effectiveIspSum + isp
            elseif cat == "decoupler" then
                dry = 100
            elseif cat == "radialDec" then
                dry = 50
            elseif cat == "cone" then
                dry = 50
            elseif cat == "heatShield" then
                dry = 150
            elseif cat == "parachute" then
                dry = 40
            end

            physics.dryMass = physics.dryMass + dry
            physics.fuelMass = physics.fuelMass + fuel
        end
    end

    physics.mass = physics.dryMass + physics.fuelMass
    local avgIsp = engineCount > 0 and (effectiveIspSum / engineCount) or 300

    if physics.mass > physics.dryMass and physics.dryMass > 0 and engineCount > 0 then
        physics.maxDeltaV = avgIsp * physics.G0 * math.log(physics.mass / physics.dryMass)
    else
        physics.maxDeltaV = 0
    end
    physics.currentDeltaV = physics.maxDeltaV
end

-- Calculate atmospheric density at a given altitude
function physics.getAirDensity(alt)
    return physics.MAX_AIR_DENSITY * math.exp(-alt / physics.SCALE_HEIGHT)
end

-- Core Physics Update Step (Gravity, Drag, Particles)
function physics.update(dt, craftX, craftY, craftAngle, isThrottleActive, rocketBounds)
    local airDensity = physics.getAirDensity(physics.altitude)

    -- 1. Aerodynamic Drag Acceleration
    local dragCoeff = 0.00008
    local dragDecel = dragCoeff * airDensity * (physics.velocity * physics.velocity)

    -- 2. Gravity & Net Acceleration
    local effectiveGravity = physics.G0
    if physics.altitude > 70000 then
        effectiveGravity = physics.G0 * (70000 / (70000 + physics.altitude))^2
    end

    if physics.velocity > 0 then
        physics.acceleration = -effectiveGravity - dragDecel
    else
        physics.acceleration = -effectiveGravity
    end

    -- Update velocity and altitude
    physics.velocity = physics.velocity + physics.acceleration * dt
    physics.altitude = math.max(0, physics.altitude + physics.velocity * dt)

    -- 3. Atmospheric Particle Stream Simulation (Re-entry / Wind interaction)
    local speedMagnitude = math.abs(physics.velocity)
    local spawnRate = math.floor(airDensity * (speedMagnitude / 20))
    spawnRate = math.min(spawnRate, 40)

    for i = 1, spawnRate do
        if #physics.airParticles < physics.MAX_PARTICLES then
            local spawnDist = 250
            local sideOffset = (math.random() - 0.5) * 160

            local spawnX = craftX + math.cos(craftAngle) * spawnDist - math.sin(craftAngle) * sideOffset
            local spawnY = craftY + math.sin(craftAngle) * spawnDist + math.cos(craftAngle) * sideOffset

            local windVx = -math.cos(craftAngle) * (speedMagnitude * 0.2)
            local windVy = -math.sin(craftAngle) * (speedMagnitude * 0.2)

            table.insert(physics.airParticles, {
                x = spawnX,
                y = spawnY,
                vx = windVx,
                vy = windVy,
                temp = 0.0,
                hasHit = false,
                life = 1.0,
                decay = 0.4 + math.random() * 0.4
            })
        end
    end

    -- Update existing particles
    for i = #physics.airParticles, 1, -1 do
        local p = physics.airParticles[i]
        local nextX = p.x + p.vx * dt
        local nextY = p.y + p.vy * dt

        local dx = nextX - craftX
        local dy = nextY - craftY
        local dist = math.sqrt(dx * dx + dy * dy)

        -- Local space collision check against rocket bounds
        local localX = dx * math.cos(-craftAngle) - dy * math.sin(-craftAngle)
        local localY = dx * math.sin(-craftAngle) + dy * math.cos(-craftAngle)

        local isColliding = false
        if rocketBounds then
            local boxMinX = rocketBounds.minX - rocketBounds.centerX - 1
            local boxMaxX = rocketBounds.maxX - rocketBounds.centerX + 1
            local boxMinY = rocketBounds.minY - rocketBounds.centerY - 1
            local boxMaxY = rocketBounds.maxY - rocketBounds.centerY + 1

            if localX >= boxMinX and localX <= boxMaxX and localY >= boxMinY and localY <= boxMaxY then
                isColliding = true
            end
        end

        if isColliding then
            p.temp = math.min(1.0, p.temp + 0.05)
            p.vx = p.vx * 0.85
            p.vy = p.vy * 0.85
            p.hasHit = true
        else
            p.x = nextX
            p.y = nextY
        end

        if p.hasHit then
            p.temp = math.max(0, p.temp - dt * 1.5)
        end

        p.life = p.life - p.decay * dt
        if p.life <= 0 or dist > 450 then
            table.remove(physics.airParticles, i)
        end
    end
end

return physics