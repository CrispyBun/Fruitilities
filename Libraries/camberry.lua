local camberry = {}

-- Definitions -------------------------------------------------------------------------------------

---@class Camberry.Camera
---@field targets table[] The targets the camera tries to follow. For a target to work, it needs to have both an `x` and a `y` field with a number value.
---@field smoothness number How smoothly the camera should interpolate movement. Value from 0 to 1.
---@field zoom number The camera's zoom factor.
---@field rotation number The rotation of the camera. Note that calculations to keep targets within bounds will still be done unrotated.
---@field offsetX number How much to offset the camera's rendering in the X direction. Bypasses parallax effects.
---@field offsetY number How much to offset the camera's rendering in the Y direction. Bypasses parallax effects.
---@field snapToFirstTarget boolean Whether or not the camera should snap to always show the first target.
---@field zoomToAllTargets boolean Whether or not the camera should zoom out to always show all targets.
---@field safeBoundsOffset [number, number] The distance from the camera's edge (in each axis) that targets must stay in if `snapToFirstTarget` or `zoomToAllTargets` are enabled. Positive values shrink the area, negative values grow it.
---@field minAutoZoom number The minimum zoom the camera can automatically zoom to when zooming to show targets. This stacks with the currently set zoom value. Default is 0 (unlimited).
---@field pixelPerfectMovement boolean Whether or not the camera's position should snap to integer coordinates when rendering.
---@field dontRenderZoom boolean If true, zoom will still be present in all calculations, but won't be rendered.
---@field dontRenderRotation boolean If true, rotation will still be set, but won't be rendered.
---@field parallaxDepth number The camera's parallax depth. A value of 2 will make the camera move twice as slow, etc. Default is 1.
---@field parallaxStrengthX number Multiplier for the parallax effect in the X direction. Default is 1.
---@field parallaxStrengthY number Multiplier for the parallax effect in the Y direction. Default is 0.
---@field rotationalParallax? number If set, enables parallax on rotation for a trippy effect. Works like parallax strength.
---@field x number The camera's x position. You shouldn't modify this yourself if you use targets.
---@field y number The camera's y position. You shouldn't modify this yourself if you use targets.
---@field width number The camera's width.
---@field height number The camera's height.
---@field _zoom number Internally used zoom factor.
local Camera = {}
local CameraMT = {__index = Camera}

---@class Camberry.SimpleTarget
---@field x number
---@field y number
local Target = {}
local TargetMT = {__index = Target}

-- Lerp :-) ----------------------------------------------------------------------------------------

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Cameras -----------------------------------------------------------------------------------------

--------------------------------------------------
--- ### camberry.newCamera(width, height)
--- Creates a new camera. The `width` and `height` parameters set the camera's resolution.
---@param width number
---@param height number
---@return Camberry.Camera
function camberry.newCamera(width, height)
    if not width or not height then error("Must supply a width and height to the camera.", 2) end
    ---@type Camberry.Camera
    local camera = {
        targets = {},
        smoothness = 0.05,
        zoom = 1,
        rotation = 0,
        offsetX = 0,
        offsetY = 0,
        snapToFirstTarget = true,
        zoomToAllTargets = true,
        safeBoundsOffset = {0, 0},
        minAutoZoom = 0,
        dontRenderZoom = false,
        dontRenderRotation = false,
        pixelPerfectMovement = false,
        parallaxDepth = 1,
        parallaxStrengthX = 1,
        parallaxStrengthY = 0,
        x = 0,
        y = 0,
        width = width,
        height = height,
        _zoom = 1
    }

    return setmetatable(camera, CameraMT)
end

--------------------------------------------------
--- ### Camera:addTarget(target)
--- Adds a target for the camera to follow. A valid target is any table with an `x` and `y` numeric field.  
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
--- ### Camera:renderTo(func)
--- Shortcut to:
--- ```
--- camera:attach()
--- func(camera)
--- camera:detach()
--- ```
---@param func fun(camera: Camberry.Camera)
function Camera:renderTo(func)
    self:attach()
    func(self)
    self:detach()
