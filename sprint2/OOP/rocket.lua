local rocketEnv = {}

local GAME_WIDTH = 640
local GAME_HEIGHT = 360

local canvas
local rocketData = nil
local throttle = 0
local particles = {}
local MAX_PARTICLES = 800

function rocketEnv.load()
    canvas = love.graphics.newCanvas(GAME_WIDTH, GAME_HEIGHT)
    canvas:setFilter("nearest", "nearest")
    love.graphics.setDefaultFilter("nearest", "nearest")

    -- Load the saved rocket layout from the hangar
    if love.filesystem.getInfo("saved_rocket.lua") then
        local success, chunk = pcall(love.filesystem.load, "saved_rocket.lua")
        if success and chunk then
            rocketData = chunk()
        else
            rocketData = { parts = {}, stages = {} }
        end
    else
        rocketData = { parts = {}, stages = {} }
    end

    -- Initialize engine activation states:
    -- If an engine is assigned to a stage, it starts INACTIVE (active = false).
    -- If it has no stage (unstaged), it is active by default.
    if rocketData and rocketData.parts then
        for _, p in ipairs(rocketData.parts) do
            if p.category == "engine" or p.category == "miniEngine" then
                if p.stageIdx ~= nil then
                    p.active = false
                else
                    p.active = true
                end
            end
        end
    end

    throttle = 0
    particles = {}
end

function rocketEnv.keypressed(key)
    if key == "space" then
        rocketEnv.triggerNextStage()
    end
end

-- Staging logic: Activates engines or triggers decouplers, ignoring parachutes
function rocketEnv.triggerNextStage()
    if not rocketData or not rocketData.stages then return end
    
    -- Iterate through stages from bottom (Stage 1) to top (Stage 3)
    for i = #rocketData.stages, 1, -1 do
        local stageIdx = i
        
        -- Collect all rocket parts belonging to this stage
        local stageParts = {}
        for _, p in ipairs(rocketData.parts) do
            if p.stageIdx == stageIdx then
                table.insert(stageParts, p)
            end
        end
        
        if #stageParts > 0 then
            print("Triggering Stage: " .. rocketData.stages[i].name)
            
            for _, p in ipairs(stageParts) do
                if p.category == "parachute" then
                    print("Ignoring parachute activation per configuration.")
                elseif p.category == "engine" or p.category == "miniEngine" then
                    -- ACTIVATE THE ENGINE (Stays on the rocket and starts firing!)
                    p.active = true
                    p.stageIdx = nil -- Clear stage index so it won't re-trigger
                    print("Engine activated!")
                elseif p.category == "decoupler" or p.category == "radialDec" then
                    -- Remove decouplers when triggered
                    for idx, partInRocket in ipairs(rocketData.parts) do
                        if partInRocket.id == p.id then
                            table.remove(rocketData.parts, idx)
                            break
                        end
                    end
                end
            end
            
            -- Clear this stage's entry in saved stages list
            rocketData.stages[i].parts = {}
            break
        end
    end
end

