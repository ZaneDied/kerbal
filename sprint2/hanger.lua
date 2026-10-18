local GAME_WIDTH = 1280
local GAME_HEIGHT = 720

-- Selected Category
local selectedCategory = "Pods"
local categories = {"Pods", "Fuel", "Engines", "Utility"}

-- Parts Catalog
local CATALOG = {
    Pods = {
        { id = "cockpit",   name = "Command Pod",   width = 24, height = 32, category = "cockpit" }
    },
    Fuel = {
        { id = "fuel",      name = "Fuel Tank",     width = 24, height = 40, category = "fuel" },
        { id = "miniFuel",  name = "Mini Fuel Tank",width = 16, height = 24, category = "miniFuel" }
    },
    Engines = {
        { id = "engine",    name = "Engine Bell",   width = 24, height = 28, category = "engine" },
        { id = "miniEngine",name = "Mini Rocket",   width = 16, height = 16, category = "miniEngine" }
    },
    Utility = {
        { id = "decoupler", name = "Decoupler Ring",width = 24, height = 12, category = "decoupler" },
        { id = "radialDec", name = "Radial Decoupler", width = 10, height = 16, category = "radialDec" },
        { id = "cone",      name = "Aero Cone",     width = 24, height = 16, category = "cone" },
        { id = "heatShield",name = "Heat Shield",   width = 24, height = 8,  category = "heatShield" },
        { id = "parachute", name = "Parachute Cap", width = 16, height = 12, category = "parachute" }
    }
}

-- Only stageable categories allowed in the PARTS list
local stageableWhitelist = {
    engine = true,
    miniEngine = true,
    decoupler = true,
    radialDec = true,
    parachute = true
}

local partDisplayNames = {
    engine = "Engine Bell",
    miniEngine = "Mini Rocket",
    decoupler = "Decoupler Ring",
    radialDec = "Radial Decoupler",
    parachute = "Parachute Cap"
}

local placedParts = {}
local stages = { 
    {id = 1, name = "Stage 3", parts = {}}, 
    {id = 2, name = "Stage 2", parts = {}}, 
    {id = 3, name = "Stage 1", parts = {}} 
}

-- Unique Counter for Part IDs
local nextPartId = 1

-- Selection State for Specific Part Instances
local selectedPartId = nil

-- Dragging State
local draggedPart = nil
local draggedSubAssembly = {}
local dragOffsetX = 0
local dragOffsetY = 0
local SNAP_THRESHOLD = 20

-- Dragging State for staging blocks (PARTS list <-> stage slots)
local draggedBlock = nil

-- Right sidebar layout
local MAX_PARTS_VISIBLE = 6
local PARTS_ITEM_H = 24
local PARTS_ITEM_STEP = 28
local STAGE_SLOT_H = 110
local STAGE_SLOT_STEP = 115
local CHIP_W = 110
local CHIP_H = 20

function love.load()
    love.window.setTitle("Pixel Rocket Hangar & VAB")
    love.window.setMode(GAME_WIDTH, GAME_HEIGHT, { resizable = true, vsync = true })
    love.graphics.setDefaultFilter("nearest", "nearest")
end

function love.keypressed(key)
    if key == "c" then
        placedParts = {}
        selectedPartId = nil
        nextPartId = 1
        rebuildStaging()
    elseif key == "space" then
        triggerNextStage()
    end
end

function getPlacedStageableInstances()
    local list = {}
    -- Keep track of counts per category to number them 1, 2, 3...
    local categoryCounts = {}
    for _, p in ipairs(placedParts) do
        local cat = p.template.category
        if stageableWhitelist[cat] then
            categoryCounts[cat] = (categoryCounts[cat] or 0) + 1
            table.insert(list, {
                part = p,
                displayLabel = (partDisplayNames[cat] or p.template.name) .. " " .. categoryCounts[cat]
            })
        end
    end
    return list
end

-- Stageable parts that are NOT assigned to a stage (shown in the PARTS list)
function getUnstagedInstances(all)
    local list = {}
    for _, entry in ipairs(all) do
        if not entry.part.stageIdx then
            table.insert(list, entry)
        end
    end
    return list
end

