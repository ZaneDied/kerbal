-- Celestial Bodies
local planet = {
    x = 0,
    y = 0,
    radius = 500000,         -- 500 km radius
    mu = 3.5316e12,          -- Gravitational parameter
    atmHeight = 60000,       -- 60 km atmosphere
    scaleHeight = 5000,
    rho0 = 1.225
}

local moon = {
    orbitRadius = 2200000,   
    orbitAngle = 0,
    orbitSpeed = 0.015,      
    radius = 120000,         
    mu = 6.5e10,             
    soi = 250000,            
    x = 0,
    y = 0
}

-- Launchpad fixed coordinates (top of planet)
local launchpad = {
    x = 0,
    y = -planet.radius
}

-- Rocket State
local rocket = {
    x = launchpad.x,
    y = launchpad.y - 1,
    vx = 0,
    vy = 0,
    angle = -math.pi / 2,
    angularVelocity = 0,
    torque = 2.5,
    rotationalInertia = 0.8,
    sasEnabled = true,

    dryMass = 1000,
    fuel = 2500,             
    maxFuel = 2500,
    thrust = 130000,
    isp = 320,
    dragCoeff = 0.0004,
    
    throttle = 0,
    isDestroyed = false
}

-- Camera
local camera = { x = launchpad.x, y = launchpad.y - 150, zoom = 0.8 }
local stars = {}

function love.load()
    love.window.setTitle("2D Spaceflight Simulator - Fixed Ground Camera")
    love.window.setMode(1000, 750)

    -- Generate Starfield
    math.randomseed(42)
    for i = 1, 600 do
        table.insert(stars, {
            x = math.random(-4000000, 4000000),
            y = math.random(-4000000, 4000000),
            size = math.random(1, 3)
        })
    end
end

