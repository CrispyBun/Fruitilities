----------------------------------------------------------------------------------------------------
-- An overengineered camera library (and value interpolation animation library)
-- written by yours truly, CrispyBun.
-- crispybun@pm.me
-- https://github.com/CrispyBun/Fruitilities
----------------------------------------------------------------------------------------------------
--[[
MIT License

Copyright (c) 2024-2025 Ava "CrispyBun" Špráchalů

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
--]]
----------------------------------------------------------------------------------------------------

local camberry = {}

-- Definitions -------------------------------------------------------------------------------------

---@class Camberry.Camera : Camberry.RigReceiver
---@field targets table[] The targets the camera tries to follow. For a target to work, it needs to have both an `x` and a `y` field with a number value.
---@field smoothness number How smoothly the camera should interpolate movement. Value from 0 to 1.
---@field zoom number The camera's zoom factor.
---@field rotation number The rotation of the camera. Note that calculations to keep targets within bounds will still be done unrotated.
---@field offsetX number How much to offset the camera's rendering in the X direction. Bypasses parallax effects.
---@field offsetY number How much to offset the camera's rendering in the Y direction. Bypasses parallax effects.
---@field snapToFirstTarget boolean Whether or not the camera should snap to always show the first target.
---@field zoomToAllTargets boolean Whether or not the camera should zoom out to always show all targets.
---@field safeBoundsOffset [number, number] The distance from the camera's edge (in each axis) that targets must stay in if `snapToFirstTarget` or `zoomToAllTargets` are enabled. Positive values shrink the area, negative values grow it.
---@field safeBoundsAreDeadzone boolean If true, the `safeBoundsOffset` will be a rectangle starting from the center of the camera, rather than it starting and shrinking from the edges of the camera. Default is false.
---@field scaleSafeBoundsWithZoom boolean If true, the safe bounds area will scale with the camera's zoom. This may make auto-zooming to show targets inaccurate. Default is false.
---@field shouldUpdateTargetRigs boolean If true, the camera will scan its targets and, if they have an `updateRigs` method, calls it.
---@field minAutoZoom number The minimum zoom the camera can automatically zoom to when zooming to show targets. This stacks with the currently set zoom value. Default is 0 (unlimited).
---@field pixelPerfectMovement boolean Whether or not the camera's position should snap to integer coordinates when rendering.
---@field dontRenderZoom boolean If true, zoom will still be present in all calculations, but won't be rendered.
---@field dontRenderRotation boolean If true, rotation will still be set, but won't be rendered.
---@field dontRenderOffset boolean If true, offset will still be set, but won't be rendered.
---@field parallaxDepth number The camera's parallax depth. A value of 2 will make the camera move twice as slow, etc. Default is 1.
---@field parallaxStrengthX number Multiplier for the parallax effect in the X direction. Default is 1.
---@field parallaxStrengthY number Multiplier for the parallax effect in the Y direction. Default is 0.
---@field rotationalParallax? number If set, enables parallax on rotation for a trippy effect. Works like parallax strength.
---@field invertPositionRelativeToTargets boolean If set to true, the camera will render its position to the opposite one in relation to its targets - if the camera is to the left of the targets, it will render to the right of them, etc.
---@field x number The camera's x position. You shouldn't modify this yourself if you use targets.
---@field y number The camera's y position. You shouldn't modify this yourself if you use targets.
---@field width number The camera's width.
---@field height number The camera's height.
---@field _zoom number Internally used zoom factor.
---@field _offsetX number Internally used offset in the X direction.
---@field _offsetY number Internally used offset in the Y direction.
local Camera = {}
local CameraMT = {__index = Camera}

---@class Camberry.SimpleTarget : Camberry.RigReceiver
---@field x number
---@field y number
local Target = {}
local TargetMT = {__index = Target}

---@class Camberry.RigReceiver
---@field attachedRigs Camberry.Rig[] The current active rigs. These will be updated and used. If any modify the same value, the value will be averaged.
---@field waitForAllRigs boolean If true, the receiver will finish and detach its attached rigs all at once, and only after all of them are at the end of the animation.
---@field stackableRigValues table<string, boolean> If a key in this table is true, and multiple rigs modify a value with that key in the receiver, the values will be summed instead of averaged.
local RigReceiver = {}
local RigReceiverMT = {__index = RigReceiver}

