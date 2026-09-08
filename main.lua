-- Pixel Canvas Setup (640x360)
local GAME_WIDTH = 640
local GAME_HEIGHT = 360

local canvas
local capsule = {
    x = GAME_WIDTH / 2,
    y = GAME_HEIGHT / 2,
    radius = 20,           
    angle = 0,             
    speed = 7500,          
    altitude = 55000,      
    angleAoA = 0,
    isBlunt = true
}

local airParticles = {}
local MAX_AIR_PARTICLES = 2000 

function love.load()
    love.window.setTitle("Gas Trails & Dynamic Base Collisions")
    love.window.setMode(1280, 720)

    canvas = love.graphics.newCanvas(GAME_WIDTH, GAME_HEIGHT)
    canvas:setFilter("nearest", "nearest")
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setLineStyle("rough")
end

function love.keypressed(key)
    if key == "space" then
        capsule.isBlunt = not capsule.isBlunt
    elseif key == "r" then
        capsule.altitude = 55000
        capsule.speed = 7500
        capsule.angleAoA = 0
        airParticles = {}
    end
end

function love.update(dt)
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

        local localX = dx * math.cos(-currentAngle) - dy * math.sin(-currentAngle)
        local localY = dx * math.sin(-currentAngle) + dy * math.cos(-currentAngle)
        
        -- Calculate local wind velocity to see if air is hitting the front or the back
        local localVx = p.vx * math.cos(-currentAngle) - p.vy * math.sin(-currentAngle)

        local isColliding = false
        local nx, ny = 0, 0
        
        -- These define how the fluid behaves depending on WHAT surface it hits
        local compressionHeat = 0.001
        local outwardPressure = 15
        local slipFriction = 0.98

        if capsule.isBlunt then
            if dist < capsule.radius then
                isColliding = true
                nx = dx / dist
                ny = dy / dist
                
                p.x = capsule.x + nx * (capsule.radius + 0.5)
                p.y = capsule.y + ny * (capsule.radius + 0.5)
                
                outwardPressure = p.temp * 15
            end
        else
            if localX >= -14 and localX <= 16 then
                local allowedWidth = (1.0 - ((localX + 14) / 30)) * 10
                if math.abs(localY) < allowedWidth + 1.5 then
                    isColliding = true
                    
                    -- If wind is moving left-to-right locally AND we are near the back, we hit the flat base
                    if localVx > 0 and localX < -8 then
                        local localNx = -1
                        local localNy = 0
                        
                        nx = localNx * math.cos(currentAngle) - localNy * math.sin(currentAngle)
                        ny = localNx * math.sin(currentAngle) + localNy * math.cos(currentAngle)

                        local rotatedSnapX = -14.5 * math.cos(currentAngle) - localY * math.sin(currentAngle)
                        local rotatedSnapY = -14.5 * math.sin(currentAngle) + localY * math.cos(currentAngle)
                        
                        p.x = capsule.x + rotatedSnapX
                        p.y = capsule.y + rotatedSnapY
                        
                        -- Base behaves exactly like a blunt heat shield
                        compressionHeat = 0.001
                        outwardPressure = p.temp * 15
                        slipFriction = 0.85
                    else
                        -- Hitting the slanted slicing sides
                        local sideSign = localY >= 0 and 1 or -1
                        local localNx = 0.316
                        local localNy = 0.948 * sideSign
                        
                        nx = localNx * math.cos(currentAngle) - localNy * math.sin(currentAngle)
                        ny = localNx * math.sin(currentAngle) + localNy * math.cos(currentAngle)

                        local snapY = (allowedWidth + 0.5) * sideSign
                        local rotatedSnapX = localX * math.cos(currentAngle) - snapY * math.sin(currentAngle)
                        local rotatedSnapY = localX * math.sin(currentAngle) + snapY * math.cos(currentAngle)
                        
                        p.x = capsule.x + rotatedSnapX
                        p.y = capsule.y + rotatedSnapY
                        
                        -- Sharp sides create less heat and slice the fluid easily
                        compressionHeat = 0.0006
                        outwardPressure = p.temp * 4
                        slipFriction = 0.99
                    end
                end
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
        if p.life <= 0 or dist > 400 then
            table.remove(airParticles, i)
        end
    end
end

function love.draw()
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
            -- DRAW PLASMA STREAM
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
            -- DRAW EXPANDING GAS TRAIL (Post-Plasma)
            love.graphics.setBlendMode("alpha")
            local gasAlpha = p.life * 0.3
            -- Gas expands as it ages (p.life goes from 1.0 down to 0)
            local gasSize = 1.5 + (1.0 - p.life) * 8 
            love.graphics.setColor(0.65, 0.7, 0.75, gasAlpha) 
            love.graphics.circle("fill", p.x, p.y, gasSize)
        else
            -- DRAW COLD INCOMING AIR
            love.graphics.setBlendMode("alpha")
            love.graphics.setColor(r, g, b, a)
            love.graphics.points(math.floor(p.x), math.floor(p.y))
        end
    end
    
    love.graphics.setBlendMode("alpha") 

    love.graphics.push()
    love.graphics.translate(capsule.x, capsule.y)
    love.graphics.rotate(capsule.angle + capsule.angleAoA)

    if capsule.isBlunt then
        drawBluntCapsule()
    else
        drawSharpCone()
    end

    love.graphics.pop()
    love.graphics.pop()
    love.graphics.setCanvas()

    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, 0, 0, 0, 2, 2)

    love.graphics.print("DYNAMIC CONE BASE & GAS TRAILS", 10, 10)
    love.graphics.print("Hold 'A' or 'D' to turn the nose into the wind", 10, 30)
end

function drawBluntCapsule()
    love.graphics.setColor(0.8, 0.8, 0.85)
    love.graphics.polygon("fill", -14, -8, -14, 8, 2, 14, 2, -14)

    love.graphics.setColor(0.12, 0.12, 0.15)
    love.graphics.arc("fill", 2, 0, 14, -math.pi/2, math.pi/2)

    love.graphics.setColor(0.3, 0.8, 0.95)
    love.graphics.rectangle("fill", -10, -3, 4, 6)
end

function drawSharpCone()
    love.graphics.setColor(0.85, 0.85, 0.9)
    love.graphics.polygon("fill", -14, -10, -14, 10, 16, 0)
end