-- Geometry helpers for the stage slots / chips
function stageSlotRect(i)
    local xPos = GAME_WIDTH - 270
    return xPos + 15, 300 + (i - 1) * STAGE_SLOT_STEP, 230, STAGE_SLOT_H
end

function chipRect(stageSlot, k)
    local sx, sy = stageSlotRect(stageSlot)
    local col = (k - 1) % 2
    local row = math.floor((k - 1) / 2)
    return sx + 4 + col * (CHIP_W + 6), sy + 20 + row * (CHIP_H + 2), CHIP_W, CHIP_H
end

function stageSlotAt(x, y)
    for i = 1, 3 do
        local sx, sy, sw, sh = stageSlotRect(i)
        if x >= sx and x <= sx + sw and y >= sy and y <= sy + sh then
            return i
        end
    end
    return nil
end

function overPartsArea(x, y)
    local xPos = GAME_WIDTH - 270
    return x >= xPos and x <= xPos + 260 and y >= 60 and y <= 285
end

function love.mousepressed(x, y, button)
    if button == 1 then
        -- Check category button clicks in the left sidebar
        if x >= 20 and x <= 300 then
            local startY = 110
            for i, cat in ipairs(categories) do
                local btnY = startY + (i - 1) * 45
                if y >= btnY and y <= btnY + 38 then
                    selectedCategory = cat
                end
            end
        end

        -- Check parts list selection inside the left sidebar
        local partsListStartY = 310
        local currentParts = CATALOG[selectedCategory] or {}
        for i, template in ipairs(currentParts) do
            local itemY = partsListStartY + (i - 1) * 45
            if x >= 20 and x <= 300 and y >= itemY and y <= itemY + 38 then
                draggedPart = {
                    id = "part_" .. nextPartId,
                    template = template,
                    x = x - 320 - template.width / 2,
                    y = y - 60 - template.height / 2,
                    parent = nil,
                    side = "center",
                    stageIdx = nil
                }
                nextPartId = nextPartId + 1
                draggedSubAssembly = { draggedPart }
                dragOffsetX = template.width / 2
                dragOffsetY = template.height / 2
                return
            end
        end

        local rightSidebarX = GAME_WIDTH - 270
        local allInstances = getPlacedStageableInstances()

        -- Start dragging a block from the PARTS list
        local unstaged = getUnstagedInstances(allInstances)
        for i, entry in ipairs(unstaged) do
            if i > MAX_PARTS_VISIBLE then break end
            local itemY = 100 + (i - 1) * PARTS_ITEM_STEP
            if x >= rightSidebarX + 15 and x <= rightSidebarX + 245 and y >= itemY and y <= itemY + PARTS_ITEM_H then
                draggedBlock = { part = entry.part, label = entry.displayLabel, startX = x, startY = y }
                return
            end
        end

        -- Start dragging a block out of a stage slot
        for s = 1, 3 do
            local k = 0
            for _, entry in ipairs(allInstances) do
                if entry.part.stageIdx == s then
                    k = k + 1
                    local cx, cy, cw, ch = chipRect(s, k)
                    if x >= cx and x <= cx + cw and y >= cy and y <= cy + ch then
                        draggedBlock = { part = entry.part, label = entry.displayLabel, startX = x, startY = y }
                        return
                    end
                end
            end
        end

        -- Pick up already placed parts (and their attached sub-assembly children)
        for i = #placedParts, 1, -1 do
            local p = placedParts[i]
            local gridX = p.x + 320
            local gridY = p.y + 60
            if x >= gridX and x <= gridX + p.template.width and y >= gridY and y <= gridY + p.template.height then
                draggedPart = p
                dragOffsetX = x - gridX
                dragOffsetY = y - gridY

                draggedSubAssembly = {}
                collectSubAssembly(p, placedParts, draggedSubAssembly)

                for _, subPart in ipairs(draggedSubAssembly) do
                    for idx, existing in ipairs(placedParts) do
                        if existing == subPart then
                            table.remove(placedParts, idx)
                            break
                        end
                    end
                end

                if selectedPartId and not hasIdInPlaced(selectedPartId) then
                    selectedPartId = nil
                end

                rebuildStaging()
                return
            end
        end

        -- Right Sidebar Action Buttons (Stage / Clear)
        local btnY = GAME_HEIGHT - 65
        if x >= rightSidebarX + 15 and x <= rightSidebarX + 110 and y >= btnY and y <= btnY + 35 then
            triggerNextStage()
            return
        elseif x >= rightSidebarX + 120 and x <= rightSidebarX + 245 and y >= btnY and y <= btnY + 35 then
            placedParts = {}
            selectedPartId = nil
            nextPartId = 1
            rebuildStaging()
            return
        end

    elseif button == 2 then
        -- Right click to delete a part and its attached sub-assembly
        for i = #placedParts, 1, -1 do
            local p = placedParts[i]
            local gridX = p.x + 320
            local gridY = p.y + 60
            if x >= gridX and x <= gridX + p.template.width and y >= gridY and y <= gridY + p.template.height then
                local toRemove = {}
                collectSubAssembly(p, placedParts, toRemove)
                for _, rem in ipairs(toRemove) do
                    for idx, existing in ipairs(placedParts) do
                        if existing == rem then
                            table.remove(placedParts, idx)
                            break
                        end
                    end
                end
                if selectedPartId and not hasIdInPlaced(selectedPartId) then
                    selectedPartId = nil
                end
                rebuildStaging()
                return
            end
        end
    end