---@class Camberry.Rig
---@field progress number A timer counting towards the max duration.
---@field duration number The duration of the whole animation. When `progress` reaches this value, the rig will be removed from the RigReceiver.
---@field easing fun(x: number): number The easing function to use for interpolation. When setting this using `rig:setEasing()`, you can set this with a name of an easing function known by the library.
---@field stayAttached boolean If true, the rig will never finish and will not automatically detach itself when it finished playing, and will have to be removed manually be either setting this to false or calling RemoveRig on the RigReceiver.
---
---@field next? Camberry.Rig Optional next rig to chain after this one. It will be attached after this one is done playing.
---@field reachedEnd boolean Will be set to true once the rig has finished playing. Doesn't actually have any function, it's just for quickly being able to tell if a rig is done.
---@field isAttached boolean This is set automatically by RigReceivers. An error will happen if an already attached rig tries to attach itself again. Rigs stop being attached automatically once they finish playing.
---
---@field onAttach? fun(rig: Camberry.Rig, receiver: Camberry.RigReceiver) Called when the rig gets attached to a receiver.
---@field onFinish? fun(rig: Camberry.Rig, receiver: Camberry.RigReceiver) Called when the rig finishes playing and stops being attached.
---@field onUpdate? fun(rig: Camberry.Rig, receiver: Camberry.RigReceiver, dt: number) Called for each update of the rig.
---@field onReset? fun(rig: Camberry.Rig) Called when the rig is reset.
---
---@field sourceValues table<string, number> The values of the RigReceiver the rig will interpolate from.
---@field targetValues table<string, number> The values of the RigReceiver the rig will interpolate to.
local Rig = {}
local RigMT = {__index = Rig}

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
    if not width or not height then error("Must supply a width and height to the camera", 2) end
    -- new Camberry.Camera
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
        safeBoundsAreDeadzone = false,
        scaleSafeBoundsWithZoom = false,
        shouldUpdateTargetRigs = false,
        minAutoZoom = 0,
        dontRenderZoom = false,
        dontRenderRotation = false,
        dontRenderOffset = false,
        pixelPerfectMovement = false,
        parallaxDepth = 1,
        parallaxStrengthX = 1,
        parallaxStrengthY = 0,
        invertPositionRelativeToTargets = false,
        x = 0,
        y = 0,
        width = width,
        height = height,
        _zoom = 1,
        _offsetX = 0,
        _offsetY = 0,

        attachedRigs = {},
        waitForAllRigs = false,
        stackableRigValues = {
            offsetX = true,
            offsetY = true,
            _offsetX = true,
            _offsetY = true
        }
    }

    return setmetatable(camera, CameraMT)
end

--------------------------------------------------
--- ### Camera:clone()
--- Returns a copy of the camera.
---@return Camberry.Camera
function Camera:clone()
    local camera = camberry.newCamera(self.width, self.height)
    for targetIndex = 1, #self.targets do
        camera.targets[targetIndex] = self.targets[targetIndex]
    end
    camera.smoothness = self.smoothness
    camera.zoom = self.zoom
    camera.rotation = self.rotation
    camera.offsetX = self.offsetX
    camera.offsetY = self.offsetY
    camera.snapToFirstTarget = self.snapToFirstTarget
    camera.zoomToAllTargets = self.zoomToAllTargets
    camera.safeBoundsOffset[1], camera.safeBoundsOffset[2] = self.safeBoundsOffset[1], self.safeBoundsOffset[2]
    camera.shouldUpdateTargetRigs = self.shouldUpdateTargetRigs
    camera.minAutoZoom = self.minAutoZoom
    camera.dontRenderZoom = self.dontRenderZoom
    camera.dontRenderRotation = self.dontRenderRotation
    camera.dontRenderOffset = self.dontRenderOffset
    camera.pixelPerfectMovement = self.pixelPerfectMovement
    camera.parallaxDepth = self.parallaxDepth
    camera.parallaxStrengthX = self.parallaxStrengthX
    camera.parallaxStrengthY = self.parallaxStrengthY
    camera.x = self.x
    camera.y = self.y
    camera._zoom = self._zoom
    camera._offsetX = self._offsetX
    camera._offsetY = self._offsetY

    -- No point in copying attached rigs, as that'd make them attached to two cameras which would break stuff
    camera.waitForAllRigs = self.waitForAllRigs
    for valueIndex = 1, #self.stackableRigValues do
        camera.stackableRigValues[valueIndex] = self.stackableRigValues[valueIndex]
    end

    return camera
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
--- ### Camera:setTargets(...)
--- ### Camera:setTarget(target)
--- Directly sets the camera's targets (and overwrites any existing ones, unlike `camera:addTarget()`).
---@param ... table
function Camera:setTargets(...)
    self.targets = {...}
