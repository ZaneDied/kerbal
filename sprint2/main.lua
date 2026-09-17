local GAME_WIDTH = 640
local GAME_HEIGHT = 360

local canvas

-- CATALOG (Matching pixel dimensions and visual style from reference)
local CATALOG = {
    { id = "cockpit", name = "Nose Cone Pod", width = 12, height = 22, category = "cockpit" },
    { id = "fuel",    name = "Fuel Tank",     width = 12, height = 22, category = "fuel" },
    { id = "engine",  name = "Engine Bell",   width = 12, height = 18, category = "engine" }
}

local placedParts = {}

-- Dragging State
local draggedPart = nil
local dragOffsetX = 0
local dragOffsetY = 0
local SNAP_THRESHOLD = 16 -- Pixel radius to trigger snap

function love.load()
    love.window.setTitle("Rocket Hangar - Node Snap Assembly")
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
        -- 1. Check Catalog selection
        for i, template in ipairs(CATALOG) do
            local btnX, btnY = 10, 40 + (i - 1) * 35
            if mx >= btnX and mx <= btnX + 130 and my >= btnY and my <= btnY + 28 then
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

        -- 2. Pick up existing placed part
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
        -- Right Click: Remove part
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

        if mx > 150 then
            local bestSnap = getBestSnapPosition(draggedPart)

            if bestSnap then
                -- Lock directly to another component's connection node
                draggedPart.x = bestSnap.x
                draggedPart.y = bestSnap.y
            end

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

-- --- SMART CONNECTION SNAP LOGIC ---
function getBestSnapPosition(part)
    local bestDist = SNAP_THRESHOLD
    local snapPos = nil

    for _, existing in ipairs(placedParts) do
        -- 1. Snap BOTTOM of dragged part to TOP of existing part
        local alignX = existing.x
        local snapY_top = existing.y - part.template.height
        local distTop = math.abs(part.x - alignX) + math.abs(part.y - snapY_top)

        if distTop < bestDist then
            bestDist = distTop
            snapPos = { x = alignX, y = snapY_top }
        end

        -- 2. Snap TOP of dragged part to BOTTOM of existing part
        local snapY_bottom = existing.y + existing.template.height
        local distBottom = math.abs(part.x - alignX) + math.abs(part.y - snapY_bottom)

        if distBottom < bestDist then
            bestDist = distBottom
            snapPos = { x = alignX, y = snapY_bottom }
        end
    end

    return snapPos
end

function love.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.04, 0.05, 0.1)

    -- Background Grid
    love.graphics.setColor(1, 1, 1, 0.03)
    for gridX = 150, GAME_WIDTH, 16 do
        love.graphics.line(gridX, 0, gridX, GAME_HEIGHT)
    end
    for gridY = 0, GAME_HEIGHT, 16 do
        love.graphics.line(150, gridY, GAME_WIDTH, gridY)
    end

    -- --- DRAW PLACED PARTS ---
    for _, p in ipairs(placedParts) do
        drawPart(p.template, p.x, p.y)
    end

    -- --- DRAW DRAGGED PART & SNAP GUIDE HIGHLIGHT ---
    if draggedPart then
        local snap = getBestSnapPosition(draggedPart)
        if snap then
            -- Highlight snap connection line
            love.graphics.setColor(0.2, 0.9, 0.4, 0.5)
            love.graphics.rectangle("line", snap.x - 1, snap.y - 1, draggedPart.template.width + 2, draggedPart.template.height + 2)
        end

        drawPart(draggedPart.template, draggedPart.x, draggedPart.y, true)
    end

    -- --- CATALOG PANEL ---
    love.graphics.setColor(0.1, 0.12, 0.18)
    love.graphics.rectangle("fill", 0, 0, 150, GAME_HEIGHT)
    love.graphics.setColor(0.25, 0.3, 0.4)
    love.graphics.line(150, 0, 150, GAME_HEIGHT)

    love.graphics.setColor(0.9, 0.9, 0.95)
    love.graphics.print("PARTS CATALOG", 10, 15)

    local mx, my = love.mouse.getPosition()
    mx, my = mx / 2, my / 2

    for i, template in ipairs(CATALOG) do
        local btnX, btnY = 10, 40 + (i - 1) * 35
        local isHover = (mx >= btnX and mx <= btnX + 130 and my >= btnY and my <= btnY + 28)

        if isHover then
            love.graphics.setColor(0.22, 0.28, 0.38)
        else
            love.graphics.setColor(0.15, 0.18, 0.25)
        end
        love.graphics.rectangle("fill", btnX, btnY, 130, 28)

        love.graphics.setColor(0.9, 0.9, 0.95)
        love.graphics.print("+ " .. template.name, btnX + 8, btnY + 7)
    end

    -- HUD
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("PART-SNAP ASSEMBLY HANGAR", 160, 10)
    love.graphics.setColor(0.6, 0.65, 0.7)
    love.graphics.print("Drag components near each other to lock together  |  [C] Clear", 160, GAME_HEIGHT - 18)

    love.graphics.setCanvas()

    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, 0, 0, 0, 2, 2)
end

function drawPart(template, x, y, isGhost)
    love.graphics.push()
    love.graphics.translate(x, y)

    if isGhost then
        love.graphics.setColor(1, 1, 1, 0.65)
    end

    if template.category == "cockpit" then
        love.graphics.setColor(0.85, 0.2, 0.2)
        love.graphics.rectangle("fill", 5, 0, 2, 2)
        love.graphics.rectangle("fill", 4, 2, 4, 3)
        love.graphics.rectangle("fill", 2, 5, 8, 3)
        love.graphics.rectangle("fill", 1, 8, 10, 4)

        love.graphics.setColor(0.85, 0.85, 0.9)
        love.graphics.rectangle("fill", 0, 12, 12, 10)

        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("fill", 0, 12, 2, 10)
        love.graphics.setColor(0.65, 0.65, 0.7)
        love.graphics.rectangle("fill", 10, 12, 2, 10)

        love.graphics.setColor(0.1, 0.15, 0.2)
        love.graphics.rectangle("fill", 3, 13, 6, 5)
        love.graphics.setColor(0.3, 0.75, 0.95)
        love.graphics.rectangle("fill", 4, 14, 4, 3)

    elseif template.category == "fuel" then
        love.graphics.setColor(0.85, 0.85, 0.9)
        love.graphics.rectangle("fill", 0, 0, 12, 22)

        love.graphics.setColor(1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, 2, 22)
        love.graphics.setColor(0.65, 0.65, 0.7)
        love.graphics.rectangle("fill", 10, 0, 2, 22)

        love.graphics.setColor(0.2, 0.2, 0.25)
        love.graphics.rectangle("fill", 0, 10, 12, 3)

    elseif template.category == "engine" then
        love.graphics.setColor(0.25, 0.25, 0.3)
        love.graphics.rectangle("fill", 2, 0, 8, 3)
        love.graphics.rectangle("fill", 1, 3, 10, 3)
        love.graphics.rectangle("fill", 0, 6, 12, 4)

        love.graphics.setColor(0.7, 0.15, 0.15)
        love.graphics.polygon("fill", 0, 0, 0, 8, -5, 14, -5, 16)
        love.graphics.polygon("fill", 12, 0, 12, 8, 17, 14, 17, 16)
    end

    love.graphics.pop()
end