end

function hasIdInPlaced(targetId)
    for _, p in ipairs(placedParts) do
        if p.id == targetId then return true end
    end
    return false
end

function collectSubAssembly(rootPart, list, collection)
    table.insert(collection, rootPart)
    for _, p in ipairs(list) do
        if p.parent == rootPart then
            collectSubAssembly(p, list, collection)
        end
    end
end

function checkCollision(x, y, w, h, ignoreList)
    for _, p in ipairs(placedParts) do
        local isIgnored = false
        for _, ign in ipairs(ignoreList) do
            if p == ign then isIgnored = true end
        end
        if not isIgnored then
            if x < p.x + p.template.width - 2 and x + w > p.x + 2 and
               y < p.y + p.template.height - 2 and y + h > p.y + 2 then
                return true
            end
        end
    end
    return false
end

function love.mousereleased(x, y, button)
    -- Dropping a staging block
    if button == 1 and draggedBlock then
        local moved = math.abs(x - draggedBlock.startX) > 4 or math.abs(y - draggedBlock.startY) > 4
        local part = draggedBlock.part

        if not moved then
            -- Plain click: toggle selection
            if selectedPartId == part.id then
                selectedPartId = nil
            else
                selectedPartId = part.id
            end
        else
            local targetStage = stageSlotAt(x, y)
            if targetStage then
                part.stageIdx = targetStage
            elseif overPartsArea(x, y) then
                part.stageIdx = nil
            end
            -- dropped anywhere else: stays where it was
        end

        draggedBlock = nil
        rebuildStaging()
        return
    end

    if button == 1 and draggedPart then
        if x >= 320 and x <= GAME_WIDTH - 280 and y >= 60 and y <= GAME_HEIGHT - 60 then
            local gridLocalX = x - 320 - dragOffsetX
            local gridLocalY = y - 60 - dragOffsetY
            
            local dx = gridLocalX - draggedPart.x
            local dy = gridLocalY - draggedPart.y

            draggedPart.x = gridLocalX
            draggedPart.y = gridLocalY

            for _, subPart in ipairs(draggedSubAssembly) do
                if subPart ~= draggedPart then
                    subPart.x = subPart.x + dx
                    subPart.y = subPart.y + dy
                end
            end

            -- Snap the root part if applicable and collision-free
            local bestSnap, parentHost, attachedSide = getBestSnapPosition(draggedPart)
            if bestSnap then
                local snapDx = bestSnap.x - draggedPart.x
                local snapDy = bestSnap.y - draggedPart.y
                
                local willCollide = false
                for _, subPart in ipairs(draggedSubAssembly) do
                    local testX = subPart.x + snapDx
                    local testY = subPart.y + snapDy
                    if checkCollision(testX, testY, subPart.template.width, subPart.template.height, draggedSubAssembly) then
                        willCollide = true
                        break
                    end
                end

                if not willCollide then
                    draggedPart.x = bestSnap.x
                    draggedPart.y = bestSnap.y
                    draggedPart.parent = parentHost
                    draggedPart.side = attachedSide or "center"

                    for _, subPart in ipairs(draggedSubAssembly) do
                        if subPart ~= draggedPart then
                            subPart.x = subPart.x + snapDx
                            subPart.y = subPart.y + snapDy
                        end
                    end
                else
                    draggedPart.parent = nil
                    draggedPart.side = "center"
                end
            else
                draggedPart.parent = nil
                draggedPart.side = "center"
            end

            for _, subPart in ipairs(draggedSubAssembly) do
                table.insert(placedParts, subPart)
            end

            rebuildStaging()
        end
        draggedPart = nil
        draggedSubAssembly = {}
    end