end
Camera.setTarget = Camera.setTargets

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
--- This is the only update that needs to be called on the camera,
--- as this will also call `camera:updateRigs()`.
---@param dt number The time in seconds since the last call to update
function Camera:update(dt)
    if self.shouldUpdateTargetRigs then
        for targetIndex = 1, #self.targets do
            local target = self.targets[targetIndex]
            if target.updateRigs then target:updateRigs(dt) end
        end
    end

    self:moveTowardsTargets(dt)
    self:snapTargetsToBounds()
    self:updateRigs(dt)
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
    local x, y, width, height = self:getBoundsForRendering()
    local zoom = self:getZoomForRendering()
    local rotation = self:getRotationForRendering()

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
    local x, y, width, height = self:getBoundsForRendering()
    local zoom = self:getZoomForRendering()
    local rotation = self:getRotationForRendering()

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
--- ### Camera:shake(intensity, duration, speed)
--- Applies a shake effect to the camera for a duration.
---@param intensity? number How many pixels out will the camera shake
---@param duration? number How long the shake will last in seconds
---@param speed? number How many shakes per second will the shake happen at
function Camera:shake(intensity, duration, speed)
    self:attachRig(camberry.newShakeRig(intensity, duration, speed))
end

--------------------------------------------------
--- ### Camera:getZoom()
--- Returns the camera's current zoom, including zoom from internal operations.
---@param ignoreInternalZoom? boolean
---@return number
function Camera:getZoom(ignoreInternalZoom)
    if ignoreInternalZoom then return self.zoom end
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
    return self.offsetX + self._offsetX, self.offsetY + self._offsetY
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
    local zoom = self:getZoom(ignoreInternalZoom)

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

    local offsetX, offsetY = safeBoundsOffset[1], safeBoundsOffset[2]
    if self.scaleSafeBoundsWithZoom then
        local zoom = self:getZoom(ignoreInternalZoom)
        offsetX = offsetX / zoom
        offsetY = offsetY / zoom
    end

    if self.safeBoundsAreDeadzone then
        local halfWidth = width / 2
        local halfHeight = height / 2
        return x + halfWidth - offsetX, y + halfHeight - offsetY, offsetX * 2, offsetY * 2
    end

    return x + offsetX, y + offsetY, width - offsetX * 2, height - offsetY * 2
end

--------------------------------------------------
--- ### Camera:getBoundsForRendering()
--- Returns the bounds the camera should actually render to.
function Camera:getBoundsForRendering()
    local depthX, depthY = self:getParallaxDepthValues()
    local offsetX, offsetY = self:getOffsetForRendering()
    local x = self.x / depthX + offsetX
    local y = self.y / depthY + offsetY
    local zoom = self:getZoomForRendering()

    if self.pixelPerfectMovement then
        x = math.floor(x * zoom + 0.5) / zoom
        y = math.floor(y * zoom + 0.5) / zoom
    end

    if self.invertPositionRelativeToTargets then
        local targetX, targetY = self:getTargetPosition()
        x = 2 * targetX - x
        y = 2 * targetY - y
    end

    local width = self.width / zoom
    local height = self.height / zoom
    local halfWidth = width / 2
    local halfHeight = height / 2
    return x - halfWidth, y - halfHeight, width, height
end

--------------------------------------------------
--- ### Camera:getZoomForRendering()
--- Returns the zoom of the camera that rendering should use.
---@return number
function Camera:getZoomForRendering()
    if self.dontRenderZoom then return 1 end
    return self:getZoom()
end

