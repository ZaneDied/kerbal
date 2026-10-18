local reentryEnv = {}

local GAME_WIDTH = 640
local GAME_HEIGHT = 360

local canvas
local capsule = {
    x = GAME_WIDTH / 2,
    y = GAME_HEIGHT / 2,
    angle = 0,             
    speed = 7500,          
    altitude = 55000,      
    angleAoA = 0
}

local rocketBounds = {
    minX = 0, minY = 0, maxX = 24, maxY = 40,
    centerX = 12, centerY = 20,
    width = 24, height = 40
}

local airParticles = {}
local MAX_AIR_PARTICLES = 2000 
local rocketData = nil

function reentryEnv.load()
    canvas = love.graphics.newCanvas(GAME_WIDTH, GAME_HEIGHT)
    canvas:setFilter("nearest", "nearest")
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")

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

    -- Calculate exact tight bounding box of the custom rocket
    if rocketData and rocketData.parts and #rocketData.parts > 0 then
        local minX, minY, maxX, maxY = 99999, 99999, -99999, -99999
        for _, p in ipairs(rocketData.parts) do
            minX = math.min(minX, p.x)
            minY = math.min(minY, p.y)
            maxX = math.max(maxX, p.x + p.width)
            maxY = math.max(maxY, p.y + p.height)
        end
        rocketBounds.minX = minX
        rocketBounds.minY = minY
        rocketBounds.maxX = maxX
        rocketBounds.maxY = maxY
        rocketBounds.centerX = minX + (maxX - minX) / 2
        rocketBounds.centerY = minY + (maxY - minY) / 2
        rocketBounds.width = maxX - minX
        rocketBounds.height = maxY - minY
    end

    reentryEnv.reset()
end

function reentryEnv.reset()
    capsule.altitude = 55000
    capsule.speed = 7500
    capsule.angleAoA = 0
    airParticles = {}
end

function reentryEnv.keypressed(key)
    if key == "r" then
        reentryEnv.reset()
    end
end