end

function love.update(dt)
end

function isHostPart(templateCat)
    return templateCat == "fuel" or templateCat == "miniFuel" or templateCat == "cockpit"
end

function getBestSnapPosition(part)
    local bestDist = SNAP_THRESHOLD
    local snapPos = nil
    local parentHost = nil
    local attachedSide = "center"

    for _, existing in ipairs(placedParts) do
        local isSelf = false
        for _, sub in ipairs(draggedSubAssembly) do
            if existing == sub then isSelf = true end
        end

        if not isSelf then
            if part.template.category == "radialDec" and isHostPart(existing.template.category) then
                local alignY = existing.y + (existing.template.height / 2) - (part.template.height / 2)
                
                if math.abs(part.y - alignY) < 15 then
                    local tankCenterX = existing.x + (existing.template.width / 2)
                    local partCenterX = part.x + (part.template.width / 2)

                    if partCenterX < tankCenterX then
                        local snapX = existing.x - part.template.width
                        local dist = math.abs(part.x - snapX)
                        if dist < bestDist and not checkCollision(snapX, alignY, part.template.width, part.template.height, draggedSubAssembly) then
                            bestDist = dist
                            snapPos = { x = snapX, y = alignY }
                            parentHost = existing
                            attachedSide = "left"
                        end
                    else
                        local snapX = existing.x + existing.template.width
                        local dist = math.abs(part.x - snapX)
                        if dist < bestDist and not checkCollision(snapX, alignY, part.template.width, part.template.height, draggedSubAssembly) then
                            bestDist = dist
                            snapPos = { x = snapX, y = alignY }
                            parentHost = existing
                            attachedSide = "right"
                        end
                    end
                end

            elseif (part.template.category == "fuel" or part.template.category == "miniFuel") and existing.template.category == "radialDec" then
                local alignY = existing.y + (existing.template.height / 2) - (part.template.height / 2)
                
                if math.abs(part.y - alignY) < 15 then
                    local decCenterX = existing.x + (existing.template.width / 2)
                    local partCenterX = part.x + (part.template.width / 2)

                    if partCenterX < decCenterX then
                        local snapX = existing.x - part.template.width
                        local dist = math.abs(part.x - snapX)
                        if dist < bestDist and not checkCollision(snapX, alignY, part.template.width, part.template.height, draggedSubAssembly) then
                            bestDist = dist
                            snapPos = { x = snapX, y = alignY }
                            parentHost = existing
                            attachedSide = "left"
                        end
                    else
                        local snapX = existing.x + existing.template.width
                        local dist = math.abs(part.x - snapX)
                        if dist < bestDist and not checkCollision(snapX, alignY, part.template.width, part.template.height, draggedSubAssembly) then
                            bestDist = dist
                            snapPos = { x = snapX, y = alignY }
                            parentHost = existing
                            attachedSide = "right"
                        end
                    end
                end

            else
                local alignX = existing.x + (existing.template.width / 2) - (part.template.width / 2)
                
                local snapY_top = existing.y - part.template.height
                local distTop = math.abs(part.x - alignX) + math.abs(part.y - snapY_top)
                if distTop < bestDist and not checkCollision(alignX, snapY_top, part.template.width, part.template.height, draggedSubAssembly) then
                    bestDist = distTop
                    snapPos = { x = alignX, y = snapY_top }
                    parentHost = existing
                    attachedSide = "center"
                end

                local snapY_bottom = existing.y + existing.template.height
                local distBottom = math.abs(part.x - alignX) + math.abs(part.y - snapY_bottom)
                if distBottom < bestDist and not checkCollision(alignX, snapY_bottom, part.template.width, part.template.height, draggedSubAssembly) then
                    bestDist = distBottom
                    snapPos = { x = alignX, y = snapY_bottom }
                    parentHost = existing
                    attachedSide = "center"
                end
            end
        end
    end
    return snapPos, parentHost, attachedSide