--------------------------------------------------
--- ### Camera:getRotationForRendering()
--- Returns the rotation of the camera that rendering should use.
---@return number
function Camera:getRotationForRendering()
    if self.dontRenderRotation then return 0 end
    if self.rotationalParallax then return self:getRotation() / lerp(1, self.parallaxDepth, self.rotationalParallax) end
    return self:getRotation()
end

--------------------------------------------------
--- ### Camera:getOffsetForRendering()
--- Returns the offset of the camera that rendering should use.
---@return number
---@return number
function Camera:getOffsetForRendering()
    if self.dontRenderOffset then return 0, 0 end
    return self:getOffset()
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

    if self.invertPositionRelativeToTargets then
        x = -x -- We need to flip the sign of the result
        y = -y
    end

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

    -- https://www.rorydriscoll.com/2016/03/07/frame-rate-independent-damping-using-lerp/
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
    -- then we calculate how much percent we need to grow by (differenceX / cameraWidth),
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
    -- new Camberry.SimpleTarget
    local target = {
        x = x or 0,
        y = y or 0,

        attachedRigs = {},
        waitForAllRigs = false,
        stackableRigValues = {}
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

-- Rig receivers -----------------------------------------------------------------------------------

--------------------------------------------------
--- ### camberry.newRigReceiver()
--- Creates a new rig receiver.  
--- 
--- A pure instanced rig receiver doesn't actually have any values to interpolate,
--- the RigReceiver is more meant to be inherited from, as the camera does.  
--- 
--- But, if you insert any values into an instance of a RigReceiver, those values can be interpolated (given that they're number values).
---@return Camberry.RigReceiver
function camberry.newRigReceiver()
    -- new Camberry.RigReceiver
    local receiver = {
        attachedRigs = {},
        waitForAllRigs = false,
        stackableRigValues = {}
    }

    return setmetatable(receiver, RigReceiverMT)
end

--------------------------------------------------
--- ### RigReceiver:attachRig(rig)
--- Attaches a rig to the receiver to be updated and used.
---@param rig Camberry.Rig
function RigReceiver:attachRig(rig)
    if rig.isAttached then error("Attempting to attach a rig that's already attached to a different receiver", 2) end
    rig.isAttached = true

    rig:reset(true)
    self.attachedRigs[#self.attachedRigs+1] = rig
    if rig.onAttach then rig.onAttach(rig, self) end
end

--------------------------------------------------
---@param receiver Camberry.RigReceiver
---@param index integer
local function popRig(receiver, index)
    local rigs = receiver.attachedRigs
    local rig = rigs[index]
    rigs[index], rigs[#rigs] = rigs[#rigs], rigs[index]
    rigs[#rigs] = nil
    rig.isAttached = false
end
--------------------------------------------------
--- ### RigReceiver:removeRig(rig)
--- ### RigReceiver:detachRig(rig)
--- Removes a rig from the receiver.  
--- If the rig isn't found, returns false. Otherwise returns true.
---@param rig Camberry.Rig
---@return boolean success
function RigReceiver:removeRig(rig)
    local rigs = self.attachedRigs
    for rigIndex = 1, #rigs do
        if rigs[rigIndex] == rig then
            popRig(self, rigIndex)
            return true
        end
    end
    return false
end
RigReceiver.detachRig = RigReceiver.removeRig

--------------------------------------------------
--- ### RigReceiver:clearRigs()
--- Removes all rigs from the receiver.
function RigReceiver:clearRigs()
    local rigs = self.attachedRigs
    for rigIndex = #rigs, 1, -1 do
        popRig(self, rigIndex)
    end
end

--------------------------------------------------
--- ### RigReceiver:updateRigs(dt)
--- Updates the attached rigs, progressing their animations.
---@param dt number The time in seconds since the last call to updateRigs
function RigReceiver:updateRigs(dt)
    if #self.attachedRigs == 0 then return end

    local valueSums = {}
    local valueCounts = {}
    local finishedRigs = {}

    local stackableValues = self.stackableRigValues

    local waitForAllRigs = self.waitForAllRigs
    local allRigsFinished = true

    local rigs = self.attachedRigs
    local rigCount = #rigs
    local rigIndex = 1
    while rigIndex <= rigCount do
        local rig = rigs[rigIndex]
        local duration = rig.duration
        rig.progress = math.min(rig.progress + dt, duration)

        local time = duration == 0 and 1 or rig.progress / duration
        local easing = rig.easing
        local interp = easing(time)
        for key, value in pairs(rig.sourceValues) do
            valueSums[key] = valueSums[key] or 0
            valueCounts[key] = valueCounts[key] or 0

            -- Maybe an unset target value should error but a default 0 makes sense to me too
            local targetValue = rig.targetValues[key] or 0
            valueSums[key] = valueSums[key] + lerp(value, targetValue, interp)
            valueCounts[key] = valueCounts[key] + 1
        end

        local progressFinished = rig.progress >= duration and not rig.stayAttached
        if not progressFinished then allRigsFinished = false end

        if progressFinished and not waitForAllRigs then
            popRig(self, rigIndex)
            rigCount = rigCount - 1
            finishedRigs[#finishedRigs+1] = rig
        else
            -- If we popped a rig, there's going to be a new rig at the same index, so only increment if we didn't
            rigIndex = rigIndex + 1
        end
    end

    if waitForAllRigs and allRigsFinished then
        for rigIndex = 1, #rigs do
            finishedRigs[rigIndex] = rigs[rigIndex]
        end
        self:clearRigs()
    end

    for finishedRigIndex = 1, #finishedRigs do
        local rig = finishedRigs[finishedRigIndex]
        rig.reachedEnd = true
        if rig.next then self:attachRig(rig.next) end
        if rig.onFinish then rig.onFinish(rig, self) end
    end

    for key, sum in pairs(valueSums) do
        if stackableValues[key] then
            self[key] = sum
        else
            self[key] = sum / valueCounts[key]
        end
    end
end

-- Slightly crude way of making the cameras and targets inherit from rig receivers (this must happen after the rig receiver has all its methods defined)
-- I know I could just have another __index metatable on their definitions pointing to rig receivers, but I prefer having the definition fully flattened into 1 table.
for key, value in pairs(RigReceiver) do
    if not Camera[key] then Camera[key] = value end
    if not Target[key] then Target[key] = value end
end

-- Rigs --------------------------------------------------------------------------------------------

--------------------------------------------------
--- ### camberry.newRig()
--- Creates a new rig, capable of animating any number values of a RigReceiver (or a class implementing RigReceiver, such as the Camera).
---@param duration? number
---@param easing? string|fun(x: number): number
---@param sourceValues? table<string, number>
---@param targetValues? table<string, number>
---@return Camberry.Rig
function camberry.newRig(duration, easing, sourceValues, targetValues)

    if type(easing) == "string" then
        if not camberry.tweens[easing] then error("Unknown easing function: " .. easing, 2) end
        easing = camberry.tweens[easing]
    end

    -- new Camberry.Rig
    local rig = {
        progress = 0,
        duration = duration or 1,
        easing = easing or camberry.tweens.smooth,
        stayAttached = false,
        reachedEnd = false,
        isAttached = false,
        sourceValues = sourceValues or {},
        targetValues = targetValues or {},
    }

    return setmetatable(rig, RigMT)
end

local random = _G["love"] and _G["love"].math.random or math.random
--------------------------------------------------
--- ### camberry.newShakeRig(intensity, duration, speed)
--- Creates a new rig intended for shaking a camera.
---@param intensity? number How many pixels out will the receiver shake
---@param duration? number How long the shake will last in seconds
---@param speed? number How many shakes per second will the shake happen at
---@param easing? string|fun(x: number):number
---@param xKey? string
---@param yKey? string
---@return Camberry.Rig shakeRig
function camberry.newShakeRig(intensity, duration, speed, easing, xKey, yKey)
    intensity = intensity or 10
    duration = duration or 1
    speed = speed or 30
    easing = easing or camberry.tweens.hold
    xKey = xKey or "_offsetX"
    yKey = yKey or "_offsetY"

    if speed <= 0 then error("Speed must be greater than 0", 2) end
    local delay = 1 / speed

    local shakeRig = camberry.newRig()
    shakeRig:setDuration(delay)
    shakeRig:setEasing(easing)
    shakeRig:source(xKey, 0)
    shakeRig:source(yKey, 0)

    local chainedRigCount = duration * speed
    for _ = 1, chainedRigCount do
        shakeRig:chain()
    end

    shakeRig.onReset = function (rig)
        local iteration = 1
        local previousRig
        while rig do
            local dist = lerp(intensity, 0, (iteration-1) / chainedRigCount)
            local angle = random() * math.pi * 2
            local x = math.cos(angle) * dist
            local y = math.sin(angle) * dist

            if previousRig then
                rig:source(xKey, previousRig.targetValues[xKey])
                rig:source(yKey, previousRig.targetValues[yKey])
            end
            rig:target(xKey, x)
            rig:target(yKey, y)

            iteration = iteration + 1
            previousRig = rig
            rig = rig.next
        end
    end

    return shakeRig
end

--------------------------------------------------
--- ### Rig:clone()
--- Returns a copy of the rig. Any rigs chained after this one are also cloned. (Cyclical chains will loop forever!)
---@return Camberry.Rig
function Rig:clone()
    local rig = camberry.newRig()
    rig.progress = self.progress
    rig.duration = self.duration
    rig.easing = self.easing

    rig.reachedEnd = self.reachedEnd
    rig.isAttached = false -- A newly cloned rig can't possibly be attached

    rig.onAttach = self.onAttach
    rig.onFinish = self.onFinish
    rig.onUpdate = self.onUpdate
    rig.onReset = self.onReset

    for key, value in pairs(self.sourceValues) do
        rig.sourceValues[key] = value
    end
    for key, value in pairs(self.targetValues) do
        rig.targetValues[key] = value
    end

    if self.next then rig.next = self.next:clone() end

    return rig
end

--------------------------------------------------
--- ### Rig:reset()
--- Resets the rig to an initial state. If `nonRecursive` is true, the rig will only reset this exact rig, and none of the chained ones.  
--- Note that it's probably not necessary to call this, as attaching a rig resets it automatically.
---@param nonRecursive? boolean
---@return Camberry.Rig self
function Rig:reset(nonRecursive)
    self.progress = 0
    self.reachedEnd = false

    if self.onReset then self.onReset(self) end

    if nonRecursive then return self end
    if self.next then self.next:reset(nonRecursive) end
    return self
end

--------------------------------------------------
--- ### Rig:setDuration(duration)
--- Sets the rig's animation duration.
---@param duration number
---@return Camberry.Rig self
function Rig:setDuration(duration)
    self.duration = duration
    return self
end

--------------------------------------------------
--- ### Rig:setEasing(easing)
--- Sets the rig's easing function.  
--- Instead of a function, you can also supply the name of an easing function stored in `camberry.tweens`.
---@param easing string|fun(x: number): number
---@return Camberry.Rig self
function Rig:setEasing(easing)
    if type(easing) == "string" then
        if not camberry.tweens[easing] then error("Unknown easing function: " .. easing, 2) end
        easing = camberry.tweens[easing]
    end

    self.easing = easing
    return self
end

--------------------------------------------------
--- ### Rig:setSourceValues(values)
--- Sets the rig's source values. These are the initial values the rig will interpolate from.
---@param values table<string, number>
---@return Camberry.Rig self
function Rig:setSourceValues(values)
    self.sourceValues = values
    return self
end

--------------------------------------------------
--- ### Rig:setTargetValues(values)
--- Sets the rig's target values. These are the values the rig will interpolate to (starting from the source values).
---@param values table<string, number>
---@return Camberry.Rig self
function Rig:setTargetValues(values)
    self.targetValues = values
    return self
end

--------------------------------------------------
--- ### Rig:addValue(key, source, target)
--- Adds a source-target pair of values to the rig for interpolation
---@param key string The field of the RigReceiver that will be animated
---@param source number The value the interpolation will start at
---@param target number The value the interpolation will end at
---@return Camberry.Rig self
function Rig:addValue(key, source, target)
    self.sourceValues[key] = source
    self.targetValues[key] = target
    return self
end

--------------------------------------------------
--- ### Rig:from(key, source)
--- ### Rig:source(key, source)
--- Adds a source value to the rig for interpolation. Make sure to also add a target value with the same key.
---@param key string
---@param source number
---@return Camberry.Rig self
function Rig:from(key, source)
    self.sourceValues[key] = source
    return self
end
Rig.source = Rig.from

--------------------------------------------------
--- ### Rig:to(key, target)
--- ### Rig:target(key, target)
--- Adds a target value to the rig for interpolation. Make sure to also add a source value with the same key.
---@param key string
---@param target number
---@return Camberry.Rig self
function Rig:to(key, target)
    self.targetValues[key] = target
    return self
end
Rig.target = Rig.to

--------------------------------------------------
--- ### Rig:setNext(rig)
--- Chains another rig after this rig to be played after this one finishes.  
--- If this rig already has a `next` rig set, it will be overwritten.  
--- The newly added rig will be returned.
---@param rig Camberry.Rig The rig to chain
---@return Camberry.Rig chainedRig The newly chained rig
function Rig:setNext(rig)
    self.next = rig
    return self
end

--------------------------------------------------
--- ### Rig:appendRig(rig)
--- Works like `Rig:setNext()`, but if the current rig already has a rig chained after it, it will not be replaced.
--- Instead, the newly added chain will be inserted into the middle of the chain at this rig's position.  
--- This function will loop forever if the rig you're adding has a cyclical reference or will cause a cyclical reference.  
--- 
--- Returns the newly added rig.
---@param rig Camberry.Rig The rig to chain
---@return Camberry.Rig chainedRig The newly chained rig
function Rig:appendRig(rig)
    local currentNext = self.next
    self.next = rig

    if currentNext then
        local chainEnd = rig

        --- The diagnostics are a little confused here
        ---@diagnostic disable-next-line: need-check-nil
        while chainEnd.next do
            chainEnd = chainEnd.next
        end

        chainEnd.next = currentNext
    end

    return rig
end

--------------------------------------------------
--- ### Rig:chain()
--- Extends the chain.  
--- 
--- This function creates a new rig, copies the easing and duration to it, and copies the target values into its source values.  
--- The new rig gets appended to the chain after this one and returned.  
--- This makes it handy to easily create a chain of rigs like so:
--- ```
--- -- Swing x to +100, then to -100, then back to 0
--- rig:addValue("x", 0, 100):chain():to("x", -100):chain():to("x", 0)
--- ```
--- If you want to add an already created rig to the chain, use `Rig:appendRig()` or `Rig:setNext()`.
---@return Camberry.Rig chainedRig The newly chained rig
function Rig:chain()
    local chainedRig = camberry.newRig()
    chainedRig.duration = self.duration
    chainedRig.easing = self.easing
    for key, value in pairs(self.targetValues) do
        chainedRig.sourceValues[key] = value
    end
    self:appendRig(chainedRig)
    return chainedRig
end

-- Easing functions --------------------------------------------------------------------------------

--- Easing functions for interpolation, intended for use with Rigs.
---@type table<string, fun(x: number): number>
camberry.tweens = {}

-- Most of these are implemented from https://easings.net/

function camberry.tweens.linear(x)
    return x
end

function camberry.tweens.hold(x)
    if x < 1 then return 0 end
    return 1
end

function camberry.tweens.instant(x)
    if x > 0 then return 1 end
    return 0
end

function camberry.tweens.sineIn(x)
    return 1 - math.cos((x * math.pi) / 2);
end

function camberry.tweens.sineOut(x)
    return math.sin((x * math.pi) / 2);
end

function camberry.tweens.sineInOut(x)
    return -(math.cos(x * math.pi) - 1) / 2;
end

function camberry.tweens.quadIn(x)
    return x * x
end

function camberry.tweens.quadOut(x)
    return 1 - (1 - x) * (1 - x)
end

function camberry.tweens.quadInOut(x)
    return x < 0.5 and 2 * x * x or 1 - math.pow(-2 * x + 2, 2) / 2
end

function camberry.tweens.cubicIn(x)
    return x * x * x
end

function camberry.tweens.cubicOut(x)
    return 1 - math.pow(1 - x, 3)
end

function camberry.tweens.cubicInOut(x)
    return x < 0.5 and 4 * x * x * x or 1 - math.pow(-2 * x + 2, 3) / 2
end

function camberry.tweens.quartIn(x)
    return x * x * x * x
end

function camberry.tweens.quartOut(x)
    return 1 - math.pow(1 - x, 4)
end

function camberry.tweens.quartInOut(x)
    return x < 0.5 and 8 * x * x * x * x or 1 - math.pow(-2 * x + 2, 4) / 2
end

function camberry.tweens.expoIn(x)
    return x == 0 and 0 or math.pow(2, 10 * x - 10)
end

function camberry.tweens.expoOut(x)
    return x == 1 and 1 or 1 - math.pow(2, -10 * x)
end

function camberry.tweens.expoInOut(x)
    if x == 0 then return x end
    if x == 1 then return x end
    if x < 0.5 then return math.pow(2, 20 * x - 10) / 2 end
    return (2 - math.pow(2, -20 * x + 10)) / 2
end

function camberry.tweens.backIn(x)
    local c1 = 1.70158
    local c3 = c1 + 1
    return c3 * x * x * x - c1 * x * x
end

function camberry.tweens.backOut(x)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * math.pow(x - 1, 3) + c1 * math.pow(x - 1, 2)
end

function camberry.tweens.backInOut(x)
    local c1 = 1.70158
    local c2 = c1 * 1.525
    if x < 0.5 then return (math.pow(2 * x, 2) * ((c2 + 1) * 2 * x - c2)) / 2 end
    return (math.pow(2 * x - 2, 2) * ((c2 + 1) * (x * 2 - 2) + c2) + 2) / 2
end

function camberry.tweens.elasticIn(x)
    local c4 = (2 * math.pi) / 3
    if x == 0 then return 0 end
    if x == 1 then return 1 end
    return -math.pow(2, 10 * x - 10) * math.sin((x * 10 - 10.75) * c4)
end

function camberry.tweens.elasticOut(x)
    local c4 = (2 * math.pi) / 3
    if x == 0 then return 0 end
    if x == 1 then return 1 end
    return math.pow(2, -10 * x) * math.sin((x * 10 - 0.75) * c4) + 1
end

function camberry.tweens.elasticInOut(x)
    local c5 = (2 * math.pi) / 4.5
    if x == 0 then return 0 end
    if x == 1 then return 1 end
    if x < 0.5 then return -(math.pow(2, 20 * x - 10) * math.sin((20 * x - 11.125) * c5)) / 2 end
    return (math.pow(2, -20 * x + 10) * math.sin((20 * x - 11.125) * c5)) / 2 + 1
end

function camberry.tweens.bounceIn(x)
    return 1 - camberry.tweens.bounceOut(1 - x)
end

function camberry.tweens.bounceOut(x)
    local n1 = 7.5625
    local d1 = 2.75

    if x < 1 / d1 then return n1 * x * x end
    if x < 2 / d1 then
        x = x - 1.5 / d1
        return n1 * x * x + 0.75 
    end
    if x < 2.5 / d1 then
        x = x - 2.25 / d1
        return n1 * x * x + 0.9375
    end
    x = x - 2.625 / d1
    return n1 * x * x + 0.984375
end

function camberry.tweens.bounceInOut(x)
    return x < 0.5
    and (1 - camberry.tweens.bounceOut(1 - 2 * x)) / 2
    or  (1 + camberry.tweens.bounceOut(2 * x - 1)) / 2
end

camberry.tweens.smooth = camberry.tweens.quadInOut
camberry.tweens.fling = camberry.tweens.expoInOut
camberry.tweens.bounce = camberry.tweens.bounceOut
camberry.tweens.easeIn = camberry.tweens.quadIn
camberry.tweens.easeOut = camberry.tweens.quadOut
camberry.tweens.easeInOut = camberry.tweens.quadInOut

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

camberry.Camera = Camera           -- The definition of the `Camera` class, mostly exposed for possible inheritance purposes
camberry.SimpleTarget = Target     -- The definition of the `SimpleTarget` class, mostly exposed for possible inheritance purposes
camberry.RigReceiver = RigReceiver -- The definition of the `RigReceiver` class, mostly exposed for possible inheritance purposes
camberry.Rig = Rig                 -- The definition of the `Rig` class, mostly exposed for possible inheritance purposes

return camberry