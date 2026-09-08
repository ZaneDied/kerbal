local GAME_WIDTH = 640
local GAME_HEIGHT = 360

local canvas

-- PART CATALOG (Landers, Rover Chassis, Wheels, & Equipment)
local CATALOG = {
    -- LANDER BASE & LEGS
    { id = "lander_core", category = "lander",  name = "Lander Core",    height = 24, width = 36, cost = 1500 },
    { id = "lander_leg",  category = "lander",  name = "Landing Leg",    height = 20, width = 14, cost = 400 },

    -- ROVER CHASSIS & CABINS
    { id = "cabin_scout", category = "cabin",   name = "Scout Cabin",   height = 18, width = 22, cost = 800 },
    { id = "chassis_s",   category = "chassis", name = "Short Frame",   height = 8,  width = 30, cost = 250 },
    { id = "chassis_l",   category = "chassis", name = "Long Frame",    height = 8,  width = 50, cost = 450 },

    -- MOBILITY / WHEELS
    { id = "wheel_s",     category = "wheel",   name = "Rover Wheel",   height = 14, width = 14, cost = 200 },
    { id = "wheel_heavy", category = "wheel",   name = "Heavy Treads",  height = 20, width = 20, cost = 500 },

    -- POWER & UTILITY
    { id = "solar_array", category = "utility", name = "Solar Panel",   height = 6,  width = 28, cost = 350 },
    { id = "rtg_battery", category = "utility", name = "RTG Generator", height = 14, width = 12, cost = 900 },

    -- SCIENCE INSTRUMENTS
    { id = "robot_arm",   category = "science", name = "Sample Arm",    height = 16, width = 12, cost = 600 },
    { id = "comm_dish",   category = "science", name = "Comms Dish",    height = 18, width = 16, cost = 450 }
}

local placedParts = {}

-- Dragging State
local draggedPart = nil
local dragOffsetX = 0
local dragOffsetY = 0

function love.load()
    love.window.setTitle("Planetary Rover & Lander Assembly Hangar")
    love.window.setMode(1280, 720)

    canvas = love.graphics.newCanvas(GAME_WIDTH, GAME_HEIGHT)
    canvas:setFilter("nearest", "nearest")
    love.graphics.setDefaultFilter("nearest", "nearest")
end

function love.keypressed(key)
    if key == "c" then
        placedParts = {}
    end
end

function love.mousepressed(x, y, button)
    local mx, my = x / 2, y / 2

    if button == 1 then
        -- 1. Check if clicking on catalog button to spawn a draggable part
        for i, template in ipairs(CATALOG) do
            local btnX, btnY = 10, 36 + (i - 1) * 20
            if mx >= btnX and mx <= btnX + 130 and my >= btnY and my <= btnY + 16 then
                draggedPart = {
                    template = template,
                    x = mx - template.width / 2,
                    y = my - template.height / 2
                }
                dragOffsetX = template.width / 2
                dragOffsetY = template.height / 2
                return
            end
        end

        -- 2. Check if picking up an existing placed part from the grid
        for i = #placedParts, 1, -1 do
            local p = placedParts[i]
            if mx >= p.x and mx <= p.x + p.template.width and my >= p.y and my <= p.y + p.template.height then
                draggedPart = p
                dragOffsetX = mx - p.x
                dragOffsetY = my - p.y
                table.remove(placedParts, i)
                return
            end
        end
    elseif button == 2 then
        -- Right Click: Remove hovering placed part
        for i = #placedParts, 1, -1 do
            local p = placedParts[i]
            if mx >= p.x and mx <= p.x + p.template.width and my >= p.y and my <= p.y + p.template.height then
                table.remove(placedParts, i)
                return
            end
        end
    end
end

function love.mousereleased(x, y, button)
    if button == 1 and draggedPart then
        local mx, my = x / 2, y / 2

        -- Drop part onto assembly grid (if dropped outside catalog area)
        if mx > 150 then
            -- Snap to 10px grid
            draggedPart.x = math.floor((mx - dragOffsetX + 5) / 10) * 10
            draggedPart.y = math.floor((my - dragOffsetY + 5) / 10) * 10

            table.insert(placedParts, draggedPart)
        end

        draggedPart = nil
    end
end

function love.update(dt)
    if draggedPart then
        local mx, my = love.mouse.getPosition()
        draggedPart.x = (mx / 2) - dragOffsetX
        draggedPart.y = (my / 2) - dragOffsetY
    end
end

