local currentState = "hangar" -- Options: "hangar", "rocket", "reentry"

local hangar = require("hangar")
local rocket = require("rocket")
local reentry = require("reentry")

function love.load()
    love.window.setTitle("Pixel Rocket Simulation Suite")
    love.window.setMode(1280, 720, { resizable = true, vsync = true })
    love.graphics.setDefaultFilter("nearest", "nearest")
    
    -- Initialize all modules
    hangar.load()
    rocket.load()
    reentry.load()
end

function love.keypressed(key)
    -- Global mode switching shortcuts
    if key == "1" then
        currentState = "hangar"
    elseif key == "2" then
        currentState = "rocket"
        -- Optional: reload rocket data in case you saved a new rocket in the hangar
        rocket.load()
    elseif key == "3" then
        currentState = "reentry"
        -- Optional: reload reentry data in case you saved a new rocket
        reentry.load()
    end

    -- Route keypress strictly to the active module
    if currentState == "hangar" and hangar.keypressed then
        hangar.keypressed(key)
    elseif currentState == "rocket" and rocket.keypressed then
        rocket.keypressed(key)
    elseif currentState == "reentry" and reentry.keypressed then
        reentry.keypressed(key)
    end
end

function love.mousepressed(x, y, button)
    if currentState == "hangar" and hangar.mousepressed then
        hangar.mousepressed(x, y, button)
    elseif currentState == "rocket" and rocket.mousepressed then
        rocket.mousepressed(x, y, button)
    elseif currentState == "reentry" and reentry.mousepressed then
        reentry.mousepressed(x, y, button)
    end
end

function love.mousereleased(x, y, button)
    if currentState == "hangar" and hangar.mousereleased then
        hangar.mousereleased(x, y, button)
    elseif currentState == "rocket" and rocket.mousereleased then
        rocket.mousereleased(x, y, button)
    elseif currentState == "reentry" and reentry.mousereleased then
        reentry.mousereleased(x, y, button)
    end
end

function love.update(dt)
    if currentState == "hangar" and hangar.update then
        hangar.update(dt)
    elseif currentState == "rocket" and rocket.update then
        rocket.update(dt)
    elseif currentState == "reentry" and reentry.update then
        reentry.update(dt)
    end
end

function love.draw()
    if currentState == "hangar" then
        hangar.draw()
    elseif currentState == "rocket" then
        rocket.draw()
    elseif currentState == "reentry" then
        reentry.draw()
    end

    -- Global Navigation Overlay (Visible across all screens)
    love.graphics.setColor(0.1, 0.1, 0.1, 0.8)
    love.graphics.rectangle("fill", GAME_WIDTH_OFFSET or 0, 0, 450, 25, 0, 0, 4, 4)
    
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.setFont(love.graphics.newFont(12))
    -- Note: Hangar draws its own top bar, but this acts as an omnipresent switcher hint
end