function rocketEnv.update(dt)
    -- --- THROTTLE CONTROLS ---
    if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
        throttle = math.min(1, throttle + 2.0 * dt)
    elseif love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") then
        throttle = math.max(0, throttle - 2.0 * dt)
    end
    if love.keyboard.isDown("z") then throttle = 1 end
    if love.keyboard.isDown("x") then throttle = 0 end

    -- --- SPAWN EXHAUST PARTICLES ONLY FOR ACTIVE ENGINES ---
    if throttle > 0 and rocketData and rocketData.parts and #rocketData.parts > 0 then
        local minX, minY, maxX, maxY = 99999, 99999, -99999, -99999
        for _, p in ipairs(rocketData.parts) do
            minX = math.min(minX, p.x)
            minY = math.min(minY, p.y)
            maxX = math.max(maxX, p.x + p.width)
            maxY = math.max(maxY, p.y + p.height)
        end
        local centerX = minX + (maxX - minX) / 2
        local centerY = minY + (maxY - minY) / 2
        local drawOffsetX = (GAME_WIDTH / 2) - centerX
        local drawOffsetY = (GAME_HEIGHT / 2) - centerY

        for _, p in ipairs(rocketData.parts) do
            -- Only emit particles if it's an engine AND it has been activated via staging
            if (p.category == "engine" or p.category == "miniEngine") and p.active then
                local spawnCount = math.max(2, math.floor((p.width / 4) * throttle))
                for i = 1, spawnCount do
                    if #particles < MAX_PARTICLES then
                        local localOffsetX = math.random(2, p.width - 2)
                        local ex = drawOffsetX + p.x + localOffsetX
                        local ey = drawOffsetY + p.y + p.height

                        local ejectSpeed = (200 + math.random(0, 140)) * throttle
                        local spread = (math.random() - 0.5) * 0.35

                        table.insert(particles, {
                            x = ex,
                            y = ey,
                            vx = spread * 60,
                            vy = ejectSpeed,
                            life = 1.0,
                            decay = 2.0 + math.random() * 1.5,
                            size = math.random(1, 3)
                        })
                    end
                end
            end
        end
    end

    for i = #particles, 1, -1 do
        local p = particles[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vx = p.vx * 0.94
        p.vy = p.vy * 0.94
        p.life = p.life - p.decay * dt
        if p.life <= 0 then
            table.remove(particles, i)
        end
    end
end

function rocketEnv.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.04, 0.05, 0.1)

    -- Background Stars
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.points({
        {40, 50}, {120, 280}, {250, 70}, {380, 310}, {520, 140}, {600, 220},
        {90, 180}, {310, 190}, {480, 40}, {150, 330}, {570, 80}, {210, 20}
    })

    -- Draw Fire Particles
    for _, p in ipairs(particles) do
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
        if p.size == 1 then
            love.graphics.points(p.x, p.y)
        else
            love.graphics.rectangle("fill", math.floor(p.x), math.floor(p.y), p.size, p.size)
        end
    end

    -- --- AUTO-CENTER AND DRAW THE LOADED ROCKET ---
    if rocketData and rocketData.parts and #rocketData.parts > 0 then
        local minX, minY, maxX, maxY = 99999, 99999, -99999, -99999
        for _, p in ipairs(rocketData.parts) do
            minX = math.min(minX, p.x)
            minY = math.min(minY, p.y)
            maxX = math.max(maxX, p.x + p.width)
            maxY = math.max(maxY, p.y + p.height)
        end
        
        local centerX = minX + (maxX - minX) / 2
        local centerY = minY + (maxY - minY) / 2

        love.graphics.push()
        love.graphics.translate((GAME_WIDTH / 2) - centerX, (GAME_HEIGHT / 2) - centerY)
        
        for _, p in ipairs(rocketData.parts) do
            love.graphics.push()
            love.graphics.translate(p.x, p.y)
            drawPartGraphic({ category = p.category, width = p.width, height = p.height }, p.side)
            love.graphics.pop()
        end
        
        love.graphics.pop()
    else
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.print("No rocket loaded! Build & Save in Hangar (1)", GAME_WIDTH/2 - 140, GAME_HEIGHT/2)
    end

    love.graphics.setCanvas()

    -- Scale to Window
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, 0, 0, 0, 2, 2)

    -- HUD
    love.graphics.print("ENGINE TEST STAND", 10, 10)
    love.graphics.print("Throttle: " .. math.floor(throttle * 100) .. "%", 10, 30)
    love.graphics.print("Controls: [Z] Full Thrust | [X] Cut | [Shift/Ctrl] Adjust | [Space] Stage (Activate Engines)", 10, 50)
    love.graphics.print("Active Particles: " .. #particles, 10, 70) -- FIXED: Changed '+' to '..'
end

function drawPartGraphic(template, side)
    if template.category == "cockpit" then
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

    elseif template.category == "fuel" then
        love.graphics.setColor(0.85, 0.85, 0.9)
        love.graphics.rectangle("fill", 0, 0, 24, 40)

        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, 3, 40)
        love.graphics.setColor(0.65, 0.65, 0.7)
        love.graphics.rectangle("fill", 21, 0, 3, 40)

        love.graphics.setColor(0.2, 0.2, 0.25)
        love.graphics.rectangle("fill", 0, 18, 24, 4)

    elseif template.category == "miniFuel" then
        love.graphics.setColor(0.8, 0.83, 0.88)
        love.graphics.rectangle("fill", 0, 0, 16, 24)

        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, 2, 24)
        love.graphics.setColor(0.6, 0.63, 0.68)
        love.graphics.rectangle("fill", 14, 0, 2, 24)

        love.graphics.setColor(0.2, 0.2, 0.25)
        love.graphics.rectangle("fill", 0, 11, 16, 2)

    elseif template.category == "decoupler" then
        love.graphics.setColor(0.3, 0.3, 0.35)
        love.graphics.rectangle("fill", 0, 0, 24, 12)
        love.graphics.setColor(0.8, 0.7, 0.2)
        love.graphics.rectangle("fill", 4, 4, 16, 4)

    elseif template.category == "radialDec" then
        love.graphics.setColor(0.35, 0.35, 0.4)
        love.graphics.rectangle("fill", 0, 0, 10, 16)
        love.graphics.setColor(0.9, 0.75, 0.15)
        love.graphics.rectangle("fill", 2, 5, 6, 6)

    elseif template.category == "cone" then
        love.graphics.setColor(0.85, 0.85, 0.9)
        love.graphics.polygon("fill", 12, 0, 24, 16, 0, 16)
        love.graphics.setColor(0.5, 0.55, 0.6)
        love.graphics.line(12, 0, 12, 16)

    elseif template.category == "heatShield" then
        love.graphics.setColor(0.2, 0.2, 0.22)
        love.graphics.rectangle("fill", 0, 2, 24, 6)
        love.graphics.setColor(0.6, 0.15, 0.1)
        love.graphics.rectangle("fill", 0, 0, 24, 2)

    elseif template.category == "engine" then
        love.graphics.setColor(0.25, 0.25, 0.3)
        love.graphics.rectangle("fill", 4, 0, 16, 8)

        love.graphics.setColor(0.7, 0.15, 0.15)
        love.graphics.polygon("fill", 4, 8, 20, 8, 24, 28, 0, 28)

    elseif template.category == "miniEngine" then
        love.graphics.setColor(0.3, 0.3, 0.35)
        love.graphics.rectangle("fill", 4, 0, 8, 5)

        love.graphics.setColor(0.6, 0.2, 0.2)
        love.graphics.polygon("fill", 4, 5, 12, 5, 16, 16, 0, 16)

    elseif template.category == "parachute" then
        love.graphics.setColor(0.9, 0.4, 0.1)
        love.graphics.rectangle("fill", 3, 0, 10, 3)
        love.graphics.rectangle("fill", 2, 3, 12, 5)
        love.graphics.setColor(0.85, 0.85, 0.9)
        love.graphics.rectangle("fill", 4, 8, 8, 4)
    end
end

return rocketEnv