end

--------------------------------------------------
--- ### Camera:update(dt)
--- Updates the camera's position.
---@param dt number The time in seconds since the last call to update
function Camera:update(dt)
    self:moveTowardsTargets(dt)
    self:snapTargetsToBounds()
    return camberry.graphics.updateCamera(self)
end

--------------------------------------------------
--- ### Camera:setPosition(x, y)
--- Directly sets the camera's position. Only use this if you don't use targets! Otherwise, things will just be jittery and broken.
---@param x number
---@param y number
---@return Camberry.Camera self
function Camera:setPosition(x, y)
    self.x = x
    self.y = y
    return self
end

--------------------------------------------------
--- ### Camera:toCameraSpace(px, py)
--- Transforms a point from global space to camera space.
---@param px number
---@param py number
---@return number
---@return number
function Camera:toCameraSpace(px, py)
    local x, y, width, height = self:getBounds()
    local zoom = self:getZoom()
    local rotation = self:getRotation()

    local halfWidth = width / 2
    local halfHeight = height / 2

    px = px - x - halfWidth
    py = py - y - halfHeight

    local sinr = math.sin(-rotation)
    local cosr = math.cos(-rotation)
    local pxRotated = px * cosr - py * sinr
    local pyRotated = px * sinr + py * cosr

    px = pxRotated + halfWidth
    py = pyRotated + halfHeight

    px = px * zoom
    py = py * zoom

    return px, py
end

--------------------------------------------------
--- ### Camera:toWorldSpace(px, py)
--- Transforms a point from camera space to global space.
---@param px number
---@param py number
---@return number
---@return number
function Camera:toWorldSpace(px, py)
    local x, y, width, height = self:getBounds()
    local zoom = self:getZoom()
    local rotation = self:getRotation()

    local halfWidth = width / 2
    local halfHeight = height / 2

    px = px / zoom
    py = py / zoom

    px = px - halfWidth
    py = py - halfHeight

    local sinr = math.sin(rotation)
    local cosr = math.cos(rotation)
    local pxRotated = px * cosr - py * sinr
    local pyRotated = px * sinr + py * cosr

    px = pxRotated + x + halfWidth
    py = pyRotated + y + halfHeight

    return px, py
end

--------------------------------------------------
--- ### Camera:setSmoothness(smoothness)
--- Sets the camera's smoothness.
---@param smoothness number
---@return Camberry.Camera self
function Camera:setSmoothness(smoothness)
    self.smoothness = smoothness
    return self
end

--------------------------------------------------
--- ### Camera:setZoom(zoom)
--- Sets the zoom factor of the camera.
---@param zoom number
---@return Camberry.Camera self
function Camera:setZoom(zoom)
    self.zoom = zoom
    return self
end

--------------------------------------------------
--- ### Camera:setRotation(rotation)
--- Sets the camera's rotation.
---@param rotation number
---@return Camberry.Camera self
function Camera:setRotation(rotation)
    self.rotation = rotation
    return self
end

--------------------------------------------------
--- ### Camera:setOffset(x, y)
--- Sets the camera's rendering offset. The offset bypasses parallax effects.
---@param x number
---@param y number
---@return Camberry.Camera self
function Camera:setOffset(x, y)
    self.offsetX = x
    self.offsetY = y
    return self
end

--------------------------------------------------
--- ### Camera:setSafeBoundsOffset(x, y)
--- Sets the camera's safe bounds offset.  
--- Each axis states how far from the camera's edge the targets must stay in. Negative values grow the area, positive shrink it.
--- 
--- If only one value is supplied, both axes will be set to it.
---@param x number The offset in the X direction
---@param y? number The offset in the Y direction (Default is `x`)
---@return Camberry.Camera self
function Camera:setSafeBoundsOffset(x, y)
    self.safeBoundsOffset[1] = x
    self.safeBoundsOffset[2] = y or x
    return self