function reentryEnv.update(dt)
    if love.keyboard.isDown("a") or love.keyboard.isDown("left") then
        capsule.angleAoA = capsule.angleAoA - 1.8 * dt
    elseif love.keyboard.isDown("d") or love.keyboard.isDown("right") then
        capsule.angleAoA = capsule.angleAoA + 1.8 * dt
    end

    if love.keyboard.isDown("w") or love.keyboard.isDown("up") then
        capsule.speed = math.min(10000, capsule.speed + 1200 * dt)
    elseif love.keyboard.isDown("s") or love.keyboard.isDown("down") then
        capsule.speed = math.max(100, capsule.speed - 1200 * dt)
    end

    capsule.altitude = math.max(0, capsule.altitude - capsule.speed * 0.15 * dt)
    local scaleHeight = 7500
    local maxDensity = 1.225
    local airDensity = maxDensity * math.exp(-capsule.altitude / scaleHeight)

    local dragAcc = 0.00008 * airDensity * (capsule.speed * capsule.speed)
    capsule.speed = math.max(150, capsule.speed - dragAcc * dt)

    local currentAngle = capsule.angle + capsule.angleAoA
    local trajectoryAngle = 0 
    local spawnRate = math.floor(airDensity * (capsule.speed / 15))

    for i = 1, spawnRate do
        if #airParticles < MAX_AIR_PARTICLES then
            local spawnDist = 220
            local sideOffset = (math.random() - 0.5) * 120

            local spawnX = capsule.x + math.cos(trajectoryAngle) * spawnDist - math.sin(trajectoryAngle) * sideOffset
            local spawnY = capsule.y + math.sin(trajectoryAngle) * spawnDist + math.cos(trajectoryAngle) * sideOffset

            local windVx = -math.cos(trajectoryAngle) * (capsule.speed * 0.22)
            local windVy = -math.sin(trajectoryAngle) * (capsule.speed * 0.22)

            table.insert(airParticles, {
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

    for i = #airParticles, 1, -1 do
        local p = airParticles[i]

        local nextX = p.x + p.vx * dt
        local nextY = p.y + p.vy * dt

        local dx = nextX - capsule.x
        local dy = nextY - capsule.y
        local dist = math.sqrt(dx * dx + dy * dy)

        -- Transform particle position into local rocket space
        local localX = dx * math.cos(-currentAngle) - dy * math.sin(-currentAngle)
        local localY = dx * math.sin(-currentAngle) + dy * math.cos(-currentAngle)

        local isColliding = false
        local nx, ny = 0, 0

        local compressionHeat = 0.001
        local outwardPressure = 15
        local slipFriction = 0.92

        -- Exact tight rectangular bounds matching the built rocket's dimensions
        local boxMinX = rocketBounds.minX - rocketBounds.centerX - 1
        local boxMaxX = rocketBounds.maxX - rocketBounds.centerX + 1
        local boxMinY = rocketBounds.minY - rocketBounds.centerY - 1
        local boxMaxY = rocketBounds.maxY - rocketBounds.centerY + 1

        if localX >= boxMinX and localX <= boxMaxX and localY >= boxMinY and localY <= boxMaxY then
            isColliding = true

            -- Determine which edge of the rocket hull the particle hit
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

            -- Convert local surface normal back to world space
            nx = localNx * math.cos(currentAngle) - localNy * math.sin(currentAngle)
            ny = localNx * math.sin(currentAngle) + localNy * math.cos(currentAngle)
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
        if p.life <= 0 or dist > 400 then
            table.remove(airParticles, i)
        end
    end
end

local function hasDecouplerBelow(targetPart, partsList)
    for _, p in ipairs(partsList) do
        if p ~= targetPart and math.abs(p.x + p.width/2 - (targetPart.x + targetPart.width/2)) <= 2 then
            if targetPart.y + targetPart.height == p.y and p.category == "decoupler" then
                return true
            end
        end
    end
    return false
end

function reentryEnv.draw()
    local maxDensity = 1.225
    local currentDensity = maxDensity * math.exp(-capsule.altitude / 7500)
    local shakeIntensity = (capsule.speed / 8000) * currentDensity * 3.5
    local camX = (math.random() - 0.5) * shakeIntensity
    local camY = (math.random() - 0.5) * shakeIntensity

    love.graphics.setCanvas(canvas)
    love.graphics.push()
    love.graphics.translate(camX, camY)

    local skyFactor = math.max(0, 1.0 - (capsule.altitude / 80000))
    love.graphics.clear(0.005 + skyFactor * 0.04, 0.01 + skyFactor * 0.1, 0.02 + skyFactor * 0.2)

    for _, p in ipairs(airParticles) do
        local r, g, b, a = 1, 1, 1, p.life
        local lineWidth = 1

        if p.temp > 0.8 then
            r, g, b = 1.0, 0.95, 0.7   
            lineWidth = 3
        elseif p.temp > 0.5 then
            r, g, b = 1.0, 0.4, 0.0    
            lineWidth = 2.5
        elseif p.temp > 0.25 then
            r, g, b = 1.0, 0.05, 0.1   
            lineWidth = 2
            a = p.life * 0.9
        elseif p.temp > 0.05 then
            r, g, b = 0.5, 0.0, 0.0    
            lineWidth = 1.5
            a = p.life * 0.7
        else
            r, g, b = 0.2, 0.4, 0.8    
            a = p.life * 0.15
        end

        if p.temp > 0.05 then
            love.graphics.setBlendMode("add")

            local streakLength = 0.02 + (p.temp * 0.045)
            local endX = p.x - p.vx * streakLength
            local endY = p.y - p.vy * streakLength

            if p.temp > 0.3 then
                love.graphics.setColor(r, g, b, a * 0.3)
                love.graphics.setLineWidth(lineWidth * 2.5)
                love.graphics.line(p.x, p.y, endX, endY)
            end

            love.graphics.setColor(r, g, b, a)
            love.graphics.setLineWidth(lineWidth)
            love.graphics.line(p.x, p.y, endX, endY)

            if p.temp > 0.4 and math.random() > 0.85 then
                love.graphics.setColor(1, 1, 1, a)
                love.graphics.points(p.x + math.random(-2, 2), p.y + math.random(-2, 2))
            end
        elseif p.hasHit then
            love.graphics.setBlendMode("alpha")
            local gasAlpha = p.life * 0.3
            local gasSize = 1.5 + (1.0 - p.life) * 8 
            love.graphics.setColor(0.65, 0.7, 0.75, gasAlpha) 
            love.graphics.circle("fill", p.x, p.y, gasSize)
        else
            love.graphics.setBlendMode("alpha")
            love.graphics.setColor(r, g, b, a)
            love.graphics.points(math.floor(p.x), math.floor(p.y))
        end
    end

    love.graphics.setBlendMode("alpha") 

    -- --- DRAW THE CUSTOM ROCKET CENTERED ---
    love.graphics.push()
    love.graphics.translate(capsule.x, capsule.y)
    love.graphics.rotate(capsule.angle + capsule.angleAoA)

    if rocketData and rocketData.parts and #rocketData.parts > 0 then
        love.graphics.push()
        love.graphics.translate(-rocketBounds.centerX, -rocketBounds.centerY)
        
        for _, p in ipairs(rocketData.parts) do
            love.graphics.push()
            love.graphics.translate(p.x, p.y)
            drawPartGraphic({ category = p.category, width = p.width, height = p.height }, p.side)
            
            if p.category == "engine" and hasDecouplerBelow(p, rocketData.parts) then
                drawEngineFairing(0, 0, p.width, p.height)
            end

            love.graphics.pop()
        end
        
        love.graphics.pop()
    else
        love.graphics.setColor(1, 1, 1, 0.5)
        love.graphics.print("No rocket loaded!", -40, -10)
    end

    love.graphics.pop()
    love.graphics.pop()
    love.graphics.setCanvas()

    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, 0, 0, 0, 2, 2)

    love.graphics.print("RE-ENTRY SIMULATION", 10, 10)
    love.graphics.print(string.format("Altitude: %.0fm | Speed: %.0fm/s", capsule.altitude, capsule.speed), 10, 30)
    love.graphics.print("Controls: Hold [A] or [D] to turn nose | [R] Reset", 10, 50)
end

local function drawEngineFairing(x, y, w, h)
    love.graphics.push()
    love.graphics.setColor(0.75, 0.78, 0.82)
    love.graphics.polygon("fill", 
        x - 2, y,               
        x + w + 2, y,           
        x + w + 4, y + h + 6,   
        x - 4, y + h + 6        
    )
    love.graphics.setColor(0.5, 0.55, 0.6)
    love.graphics.line(x + w/2, y, x + w/2, y + h + 6)
    love.graphics.pop()
end

local function drawPartGraphic(template, side)
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

    elseif template.color == "heatShield" or template.category == "heatShield" then
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

return reentryEnv