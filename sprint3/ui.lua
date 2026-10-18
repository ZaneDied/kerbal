local ui = {}

function ui.draw(zoom, stages, currentDeltaV, currentMaxDeltaV)
    local GAME_WIDTH = 1280
    local GAME_HEIGHT = 720

    -- Draw Staging UI on the right side
    local panelW = 220
    local panelH = 300
    local panelX = GAME_WIDTH - panelW - 20
    local panelY = 20

    love.graphics.setColor(0.12, 0.13, 0.16, 0.85)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 6, 6)
    love.graphics.setColor(0.3, 0.35, 0.45)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 6, 6)

    love.graphics.setColor(0.9, 0.9, 0.95)
    love.graphics.print("FLIGHT STAGES", panelX + 15, panelY + 12)

    -- Delta-V Info
    love.graphics.setColor(0.6, 0.8, 1.0)
    love.graphics.print(string.format("Delta-V: %.0f / %.0f m/s", currentDeltaV or 0, currentMaxDeltaV or 0), panelX + 15, panelY + 36)

    -- Stage list placeholder if empty
    love.graphics.setColor(0.7, 0.75, 0.8)
    love.graphics.print("Press [Space] to fire next stage", panelX + 15, panelY + 66)
    love.graphics.print("Press [M] for Map / Tracking", panelX + 15, panelY + 90)
    love.graphics.print("Press [R] to Reset Flight", panelX + 15, panelY + 114)
    love.graphics.print("Controls: [A][D] Rotate Ship", panelX + 15, panelY + 138)
    love.graphics.print("          [Shift/Ctrl] Throttle", panelX + 15, panelY + 162)
end

return ui