end

--------------------------------------------------
--- ### Camera:setTargetSnapping(snapToFirstTarget, zoomToAllTargets)
--- Configures how the camera should behave if targets try to leave its view.
---@param snapToFirstTarget boolean Whether or not the camera should move to always show the first target
---@param zoomToAllTargets boolean Whether or not the camera should zoom to always show all targets
---@return Camberry.Camera self
function Camera:setTargetSnapping(snapToFirstTarget, zoomToAllTargets)
    self.snapToFirstTarget = snapToFirstTarget
    self.zoomToAllTargets = zoomToAllTargets
    return self
end

--------------------------------------------------
--- ### Camera:setParallaxDepth(depth)
--- Sets the depth of the camera for a parallax effect. A value of 2 will make the camera move twice as slow etc. Default is 1.  
--- This affects the next call to `camera:attach()`, as well as calls to `camera:getPixelPerfectOffset()`.
--- It does not affect the camera's actual position.
---@param depth number
---@return Camberry.Camera self
function Camera:setParallaxDepth(depth)
    self.parallaxDepth = depth
    return self
end

--------------------------------------------------
--- ### Camera:resetParallaxDepth()
--- Resets the camera's parallax depth value to remove the parallax effect.
---@return Camberry.Camera self
function Camera:resetParallaxDepth()
    return self:setParallaxDepth(1)
end

--------------------------------------------------
--- ### Camera:setParallaxStrength(x, y)
--- Sets the strength of the parallax effect in each direction.
---@param x number
---@param y number
---@return Camberry.Camera self
function Camera:setParallaxStrength(x, y)
    self.parallaxStrengthX = x
    self.parallaxStrengthY = y
    return self
end

--------------------------------------------------
--- ### Camera:getZoom()
--- Returns the camera's current zoom, including zoom from internal operations.
---@return number
function Camera:getZoom()
    return self.zoom * self._zoom
end

--------------------------------------------------
--- ### Camera:getRotation()
--- Returns the camera's rotation.
---@return number
function Camera:getRotation()
    return self.rotation
end

--------------------------------------------------
--- ### Camera:getOffset()
--- Returns the camera's rendering offset, including offset from internal operations.
---@return number offsetX
---@return number offsetY
function Camera:getOffset()
    return self.offsetX, self.offsetY
end

--------------------------------------------------
--- ### Camera:getBounds()
--- Returns the bounds that the camera sees.
---@param ignoreInternalZoom? boolean
---@return number x
---@return number y
---@return number width
---@return number height
function Camera:getBounds(ignoreInternalZoom)
    local zoom = self.zoom
    if not ignoreInternalZoom then zoom = zoom * self._zoom end

    local width = self.width / zoom
    local height = self.height / zoom
    local halfWidth = width / 2
    local halfHeight = height / 2
    return self.x - halfWidth, self.y - halfHeight, width, height
end

--------------------------------------------------
--- ### Camera:getSafeBounds()
--- Returns the bounds in which the camera will try to keep its targets, or just the regular bounds, if safeBoundsOffset is unset.
---@param ignoreInternalZoom? boolean
---@return number x
---@return number y
---@return number width
---@return number height
function Camera:getSafeBounds(ignoreInternalZoom)
    local safeBoundsOffset = self.safeBoundsOffset
    if not safeBoundsOffset then return self:getBounds(ignoreInternalZoom) end

    local x, y, width, height = self:getBounds(ignoreInternalZoom)
    return x + safeBoundsOffset[1], y + safeBoundsOffset[2], width - safeBoundsOffset[1] * 2, height - safeBoundsOffset[2] * 2
end