function love.update(dt)
    if rocket.isDestroyed then return end

    -- --- 1. MOON ORBIT MECHANICS ---
    moon.orbitAngle = moon.orbitAngle + moon.orbitSpeed * dt
    moon.x = planet.x + math.cos(moon.orbitAngle) * moon.orbitRadius
    moon.y = planet.y + math.sin(moon.orbitAngle) * moon.orbitRadius

    -- --- 2. CONTROLS ---
    if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
        rocket.throttle = math.min(1, rocket.throttle + 1.2 * dt)
    elseif love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") then
        rocket.throttle = math.max(0, rocket.throttle - 1.2 * dt)
    end

    local steeringInput = 0
    if love.keyboard.isDown("a") or love.keyboard.isDown("left") then
        steeringInput = -1
    elseif love.keyboard.isDown("d") or love.keyboard.isDown("right") then
        steeringInput = 1
    end

    -- Torque & Rotation
    local angularAccel = (steeringInput * rocket.torque) / rocket.rotationalInertia
    rocket.angularVelocity = rocket.angularVelocity + angularAccel * dt

    if steeringInput == 0 and rocket.sasEnabled then
        rocket.angularVelocity = rocket.angularVelocity * math.pow(0.01, dt)
    end

    rocket.angle = rocket.angle + rocket.angularVelocity * dt

    -- --- 3. GRAVITY & SPHERE OF INFLUENCE (SOI) ---
    local distToMoon = math.sqrt((rocket.x - moon.x)^2 + (rocket.y - moon.y)^2)
    local activeBody = (distToMoon < moon.soi) and moon or planet

    local dx = rocket.x - activeBody.x
    local dy = rocket.y - activeBody.y
    local r = math.sqrt(dx * dx + dy * dy)
    local upX, upY = dx / r, dy / r

    -- Gravity
    local gravityMag = activeBody.mu / (r * r)
    local gravityAx = -gravityMag * upX
    local gravityAy = -gravityMag * upY

    -- Engine Thrust
    local totalMass = rocket.dryMass + rocket.fuel
    local currentThrust = 0
    
    if rocket.fuel > 0 and rocket.throttle > 0 then
        currentThrust = rocket.thrust * rocket.throttle
        local massFlowRate = currentThrust / (rocket.isp * 9.81)
        rocket.fuel = math.max(0, rocket.fuel - massFlowRate * dt)
    else
        if rocket.fuel <= 0 then rocket.throttle = 0 end
    end

    local thrustAx = (math.cos(rocket.angle) * currentThrust) / totalMass
    local thrustAy = (math.sin(rocket.angle) * currentThrust) / totalMass

    -- Atmospheric Drag
    local dragAx, dragAy = 0, 0
    if activeBody == planet then
        local altitude = r - planet.radius
        if altitude < planet.atmHeight and altitude > 0 then
            local airDensity = planet.rho0 * math.exp(-altitude / planet.scaleHeight)
            local vSq = rocket.vx * rocket.vx + rocket.vy * rocket.vy
            local vMag = math.sqrt(vSq)
            if vMag > 1 then
                local dragForce = 0.5 * airDensity * vSq * rocket.dragCoeff
                dragAx = -dragForce * (rocket.vx / vMag) / totalMass
                dragAy = -dragForce * (rocket.vy / vMag) / totalMass
            end
        end
    end

    -- Accelerations
    rocket.vx = rocket.vx + (gravityAx + thrustAx + dragAx) * dt
    rocket.vy = rocket.vy + (gravityAy + thrustAy + dragAy) * dt

    -- Ground Collision
    local radialVelocity = rocket.vx * upX + rocket.vy * upY

    if r <= activeBody.radius + 0.5 then
        if radialVelocity < 0 then
            local impactSpeed = math.sqrt(rocket.vx * rocket.vx + rocket.vy * rocket.vy)
            rocket.x = activeBody.x + upX * (activeBody.radius + 0.5)
            rocket.y = activeBody.y + upY * (activeBody.radius + 0.5)

            if impactSpeed > 25 then
                rocket.isDestroyed = true
            else
                rocket.vx = 0
                rocket.vy = 0
                rocket.angularVelocity = 0
            end
        end
    end

    rocket.x = rocket.x + rocket.vx * dt
    rocket.y = rocket.y + rocket.vy * dt

    -- --- 4. SMART LAUNCHPAD / ORBITAL CAMERA ---
    local altPlanet = math.sqrt((rocket.x - planet.x)^2 + (rocket.y - planet.y)^2) - planet.radius
    
    -- Blend factor between Ground Cam (0) and Flight Cam (1)
    local blend = math.max(0, math.min(1, (altPlanet - 50) / 400))

    local targetCamX = (1 - blend) * launchpad.x + blend * rocket.x
    local targetCamY = (1 - blend) * (launchpad.y - 120) + blend * rocket.y

    camera.x = camera.x + (targetCamX - camera.x) * 0.08
    camera.y = camera.y + (targetCamY - camera.y) * 0.08

    local targetZoom = (1 - blend) * 0.8 + blend * math.max(0.00015, math.min(0.8, 300 / math.max(20, altPlanet)))
    camera.zoom = camera.zoom + (targetZoom - camera.zoom) * 0.08
end

function love.keypressed(key)
    if key == "z" then rocket.throttle = 1 end
    if key == "x" then rocket.throttle = 0 end
    if key == "t" then rocket.sasEnabled = not rocket.sasEnabled end
    if key == "r" and rocket.isDestroyed then love.event.quit("restart") end
end

