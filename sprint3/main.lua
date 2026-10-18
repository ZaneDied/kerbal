local currentState = "hangar"

local hangar = require("hangar")
local world = require("world")

function love.load()
    love.window.setTitle("Pixel Rocket: World & Moon Explorer")
    love.window.setMode(1280, 720, { resizable = true, vsync = true })
    love.graphics.setDefaultFilter("nearest", "nearest")
    
    hangar.load()
    world.load()
end

function love.keypressed(key)
    if key == "1" then
        currentState = "hangar"
        hangar.load()
    elseif key == "2" then
        currentState = "world"
        world.load()
    end

    if currentState == "hangar" and hangar.keypressed then
        hangar.keypressed(key)
    elseif currentState == "world" and world.keypressed then
        world.keypressed(key)
    end
end

function love.mousepressed(x, y, button)
    if currentState == "hangar" and hangar.mousepressed then
        local action = hangar.mousepressed(x, y, button)
        if action == "launch" then
            currentState = "world"
            world.load()
        end
    elseif currentState == "world" and world.mousepressed then
        world.mousepressed(x, y, button)
    end
end

function love.mousereleased(x, y, button)
    if currentState == "hangar" and hangar.mousereleased then
        hangar.mousereleased(x, y, button)
    end
end

function love.wheelmoved(x, y)
    if currentState == "world" and world.wheelmoved then
        world.wheelmoved(x, y)
    end
end

function love.update(dt)
    if currentState == "hangar" and hangar.update then
        hangar.update(dt)
    elseif currentState == "world" and world.update then
        world.update(dt)
    end
end

function love.draw()
    if currentState == "hangar" then
        hangar.draw()
    elseif currentState == "world" then
        world.draw()
    end
end