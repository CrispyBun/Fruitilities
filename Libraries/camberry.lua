local camberry = {}

-- Definitions -------------------------------------------------------------------------------------

---@class Camerry.Camera
---@field targets table[] The targets the camera tries to follow. For a target to work, it needs to have both an `x` and a `y` field with a number value.
---@field smoothness number How smoothly the camera should interpolate movement. Value from 0 to 1.
---@field x number The camera's x position. You shouldn't modify this yourself if you use targets.
---@field y number The camera's y position. You shouldn't modify this yourself if you use targets.
---@field width number The camera's width.
---@field height number The camera's height.
local Camera = {}
local CameraMT = {__index = Camera}

---@class Camberry.SimpleTarget
---@field x number
---@field y number
local Target = {}
local TargetMT = {__index = Target}

-- Cameras -----------------------------------------------------------------------------------------

--------------------------------------------------
--- ### camberry.newCamera(width, height)
--- Creates a new camera. The `width` and `height` parameters set the camera's resolution, default is a resolution of 0x0.
---@param width? number
---@param height? number
---@return Camerry.Camera
function camberry.newCamera(width, height)
    ---@type Camerry.Camera
    local camera = {
        targets = {},
        smoothness = 0.05,
        x = 0,
        y = 0,
        width = width or 0,
        height = height or 0
    }

    return setmetatable(camera, CameraMT)
end

--------------------------------------------------
--- ### Camera:addTarget(target)
--- Adds a target for the camera to follow.  
--- If `target` is not supplied, creates a new SimpleTarget.  
--- Returns the added target.
---@param target? table
---@return table target
function Camera:addTarget(target)
    target = target or camberry.newSimpleTarget()
    self.targets[#self.targets+1] = target
    return target
end

--------------------------------------------------
--- ### Camera:removeTarget(target)
--- Removes a target from the camera.
function Camera:removeTarget(target)
    local targets = self.targets
    for targetIndex = 1, #targets do
        if targets[targetIndex] == target then
            return table.remove(targets, targetIndex)
        end
    end
end

--------------------------------------------------
--- ### Camera:attach()
--- ### Camera:action()
--- Attaches the camera for upcoming draw operations. Make sure the call `Camera:detach()` after those are done.
function Camera:attach()
    return camberry.graphics.attachCamera(self)
end
Camera.action = Camera.attach

--------------------------------------------------
--- ### Camera:detach()
--- ### Camera:cut()
--- Detaches the camera after all draw operations have been made.
function Camera:detach()
    return camberry.graphics.detachCamera(self)
end
Camera.cut = Camera.detach

--------------------------------------------------
--- ### Camera:update(dt)
--- Updates the camera's position.
---@param dt number The time in seconds since the last call to update
function Camera:update(dt)
    local sourceX, sourceY = self.x, self.y
    local targetX, targetY = self:getTargetPosition()
    local smoothness = self.smoothness

    -- lerp(sourceX, targetX, 1 - smoothness ^ dt)
    self.x = sourceX + (targetX - sourceX) * (1 - smoothness ^ dt)
    self.y = sourceY + (targetY - sourceY) * (1 - smoothness ^ dt)

    return camberry.graphics.updateCamera(self)
end

--------------------------------------------------
--- ### Camera:getTargetPosition()
--- Returns the `x` and `y` coordinates the camera is currently travelling to.
---@return number targetX
---@return number targetY
function Camera:getTargetPosition()
    local targets = self.targets
    local targetSumX, targetSumY = 0, 0
    local targetCountX, targetCountY = 0, 0
    for targetIndex = 1, #targets do
        local target = targets[targetIndex]
        if target.x then
            targetSumX = targetSumX + target.x
            targetCountX = targetCountX + 1
        end
        if target.y then
            targetSumY = targetSumY + target.y
            targetCountY = targetCountY + 1
        end
    end

    local targetX = targetCountX > 0 and targetSumX / targetCountX or self.x
    local targetY = targetCountY > 0 and targetSumY / targetCountY or self.y

    return targetX, targetY
end

--------------------------------------------------
--- ### Camera:setPosition(x, y)
--- Directly sets the camera's position. Only use this if you don't use targets! Otherwise, things will just be jittery and broken.
---@param x number
---@param y number
---@return Camerry.Camera self
function Camera:setPosition(x, y)
    self.x = x
    self.y = y
    return self
end

--------------------------------------------------
--- ### Camera:setSmoothness(smoothness)
--- Sets the camera's smoothness.
---@param smoothness number
---@return Camerry.Camera self
function Camera:setSmoothness(smoothness)
    self.smoothness = smoothness
    return self
end

--------------------------------------------------
--- ### Camera:setResolution(width, height)
--- ### Camera:setSize(width, height)
--- ### Camera:setDimensions(width, height)
--- Sets the camera's resolution.
---@param width number
---@param height number
---@return Camerry.Camera self
function Camera:setResolution(width, height)
    self.width = width
    self.height = height
    return self
end
Camera.setSize = Camera.setResolution
Camera.setDimensions = Camera.setResolution

-- Simple targets ----------------------------------------------------------------------------------

--------------------------------------------------
--- ### camberry.newSimpleTarget()
--- Creates a new simple target that cameras can use.
--- Note that a camera's target does not have to be made by this function. A valid target is any table with an `x` and `y` numeric field.
function camberry.newSimpleTarget()
    ---@type Camberry.SimpleTarget
    local target = {
        x = 0,
        y = 0
    }

    return setmetatable(target, TargetMT)
end

--------------------------------------------------
--- ### Target:setPosition(x, y)
--- Sets the target's position.
---@param x number
---@param y number
---@return Camberry.SimpleTarget self
function Target:setPosition(x, y)
    self.x = x
    self.y = y
    return self
end
Target.setPos = Target.setPosition

-- Abstraction for possible usage outside LÖVE -----------------------------------------------------

-- Can be replaced with functions to perform these actions in non-love2d environments
camberry.graphics = {}

---@diagnostic disable-next-line: undefined-global
local love = love

function camberry.graphics.attachCamera(camera)
    -- todo
end

function camberry.graphics.detachCamera(camera)
    -- todo
end

function camberry.graphics.updateCamera(camera)
    -- Nothing has to happen in Love2D but this function can be useful for moving a third party camera object in some other engine
end

local emptyFunction = function () end
if not love then
    camberry.graphics.attachCamera = emptyFunction
    camberry.graphics.detachCamera = emptyFunction
    camberry.graphics.updateCamera = emptyFunction
end

return camberry