end

-- Stages are now filled manually: each part carries a stageIdx (nil = in PARTS list)
function rebuildStaging()
    for _, stage in ipairs(stages) do
        stage.parts = {}
    end

    for _, p in ipairs(placedParts) do
        if p.stageIdx and stages[p.stageIdx] then
            table.insert(stages[p.stageIdx].parts, p)
        end
    end
end

function triggerNextStage()
    for i = #stages, 1, -1 do
        if #stages[i].parts > 0 then
            for _, stagePart in ipairs(stages[i].parts) do
                for idx, p in ipairs(placedParts) do
                    if p == stagePart then
                        table.remove(placedParts, idx)
                        break
                    end
                end
            end
            if selectedPartId and not hasIdInPlaced(selectedPartId) then
                selectedPartId = nil
            end
            rebuildStaging()
            break
        end
    end
end

function hasDecouplerBelow(targetPart)
    for _, p in ipairs(placedParts) do
        if p ~= targetPart and math.abs(p.x + p.template.width/2 - (targetPart.x + targetPart.template.width/2)) <= 2 then
            if targetPart.y + targetPart.template.height == p.y and p.template.category == "decoupler" then
                return true
            end
        end
    end
    return false
end

function love.draw()
    love.graphics.clear(0.12, 0.13, 0.16)

    drawTopBar()
    drawLeftSidebar()
    drawRightSidebar()
    drawBuildGrid()
    drawDraggedBlock()
end

function drawBuildGrid()
    local gridLeft = 320
    local gridTop = 60
    local gridRight = GAME_WIDTH - 280
    local gridBottom = GAME_HEIGHT - 60

    love.graphics.setColor(0.15, 0.17, 0.21)
    love.graphics.rectangle("fill", gridLeft, gridTop, gridRight - gridLeft, gridBottom - gridTop, 6, 6)

    love.graphics.setColor(1, 1, 1, 0.03)
    for x = gridLeft + 40, gridRight, 40 do
        love.graphics.line(x, gridTop, x, gridBottom)
    end
    for y = gridTop + 40, gridBottom, 40 do
        love.graphics.line(gridLeft, y, gridRight, y)
    end

    love.graphics.setColor(0.3, 0.5, 0.8, 0.15)
    love.graphics.setLineWidth(2)
    love.graphics.line((gridLeft + gridRight) / 2, gridTop + 10, (gridLeft + gridRight) / 2, gridBottom - 10)
    love.graphics.setLineWidth(1)

    love.graphics.push()
    love.graphics.translate(gridLeft, gridTop)
    for _, p in ipairs(placedParts) do
        love.graphics.push()
        love.graphics.translate(p.x, p.y)
        drawPartGraphic(p.template, p.side)
        
        -- Highlight specific selected part instance on the grid
        if selectedPartId and p.id == selectedPartId then
            love.graphics.setColor(0.3, 0.8, 1.0, 0.9)
            love.graphics.setLineWidth(2)
            love.graphics.rectangle("line", -2, -2, p.template.width + 4, p.template.height + 4, 2, 2)
            love.graphics.setLineWidth(1)
        end

        if p.template.category == "engine" and hasDecouplerBelow(p) then
            drawEngineFairing(0, 0, p.template.width, p.template.height)
        end

        love.graphics.pop()
    end

    if draggedPart then
        love.graphics.push()
        local currentMouseGridX = love.mouse.getX() - 320
        local currentMouseGridY = love.mouse.getY() - 60
        local rootTargetX = currentMouseGridX - dragOffsetX
        local rootTargetY = currentMouseGridY - dragOffsetY
        local dx = rootTargetX - draggedPart.x
        local dy = rootTargetY - draggedPart.y

        for _, subPart in ipairs(draggedSubAssembly) do
            love.graphics.push()
            love.graphics.translate(subPart.x + dx, subPart.y + dy)
            love.graphics.setColor(1, 1, 1, 0.75)
            drawPartGraphic(subPart.template, subPart.side)
            love.graphics.pop()
        end
        love.graphics.pop()
    end
    love.graphics.pop()

    love.graphics.setColor(0.25, 0.28, 0.35)
    love.graphics.rectangle("line", gridLeft, gridTop, gridRight - gridLeft, gridBottom - gridTop, 6, 6)