function love.draw()
    love.graphics.setCanvas(canvas)

    -- Reddish Dust Hangar Background
    love.graphics.clear(0.12, 0.09, 0.08)

    -- --- DRAW ASSEMBLY GRID ---
    love.graphics.setColor(1, 1, 1, 0.04)
    for gridX = 150, GAME_WIDTH, 10 do
        love.graphics.line(gridX, 0, gridX, GAME_HEIGHT)
    end
    for gridY = 0, GAME_HEIGHT, 10 do
        love.graphics.line(150, gridY, GAME_WIDTH, gridY)
    end

    -- Hangar Floor Platform
    love.graphics.setColor(0.22, 0.2, 0.22)
    love.graphics.rectangle("fill", 150, 310, GAME_WIDTH - 150, 50)
    love.graphics.setColor(0.35, 0.32, 0.35)
    love.graphics.rectangle("fill", 150, 310, GAME_WIDTH - 150, 2)

    -- --- DRAW PLACED PARTS ---
    local totalCost = 0
    for _, p in ipairs(placedParts) do
        drawComponent(p.template, p.x, p.y)
        totalCost = totalCost + p.template.cost
    end

    -- --- DRAW DRAGGED PART ---
    if draggedPart then
        drawComponent(draggedPart.template, draggedPart.x, draggedPart.y, true)
    end

    -- --- DRAW CATALOG UI PANEL ---
    love.graphics.setColor(0.15, 0.13, 0.15)
    love.graphics.rectangle("fill", 0, 0, 150, GAME_HEIGHT)
    love.graphics.setColor(0.3, 0.25, 0.28)
    love.graphics.line(150, 0, 150, GAME_HEIGHT)

    love.graphics.setColor(0.9, 0.85, 0.8)
    love.graphics.print("ROVER / LANDER CATALOG", 8, 10)

    local mx, my = love.mouse.getPosition()
    mx, my = mx / 2, my / 2

    for i, template in ipairs(CATALOG) do
        local btnX, btnY = 10, 36 + (i - 1) * 20
        local isHover = (mx >= btnX and mx <= btnX + 130 and my >= btnY and my <= btnY + 16)

        if isHover then
            love.graphics.setColor(0.35, 0.28, 0.25)
        else
            love.graphics.setColor(0.22, 0.18, 0.19)
        end
        love.graphics.rectangle("fill", btnX, btnY, 130, 16)

        love.graphics.setColor(0.85, 0.85, 0.9)
        love.graphics.print(template.name, btnX + 6, btnY + 2)
    end

    -- --- HUD & CONTROLS ---
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("ROVER & LANDER ASSEMBLY HANGAR", 160, 10)
    love.graphics.print("Components: " .. #placedParts .. "  |  Budget Cost: $" .. totalCost, 160, 26)
    love.graphics.setColor(0.65, 0.6, 0.6)
    love.graphics.print("Drag & Drop parts to build  |  Right-click to remove  |  [C] Clear", 160, GAME_HEIGHT - 18)

    love.graphics.setCanvas()

    -- Scale Canvas to Screen
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, 0, 0, 0, 2, 2)
end

function drawComponent(template, x, y, isGhost)
    if isGhost then
        love.graphics.setColor(1, 1, 1, 0.7)
    end

    if template.category == "lander" then
        if template.id == "lander_core" then
            -- Octagonal Gold Foil Lander Core
            love.graphics.setColor(0.85, 0.65, 0.15)
            love.graphics.rectangle("fill", x, y, template.width, template.height)
            love.graphics.setColor(0.3, 0.3, 0.35)
            love.graphics.rectangle("rectangle", x, y, template.width, template.height)
        elseif template.id == "lander_leg" then
            -- Hydraulic Piston Leg
            love.graphics.setColor(0.6, 0.6, 0.65)
            love.graphics.line(x, y, x + template.width, y + template.height)
            love.graphics.setColor(0.2, 0.2, 0.2)
            love.graphics.rectangle("fill", x + template.width - 4, y + template.height - 2, 8, 3)
        end

    elseif template.category == "cabin" then
        -- Rover Pressurized Cabin
        love.graphics.setColor(0.82, 0.84, 0.88)
        love.graphics.rectangle("fill", x, y, template.width, template.height)
        love.graphics.setColor(0.2, 0.65, 0.85)
        love.graphics.rectangle("fill", x + 3, y + 3, template.width - 6, template.height / 2)

    elseif template.category == "chassis" then
        -- Structural Frame
        love.graphics.setColor(0.35, 0.38, 0.42)
        love.graphics.rectangle("fill", x, y, template.width, template.height)
        love.graphics.setColor(0.2, 0.2, 0.22)
        for i = 2, template.width - 4, 6 do
            love.graphics.rectangle("fill", x + i, y + 2, 3, template.height - 4)
        end

    elseif template.category == "wheel" then
        -- Tire Treads & Rim
        love.graphics.setColor(0.12, 0.12, 0.14)
        love.graphics.circle("fill", x + template.width / 2, y + template.height / 2, template.width / 2)
        love.graphics.setColor(0.5, 0.52, 0.58)
        love.graphics.circle("fill", x + template.width / 2, y + template.height / 2, template.width / 4)

    elseif template.category == "utility" then
        if template.id == "solar_array" then
            -- Dark Blue Solar Cells
            love.graphics.setColor(0.1, 0.35, 0.75)
            love.graphics.rectangle("fill", x, y, template.width, template.height)
            love.graphics.setColor(0.8, 0.8, 0.9)
            for i = 4, template.width - 2, 6 do
                love.graphics.line(x + i, y, x + i, y + template.height)
            end
        else
            -- RTG Nuclear Generator
            love.graphics.setColor(0.4, 0.42, 0.45)
            love.graphics.rectangle("fill", x, y, template.width, template.height)
            love.graphics.setColor(0.85, 0.2, 0.1)
            love.graphics.rectangle("fill", x + 2, y + 2, template.width - 4, 3)
        end

    elseif template.category == "science" then
        if template.id == "robot_arm" then
            -- Articulated Robotic Arm
            love.graphics.setColor(0.75, 0.75, 0.8)
            love.graphics.line(x, y + template.height, x + template.width / 2, y + template.height / 2)
            love.graphics.line(x + template.width / 2, y + template.height / 2, x + template.width, y)
        else
            -- Parabolic Dish Antenna
            love.graphics.setColor(0.8, 0.82, 0.85)
            love.graphics.arc("fill", x + template.width / 2, y + template.height, template.width / 2, math.pi, math.pi * 2)
        end
    end
end