-- Pixel Resolution (640x360)
local GAME_WIDTH = 640
local GAME_HEIGHT = 360

local canvas
local rocket = {
    x = GAME_WIDTH / 2,
    y = GAME_HEIGHT / 2,
    angle = 0,               -- Pointing straight right
    throttle = 0
}

-- Particle system array
local particles = {}
local MAX_PARTICLES = 600

function love.load()
    love.window.setTitle("Engine Test Stand - Particle Preview")
    love.window.setMode(1280, 720)

    canvas = love.graphics.newCanvas(GAME_WIDTH, GAME_HEIGHT)
    canvas:setFilter("nearest", "nearest")
    love.graphics.setDefaultFilter("nearest", "nearest")
end

function love.update(dt)
    -- --- THROTTLE CONTROLS ---
    if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
        rocket.throttle = math.min(1, rocket.throttle + 2.0 * dt)
    elseif love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") then
        rocket.throttle = math.max(0, rocket.throttle - 2.0 * dt)
    end
    if love.keyboard.isDown("z") then rocket.throttle = 1 end
    if love.keyboard.isDown("x") then rocket.throttle = 0 end

    -- --- SPAWN BURN / EXHAUST PARTICLES ---
    if rocket.throttle > 0 then
        local spawnCount = math.floor(12 * rocket.throttle)
        for i = 1, spawnCount do
            if #particles < MAX_PARTICLES then
                -- Engine nozzle position (Right behind the engine bell)
                local ex = rocket.x - math.cos(rocket.angle) * 18
                local ey = rocket.y - math.sin(rocket.angle) * 18
                
                -- Small random spread at origin
                ex = ex + (math.random() - 0.5) * 4
                ey = ey + (math.random() - 0.5) * 4

                -- Ejection velocity (Shoots backwards relative to rocket angle)
                local ejectSpeed = (180 + math.random(0, 120)) * rocket.throttle
                local spread = (math.random() - 0.5) * 0.25
                
                local pvx = -math.cos(rocket.angle + spread) * ejectSpeed
                local pvy = -math.sin(rocket.angle + spread) * ejectSpeed

                table.insert(particles, {
                    x = ex,
                    y = ey,
                    vx = pvx,
                    vy = pvy,
                    life = 1.0,
                    decay = 2.5 + math.random() * 2.0,
                    size = math.random(1, 3)
                })
            end
        end
    end

    -- --- UPDATE PARTICLES ---
    for i = #particles, 1, -1 do
        local p = particles[i]
        
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        
        -- Air resistance on particles
        p.vx = p.vx * 0.94
        p.vy = p.vy * 0.94

        p.life = p.life - p.decay * dt
        if p.life <= 0 then
            table.remove(particles, i)
        end
    end
end

function love.draw()
    -- --- 1. RENDER TO LOW-RES PIXEL CANVAS ---
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.04, 0.05, 0.1)

    -- Background Stars
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.points({
        {40, 50}, {120, 280}, {250, 70}, {380, 310}, {520, 140}, {600, 220},
        {90, 180}, {310, 190}, {480, 40}, {150, 330}, {570, 80}, {210, 20}
    })

    -- --- DRAW FIRE PARTICLES ---
    for _, p in ipairs(particles) do
        local r, g, b, a = 1, 1, 1, 1

        if p.life > 0.8 then
            r, g, b = 1, 1, 1         -- White-hot core
        elseif p.life > 0.5 then
            r, g, b = 1, 0.9, 0.35     -- Hot yellow
        elseif p.life > 0.2 then
            r, g, b = 1, 0.45, 0.1     -- Intense orange
        else
            r, g, b = 0.8, 0.15, 0.15   -- Cooling red fadeout
            a = (p.life / 0.2) * 0.8
        end

        love.graphics.setColor(r, g, b, a)

        if p.size == 1 then
            love.graphics.points(p.x, p.y)
        else
            love.graphics.rectangle("fill", math.floor(p.x), math.floor(p.y), p.size, p.size)
        end
    end

    -- --- DRAW ROCKET ON TEST STAND ---
    love.graphics.push()
    love.graphics.translate(rocket.x, rocket.y)
    love.graphics.rotate(rocket.angle)
    
    drawDetailedPixelRocket()
    
    love.graphics.pop()

    love.graphics.setCanvas()

    -- --- 2. SCALE TO WINDOW ---
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, 0, 0, 0, 2, 2)

    -- Telemetry HUD
    love.graphics.print("ENGINE TEST STAND", 10, 10)
    love.graphics.print("Throttle: " .. math.floor(rocket.throttle * 100) .. "%", 10, 30)
    love.graphics.print("Controls: Press [Z] for Full Thrust | [X] to Cut | [Shift/Ctrl] to adjust", 10, 50)
    love.graphics.print("Active Particles: " .. #particles, 10, 70)
end

function drawDetailedPixelRocket()
    -- Rocket Body
    love.graphics.setColor(0.85, 0.85, 0.9)
    love.graphics.rectangle("fill", -12, -6, 22, 12)
    
    love.graphics.setColor(1, 1, 1)
    love.graphics.rectangle("fill", -12, -6, 22, 2)
    
    love.graphics.setColor(0.65, 0.65, 0.7)
    love.graphics.rectangle("fill", -12, 4, 22, 2)

    -- Decoupler Ring
    love.graphics.setColor(0.2, 0.2, 0.25)
    love.graphics.rectangle("fill", -2, -6, 3, 12)

    -- Nose Cone
    love.graphics.setColor(0.85, 0.2, 0.2)
    love.graphics.rectangle("fill", 10, -5, 4, 10)
    love.graphics.rectangle("fill", 14, -4, 3, 8)
    love.graphics.rectangle("fill", 17, -2, 3, 4)
    love.graphics.rectangle("fill", 20, -1, 2, 2)

    -- Engine Bell Nozzle
    love.graphics.setColor(0.25, 0.25, 0.3)
    love.graphics.rectangle("fill", -15, -4, 3, 8)
    love.graphics.rectangle("fill", -18, -5, 3, 10)

    -- Window Glass
    love.graphics.setColor(0.1, 0.15, 0.2)
    love.graphics.rectangle("fill", 4, -3, 5, 6)
    love.graphics.setColor(0.3, 0.75, 0.95)
    love.graphics.rectangle("fill", 5, -2, 3, 4)

    -- Rear Fins
    love.graphics.setColor(0.7, 0.15, 0.15)
    love.graphics.polygon("fill", -12, -6, -6, -6, -15, -11, -16, -11)
    love.graphics.polygon("fill", -12, 6, -6, 6, -15, 11, -16, 11)
end