end

function drawEngineFairing(x, y, w, h)
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

function drawTopBar()
    love.graphics.setColor(0.09, 0.10, 0.13)
    love.graphics.rectangle("fill", 0, 0, GAME_WIDTH, 50)
    love.graphics.setColor(0.2, 0.22, 0.28)
    love.graphics.line(0, 50, GAME_WIDTH, 50)

    love.graphics.setColor(0.85, 0.88, 0.95)
    love.graphics.print("VAB: Untitled Space Craft", 20, 18)
end

function drawLeftSidebar()
    love.graphics.setColor(0.09, 0.10, 0.13)
    love.graphics.rectangle("fill", 10, 60, 300, GAME_HEIGHT - 70, 6, 6)
    love.graphics.setColor(0.2, 0.22, 0.28)
    love.graphics.rectangle("line", 10, 60, 300, GAME_HEIGHT - 70, 6, 6)

    love.graphics.setColor(0.9, 0.9, 0.95)
    love.graphics.print("PART CATEGORIES", 25, 75)

    local startY = 110
    for i, cat in ipairs(categories) do
        local btnY = startY + (i - 1) * 45
        local isSelected = (selectedCategory == cat)

        if isSelected then
            love.graphics.setColor(0.22, 0.35, 0.55)
        else
            love.graphics.setColor(0.15, 0.17, 0.22)
        end
        love.graphics.rectangle("fill", 20, btnY, 280, 38, 4, 4)

        love.graphics.setColor(isSelected and 1 or 0.8, isSelected and 1 or 0.8, isSelected and 1 or 0.85)
        love.graphics.print(cat, isSelected and 36 or 32, btnY + 12)
    end

    love.graphics.setColor(0.9, 0.9, 0.95)
    love.graphics.print(selectedCategory:upper() .. " PARTS", 25, 290)

    local partsListStartY = 310
    local currentParts = CATALOG[selectedCategory] or {}
    for i, template in ipairs(currentParts) do
        local itemY = partsListStartY + (i - 1) * 45
        love.graphics.setColor(0.16, 0.19, 0.25)
        love.graphics.rectangle("fill", 20, itemY, 280, 38, 4, 4)
        love.graphics.setColor(0.8, 0.85, 0.9)
        love.graphics.print("+ " .. template.name, 32, itemY + 12)
    end
end

-- A draggable block (used in the PARTS list, in stage slots, and under the cursor)
function drawBlock(x, y, w, h, label, selected, alpha)
    alpha = alpha or 1
    if selected then
        love.graphics.setColor(0.22, 0.35, 0.55, alpha)
    else
        love.graphics.setColor(0.2, 0.23, 0.30, alpha)
    end
    love.graphics.rectangle("fill", x, y, w, h, 4, 4)

    if selected then
        love.graphics.setColor(0.3, 0.7, 1.0, alpha)
    else
        love.graphics.setColor(0.4, 0.45, 0.55, alpha)
    end
    love.graphics.rectangle("line", x, y, w, h, 4, 4)

    love.graphics.setScissor(x + 2, y, w - 4, h)
    love.graphics.setColor(selected and 1 or 0.85, selected and 1 or 0.85, selected and 1 or 0.9, alpha)
    love.graphics.print(label, x + 6, y + (h - 12) / 2)
    love.graphics.setScissor()
end