--------------------------------------------------
--- ### Camera:getBoundsForRendering()
--- Returns the bounds the camera should actually render to (takes `pixelPerfectMovement` into account).
function Camera:getBoundsForRendering()
    local depthX, depthY = self:getParallaxDepthValues()
    local offsetX, offsetY = self:getOffset()
    local x = self.x / depthX + offsetX
    local y = self.y / depthY + offsetY
    local zoom = self:getZoomForRendering()

    if self.pixelPerfectMovement then
        x = math.floor(x * zoom + 0.5) / zoom
        y = math.floor(y * zoom + 0.5) / zoom
    end

    local width = self.width / zoom
    local height = self.height / zoom
    local halfWidth = width / 2
    local halfHeight = height / 2
    return x - halfWidth, y - halfHeight, width, height
end

--------------------------------------------------
--- ### Camera:getBoundsForRendering()
--- Returns the zoom of the camera that rendering should use (takes `dontRenderZoom` into account).
function Camera:getZoomForRendering()
    if self.dontRenderZoom then return 1 end
    return self:getZoom()
end

--------------------------------------------------
--- ### Camera:getRotationForRendering()
--- Returns the rotation of the camera that rendering should use.
function Camera:getRotationForRendering()
    if self.dontRenderRotation then return 0 end
    if self.rotationalParallax then return self:getRotation() / lerp(1, self.parallaxDepth, self.rotationalParallax) end
    return self:getRotation()
end

--------------------------------------------------
--- ### Camera:getParallaxDepthValues()
--- Gets the final parallax depth values for each axis of the camera.
---@return number x
---@return number y
function Camera:getParallaxDepthValues()
    local depth = self.parallaxDepth
    return lerp(1, depth, self.parallaxStrengthX), lerp(1, depth, self.parallaxStrengthY)
end

--------------------------------------------------
--- ### Camera:getPixelPerfectOffset()
--- Returns a fractional value for each axis saying how much the camera needs to move to reach the nearest pixel perfect position. Basically, this just tells you how much the camera is currently offset if `pixelPerfectMovement` is enabled.
---@return number
---@return number
function Camera:getPixelPerfectOffset()
    local zoom = self:getZoomForRendering()
    local depthX, depthY = self:getParallaxDepthValues()
    local x = self.x / depthX * zoom
    local y = self.y / depthY * zoom
    return
        -((x + 0.5) % 1 - 0.5),
        -((y + 0.5) % 1 - 0.5)
end

--------------------------------------------------
--- ### Camera:setResolution(width, height)
--- ### Camera:setSize(width, height)
--- ### Camera:setDimensions(width, height)
--- Sets the camera's resolution.
---@param width number
---@param height number
---@return Camberry.Camera self
function Camera:setResolution(width, height)
    self.width = width
    self.height = height
    return self
end
Camera.setSize = Camera.setResolution
Camera.setDimensions = Camera.setResolution

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
--- ### Camera:moveTowardsTargets(dt)
--- Moves the camera towards its target(s). This is called automatically by `camera:update()`.
function Camera:moveTowardsTargets(dt)
    local sourceX, sourceY = self.x, self.y
    local targetX, targetY = self:getTargetPosition()
    local smoothness = self.smoothness

    -- Bypass the slightly more expensive lerp for instant cameras
    if smoothness == 0 then
        self.x = targetX
        self.y = targetY
        return
    end

    self.x = lerp(sourceX, targetX, 1 - smoothness ^ dt)
    self.y = lerp(sourceY, targetY, 1 - smoothness ^ dt)
end

--------------------------------------------------
--- ### Camera:snapTargetsToBounds()
--- Snaps the camera so that its targets are visible. Has no effect if both `snapToFirstTarget` and `zoomToAllTargets` are off.
--- Used internally.
function Camera:snapTargetsToBounds()
    if self.snapToFirstTarget then self:snapFirstTargetToBounds() end
    if self.zoomToAllTargets then self:zoomTargetsToBounds() end
end

