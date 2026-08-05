-- Rocket State
local rocket = {
    x = 400,
    y = 500,
    vx = 0,
    vy = 0,
    angle = -math.pi / 2,  -- Pointing UP (-90 degrees)
    
    mass = 1000,           -- Dry mass (kg)
    fuel = 500,            -- Fuel mass (kg)
    maxFuel = 500,
    engineThrust = 300000, -- Thrust increased so TWR > 1
    throttle = 0,
    turnSpeed = 2.0
}

-- Environment
local gravity = 150        -- Adjusted gravity scale
local groundY = 500        -- Ground position

function love.load()
    love.window.setTitle("Spaceflight Simulator Starter")
    love.window.setMode(800, 600)
end

function love.update(dt)
    -- --- CONTROLS ---
    if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
        rocket.throttle = math.min(1, rocket.throttle + 0.8 * dt)
    elseif love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") then
        rocket.throttle = math.max(0, rocket.throttle - 0.8 * dt)
    end

    if love.keyboard.isDown("a") or love.keyboard.isDown("left") then
        rocket.angle = rocket.angle - rocket.turnSpeed * dt
    elseif love.keyboard.isDown("d") or love.keyboard.isDown("right") then
        rocket.angle = rocket.angle + rocket.turnSpeed * dt
    end

    -- --- PHYSICS ---
    local totalMass = rocket.mass + rocket.fuel
    
    local currentThrust = 0
    if rocket.fuel > 0 and rocket.throttle > 0 then
        currentThrust = rocket.engineThrust * rocket.throttle
        rocket.fuel = math.max(0, rocket.fuel - (40 * rocket.throttle) * dt)
    else
        rocket.throttle = 0
    end

    -- Thrust vectors
    local thrustX = math.cos(rocket.angle) * currentThrust
    local thrustY = math.sin(rocket.angle) * currentThrust
    
    -- Acceleration = Force / Mass
    local ax = thrustX / totalMass
    local ay = (thrustY / totalMass) + gravity

    -- Velocity & Position
    rocket.vx = rocket.vx + ax * dt
    rocket.vy = rocket.vy + ay * dt

    rocket.x = rocket.x + rocket.vx * dt
    rocket.y = rocket.y + rocket.vy * dt

    -- --- GROUND COLLISION ---
    if rocket.y >= groundY then
        rocket.y = groundY
        if rocket.vy > 0 then rocket.vy = 0 end
        rocket.vx = rocket.vx * 0.9 -- Ground friction
    end
end

function love.keypressed(key)
    if key == "z" then rocket.throttle = 1 end
    if key == "x" then rocket.throttle = 0 end
end

function love.draw()
    -- Sky & Ground
    love.graphics.setColor(0.05, 0.05, 0.1)
    love.graphics.rectangle("fill", 0, 0, 800, groundY + 10)
    
    love.graphics.setColor(0.2, 0.5, 0.2)
    love.graphics.rectangle("fill", 0, groundY + 10, 800, 90)

    -- Rocket
    love.graphics.push()
    love.graphics.translate(rocket.x, rocket.y)
    love.graphics.rotate(rocket.angle + math.pi/2)

    -- Body
    love.graphics.setColor(0.9, 0.9, 0.9)
    love.graphics.rectangle("fill", -6, -20, 12, 30)
    
    -- Nose
    love.graphics.setColor(0.8, 0.2, 0.2)
    love.graphics.polygon("fill", -6, -20, 0, -32, 6, -20)

    -- Exhaust Flame
    if rocket.throttle > 0 and rocket.fuel > 0 then
        love.graphics.setColor(1, 0.5, 0.1)
        local flameSize = 20 * rocket.throttle + math.random(0, 6)
        love.graphics.polygon("fill", -4, 10, 0, 10 + flameSize, 4, 10)
    end

    love.graphics.pop()

    -- HUD
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("Altitude: " .. math.floor(groundY - rocket.y), 10, 10)
    love.graphics.print("Throttle: " .. math.floor(rocket.throttle * 100) .. "% (Press Z for 100%)", 10, 30)
    
    -- Fuel Bar
    love.graphics.print("Fuel:", 10, 50)
    love.graphics.setColor(0.2, 0.2, 0.2)
    love.graphics.rectangle("fill", 50, 52, 100, 10)
    love.graphics.setColor(0.2, 0.8, 0.2)
    love.graphics.rectangle("fill", 50, 52, (rocket.fuel / rocket.maxFuel) * 100, 10)
end