function drawRightSidebar()
    local xPos = GAME_WIDTH - 270
    local mx, my = love.mouse.getPosition()
    local dragging = draggedBlock ~= nil

    love.graphics.setColor(0.09, 0.10, 0.13)
    love.graphics.rectangle("fill", xPos, 60, 260, GAME_HEIGHT - 70, 6, 6)
    love.graphics.setColor(0.2, 0.22, 0.28)
    love.graphics.rectangle("line", xPos, 60, 260, GAME_HEIGHT - 70, 6, 6)

    -- SECTION 1: PARTS (unstaged numbered instances)
    love.graphics.setColor(0.9, 0.9, 0.95)
    love.graphics.print("PARTS", xPos + 15, 75)

    -- Highlight the PARTS area as a drop target while dragging
    if dragging and overPartsArea(mx, my) then
        love.graphics.setColor(0.3, 0.8, 1.0, 0.8)
        love.graphics.rectangle("line", xPos + 8, 92, 244, 186, 4, 4)
    end

    local allInstances = getPlacedStageableInstances()
    local unstaged = getUnstagedInstances(allInstances)
    if #unstaged == 0 then
        love.graphics.setColor(0.5, 0.55, 0.6)
        if #allInstances == 0 then
            love.graphics.print("(No stageable parts)", xPos + 22, 105)
        else
            love.graphics.print("(All parts staged)", xPos + 22, 105)
        end
    else
        for i, entry in ipairs(unstaged) do
            if i > MAX_PARTS_VISIBLE then
                love.graphics.setColor(0.5, 0.55, 0.6)
                love.graphics.print("+" .. (#unstaged - MAX_PARTS_VISIBLE) .. " more...", xPos + 22, 100 + MAX_PARTS_VISIBLE * PARTS_ITEM_STEP)
                break
            end
            local itemY = 100 + (i - 1) * PARTS_ITEM_STEP
            local isSelected = (selectedPartId == entry.part.id)
            local isDragged = dragging and draggedBlock.part == entry.part
            drawBlock(xPos + 15, itemY, 230, PARTS_ITEM_H, entry.displayLabel, isSelected, isDragged and 0.3 or 1)
        end
    end

    -- SECTION 2: STAGES
    love.graphics.setColor(0.9, 0.9, 0.95)
    love.graphics.print("STAGES", xPos + 15, 275)

    local hoverStage = dragging and stageSlotAt(mx, my) or nil

    for i = 1, 3 do
        local sx, sy, sw, sh = stageSlotRect(i)
        love.graphics.setColor(0.14, 0.16, 0.20)
        love.graphics.rectangle("fill", sx, sy, sw, sh, 4, 4)

        if hoverStage == i then
            love.graphics.setColor(0.3, 0.8, 1.0, 0.9)
            love.graphics.setLineWidth(2)
        else
            love.graphics.setColor(0.3, 0.35, 0.45)
        end
        love.graphics.rectangle("line", sx, sy, sw, sh, 4, 4)
        love.graphics.setLineWidth(1)

        love.graphics.setColor(0.7, 0.75, 0.8)
        local count = #stages[i].parts
        love.graphics.print("Stage " .. (4 - i) .. " (" .. count .. " parts)", sx + 7, sy + 4)

        -- Blocks assigned to this stage
        local k = 0
        for _, entry in ipairs(allInstances) do
            if entry.part.stageIdx == i then
                k = k + 1
                if k > 8 then break end
                local cx, cy, cw, ch = chipRect(i, k)
                local isSelected = (selectedPartId == entry.part.id)
                local isDragged = dragging and draggedBlock.part == entry.part
                drawBlock(cx, cy, cw, ch, entry.displayLabel, isSelected, isDragged and 0.3 or 1)
            end
        end
    end

    -- Bottom Action Buttons
    local btnY = GAME_HEIGHT - 65
    love.graphics.setColor(0.2, 0.5, 0.3)
    love.graphics.rectangle("fill", xPos + 15, btnY, 95, 35, 4, 4)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("STAGE", xPos + 40, btnY + 11)

    love.graphics.setColor(0.5, 0.2, 0.2)
    love.graphics.rectangle("fill", xPos + 120, btnY, 125, 35, 4, 4)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("CLEAR", xPos + 162, btnY + 11)
end

-- Block following the cursor while dragging
function drawDraggedBlock()
    if not draggedBlock then return end
    local mx, my = love.mouse.getPosition()
    if math.abs(mx - draggedBlock.startX) <= 4 and math.abs(my - draggedBlock.startY) <= 4 then
        return
    end
    drawBlock(mx - CHIP_W / 2, my - CHIP_H / 2, CHIP_W + 20, CHIP_H + 2, draggedBlock.label, true, 0.9)
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