--------------------------------------------------
--- ### Camera:snapFirstTargetToBounds()
--- Snaps the camera so that the first target is visible.  
--- Used internally.
function Camera:snapFirstTargetToBounds()
    local safeX, safeY, safeW, safeH = self:getSafeBounds()
    local targets = self.targets
    local target = targets[1]
    if not target then return end

    local targetX = target.x or safeX
    local targetY = target.y or safeY

    if     targetX < safeX then self.x = targetX + safeW / 2
    elseif targetX > safeX + safeW then self.x = targetX - safeW / 2 end

    if     targetY < safeY then self.y = targetY + safeH / 2
    elseif targetY > safeY + safeH then self.y = targetY - safeH / 2 end
end

--------------------------------------------------
--- ### Camera:zoomTargetsToBounds()
--- Sets the zoom of the camera so that all targets are visible.
--- Used internally.
function Camera:zoomTargetsToBounds()
    local safeX, safeY, safeW, safeH = self:getSafeBounds(true)
    local _, _, cameraWidth, cameraHeight = self:getBounds(true)

    local minX, minY, maxX, maxY = safeX, safeY, safeX + safeW, safeY + safeH
    local targets = self.targets

    for targetIndex = 1, #targets do
        local target = targets[targetIndex]
        local targetX = target.x
        local targetY = target.y
        if targetX then
            minX = math.min(minX, targetX)
            maxX = math.max(maxX, targetX)
        end
        if targetY then
            minY = math.min(minY, targetY)
            maxY = math.max(maxY, targetY)
        end
    end

    local differenceLeft = math.abs(minX - safeX)
    local differenceTop = math.abs(minY - safeY)
    local differenceRight = math.abs(maxX - safeX - safeW)
    local differenceBottom = math.abs(maxY - safeY - safeH)

    local differenceX = math.max(differenceLeft, differenceRight) * 2 -- *2 since both sides scale
    local differenceY = math.max(differenceTop, differenceBottom) * 2

    -- We get the amount of pixels that we want to grow by (differenceX),
    -- then we calculate how much percent we need to grow by (differenceX / safeW),
    -- then we convert that to an actual multipliable increase (0.1 becomes 1.1),
    -- then we divide 1 over that number, since that's how zoom works.
    local zoomX = 1 / (1 + differenceX / cameraWidth)
    local zoomY = 1 / (1 + differenceY / cameraHeight)

    local zoom = math.min(zoomX, zoomY)
    zoom = math.max(zoom, self.minAutoZoom)
    if zoom < 1 then self._zoom = zoom end
end

-- Simple targets ----------------------------------------------------------------------------------

--------------------------------------------------
--- ### camberry.newSimpleTarget()
--- Creates a new simple target that cameras can use.
--- Note that a camera's target does not have to be made by this function. A valid target is any table with an `x` and `y` numeric field.
---@param x? number
---@param y? number
---@return Camberry.SimpleTarget
function camberry.newSimpleTarget(x, y)
    ---@type Camberry.SimpleTarget
    local target = {
        x = x or 0,
        y = y or 0
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

--------------------------------------------------
--- ### Target:clone()
--- Returns a copy of the target.
---@return Camberry.SimpleTarget
function Target:clone()
    local target = camberry.newSimpleTarget(self.x, self.y)
    return target
end

-- Abstraction for possible usage outside LÖVE -----------------------------------------------------

-- Can be replaced with functions to perform these actions in non-love2d environments
camberry.graphics = {}

---@diagnostic disable-next-line: undefined-global
local love = love

function camberry.graphics.attachCamera(camera)
    local x, y, width, height = camera:getBoundsForRendering()
    local zoom = camera:getZoomForRendering()
    local rotation = camera:getRotationForRendering()

    local halfWidth = width / 2
    local halfHeight = height / 2
    love.graphics.push()
    love.graphics.scale(zoom)
    love.graphics.translate(halfWidth, halfHeight)
    love.graphics.rotate(-rotation)
    love.graphics.translate(-x-halfWidth, -y-halfHeight)
end

function camberry.graphics.detachCamera(camera)
    love.graphics.pop()
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