function love.draw()
    local altPlanet = math.sqrt((rocket.x - planet.x)^2 + (rocket.y - planet.y)^2) - planet.radius
    local distMoon = math.sqrt((rocket.x - moon.x)^2 + (rocket.y - moon.y)^2)

    -- Background Transition
    local atmFactor = math.max(0, math.min(1, altPlanet / planet.atmHeight))
    love.graphics.clear(0.05 * (1 - atmFactor), 0.25 * (1 - atmFactor), 0.65 * (1 - atmFactor))

    love.graphics.push()
    
    -- Camera Transform
    love.graphics.translate(500, 375)
    love.graphics.scale(camera.zoom, camera.zoom)
    love.graphics.translate(-camera.x, -camera.y)

    -- Stars
    love.graphics.setColor(1, 1, 1, 0.8)
    for _, star in ipairs(stars) do
        love.graphics.circle("fill", star.x, star.y, star.size / camera.zoom)
    end

    -- Trajectory Line
    love.graphics.setColor(0.2, 0.7, 1.0, 0.5)
    local simX, simY = rocket.x, rocket.y
    local simVx, simVy = rocket.vx, rocket.vy
    local simDt = 2.0
    
    for i = 1, 150 do
        local dMoon = math.sqrt((simX - moon.x)^2 + (simY - moon.y)^2)
        local body = (dMoon < moon.soi) and moon or planet
        
        local simDx = simX - body.x
        local simDy = simY - body.y
        local simR = math.sqrt(simDx * simDx + simDy * simDy)
        
        local gMag = body.mu / (simR * simR)
        simVx = simVx - gMag * (simDx / simR) * simDt
        simVy = simVy - gMag * (simDy / simR) * simDt
        
        local nextX = simX + simVx * simDt
        local nextY = simY + simVy * simDt
        
        love.graphics.line(simX, simY, nextX, nextY)
        simX, simY = nextX, nextY
        if simR <= body.radius then break end
    end

    -- Draw Planet & Atmosphere
    love.graphics.setColor(0.3, 0.6, 1.0, 0.15)
    love.graphics.circle("fill", planet.x, planet.y, planet.radius + planet.atmHeight)
    love.graphics.setColor(0.18, 0.5, 0.22)
    love.graphics.circle("fill", planet.x, planet.y, planet.radius)

    -- Draw Launchpad Structure
    love.graphics.setColor(0.3, 0.3, 0.3)
    love.graphics.rectangle("fill", launchpad.x - 30, launchpad.y - 5, 60, 10)

    -- Draw Moon & SOI Shell
    love.graphics.setColor(0.5, 0.5, 0.6, 0.1)
    love.graphics.circle("fill", moon.x, moon.y, moon.soi)
    love.graphics.setColor(0.7, 0.7, 0.75)
    love.graphics.circle("fill", moon.x, moon.y, moon.radius)

    -- Velocity Vector Arrow
    local speed = math.sqrt(rocket.vx * rocket.vx + rocket.vy * rocket.vy)
    if speed > 2 and not rocket.isDestroyed then
        love.graphics.setColor(0.2, 0.9, 0.3, 0.7)
        local vectorLen = math.min(100, speed * 0.5) / camera.zoom
        local vAngle = math.atan2(rocket.vy, rocket.vx)
        love.graphics.line(rocket.x, rocket.y, rocket.x + math.cos(vAngle) * vectorLen, rocket.y + math.sin(vAngle) * vectorLen)
    end

    -- Draw Rocket
    if not rocket.isDestroyed then
        love.graphics.push()
        love.graphics.translate(rocket.x, rocket.y)
        love.graphics.rotate(rocket.angle)

        love.graphics.setColor(0.9, 0.9, 0.9)
        love.graphics.rectangle("fill", -30 / camera.zoom, -10 / camera.zoom, 50 / camera.zoom, 20 / camera.zoom, 3, 3)

        love.graphics.setColor(0.8, 0.2, 0.2)
        love.graphics.polygon("fill", 20 / camera.zoom, -10 / camera.zoom, 35 / camera.zoom, 0, 20 / camera.zoom, 10 / camera.zoom)

        if rocket.throttle > 0 and rocket.fuel > 0 then
            love.graphics.setColor(1, 0.5, 0.1)
            local flameLen = (40 * rocket.throttle + math.random(0, 10)) / camera.zoom
            love.graphics.polygon("fill", -30 / camera.zoom, -7 / camera.zoom, (-30 / camera.zoom) - flameLen, 0, -30 / camera.zoom, 7 / camera.zoom)
        end

        love.graphics.pop()
    end

    love.graphics.pop()

    -- --- HUD ---
    love.graphics.setColor(1, 1, 1)
    if rocket.isDestroyed then
        love.graphics.printf("VESSEL DESTROYED!\nPress 'R' to Restart", 0, 300, 1000, "center")
    else
        local currentBody = (distMoon < moon.soi) and "Moon (Mun)" or "Planet (Home)"
        love.graphics.print("Sphere of Influence: " .. currentBody, 10, 10)
        love.graphics.print("Altitude: " .. string.format("%.1f m", altPlanet), 10, 30)
        love.graphics.print("Speed: " .. string.format("%.1f m/s", speed), 10, 45)
        love.graphics.print("Throttle: " .. math.floor(rocket.throttle * 100) .. "% [Z/X]", 10, 65)

        love.graphics.print("Fuel:", 10, 90)
        love.graphics.setColor(0.2, 0.2, 0.2)
        love.graphics.rectangle("fill", 50, 92, 120, 12)
        love.graphics.setColor(0.2, 0.8, 0.3)
        love.graphics.rectangle("fill", 50, 92, (rocket.fuel / rocket.maxFuel) * 120, 12)
    end
end