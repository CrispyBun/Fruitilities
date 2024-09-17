----------------------------------------------------------------------------------------------------
-- An eventful animation library
-- written by yours truly, CrispyBun.
-- crispybun@pm.me
-- https://github.com/CrispyBun/Fruitilities
----------------------------------------------------------------------------------------------------
--[[
MIT License

Copyright (c) 2024 Ava "CrispyBun" Špráchalů

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

local animango = {}

-- Definitions -------------------------------------------------------------------------------------

--- A single frame of animation.  
--- Comes with definitions for a LÖVE implementation, for use of Animango outside LÖVE, inject any fields necessary into this class.
---@class Animango.Frame
---@field event? Animango.AnimationEvent An event to be triggered when this frame plays
---@diagnostic disable-next-line: undefined-doc-name
---@field loveImage? love.Image The LÖVE image used to draw the frame
---@diagnostic disable-next-line: undefined-doc-name
---@field loveQuad? love.Quad The LÖVE quad used to crop the frame's image

---@class Animango.Animation
---@field frames Animango.Frame[] The frames in the animation
---@field fps number The frames per second of the animation
---@field originX number The origin on the X axis to draw the frames at
---@field originY number The origin on the Y axis to draw the frames at
---@field events table<Animango.AnimationEventType, Animango.AnimationEvent> Any events attached to the animation
local Animation = {}
local AnimationMT = {__index = Animation}

---@class Animango.Sprite
---@field x number The X position of the sprite
---@field y number The Y position of the sprite
---@field scaleX number The scale of the sprite on the X axis
---@field scaleY number The scale of the sprite on the Y axis
---@field rotation number The rotation of the sprite
---@field shearX number The shear of the sprite on the X axis
---@field shearY number The shear of the sprite on the Y axis
---@field playbackSpeed number Speed multiplier for the animation
---@field playbackSpeedMultiplier number Essentially the same thing as playbackSpeed (it stacks with it), but gets reset upon animation change. It is used internally by events.
---@field currentAnimation string The current active animation
---@field currentFrame number The current frame index within the animation
---@field currentIteration integer How many times the animation has looped back to the first frame
---@field animations table<string, Animango.Animation>
---@field events table<Animango.AnimationEventType, Animango.AnimationEvent> Any events attached to the sprite (used for any active animation)
local Sprite = {}
local SpriteMT = {__index = Sprite}

---@alias Animango.AnimationEvent
---| string # The controlling sprite will switch the current animation to the given string
---| number # The animation will switch the speed multiplier to the given value
---| fun(sprite: Animango.Sprite) # The function will be called, getting the controlling sprite as an argument

---@alias Animango.AnimationEventType
---| '"start"' # The animation has just started playing
---| '"loop"' # The animation has just finished playing and a new loop has started
---| '"frame"' # A new frame has been displayed
---| '"update"' # The animation playback has been updated

-- Sprites -----------------------------------------------------------------------------------------

--------------------------------------------------
--- ### animango.newSprite()
--- Creates a new blank animango sprite.
---@return Animango.Sprite
function animango.newSprite()
    ---@type Animango.Sprite
    local sprite = {
        x = 0,
        y = 0,
        scaleX = 1,
        scaleY = 1,
        rotation = 0,
        shearX = 0,
        shearY = 0,
        playbackSpeed = 1,
        playbackSpeedMultiplier = 1,
        currentAnimation = "default",
        currentFrame = 1,
        currentIteration = 1,
        animations = {},
        events = {}
    }
    return setmetatable(sprite, SpriteMT)
end

--------------------------------------------------
--- ### Sprite:addAnimation(name, animation)
--- Adds a new animation to the sprite.
---@param name string The name to identify the animation
---@param animation Animango.Animation The animation in question
---@return Animango.Sprite self
function Sprite:addAnimation(name, animation)
    self.animations[name] = animation
    return self
end

--------------------------------------------------
--- ### Sprite:instance()
--- Creates and returns a new instance of the sprite by generating a new sprite which references the same animations and events.
---@return Animango.Sprite
function Sprite:instance()
    ---@type Animango.Sprite
    local inst = {
        x = 0,
        y = 0,
        scaleX = 1,
        scaleY = 1,
        rotation = 0,
        shearX = 0,
        shearY = 0,
        playbackSpeed = 1,
        playbackSpeedMultiplier = 1,
        currentAnimation = "default",
        currentFrame = 1,
        currentIteration = 1,
        animations = self.animations,
        events = self.events
    }
    return setmetatable(inst, SpriteMT)
end

--------------------------------------------------
--- ### Sprite:clone()
--- Creates a copy of the sprite.
---@return Animango.Sprite
function Sprite:clone()
    ---@type Animango.Sprite
    local inst = {
        x = self.x,
        y = self.y,
        scaleX = self.scaleX,
        scaleY = self.scaleY,
        rotation = self.rotation,
        shearX = self.shearX,
        shearY = self.shearY,
        playbackSpeed = self.playbackSpeed,
        playbackSpeedMultiplier = self.playbackSpeedMultiplier,
        currentAnimation = self.currentAnimation,
        currentFrame = self.currentFrame,
        currentIteration = self.currentIteration,

        animations = {},
        events = {}
    }

    for key, value in pairs(self.animations) do
        inst.animations[key] = value
    end
    for key, value in pairs(self.events) do
        inst.events[key] = value
    end

    return setmetatable(inst, SpriteMT)
end

--------------------------------------------------
--- ### Sprite:setEvent(eventType, event)
--- Sets the given event of the sprite.
---@param eventType Animango.AnimationEventType
---@param event Animango.AnimationEvent
---@return Animango.Sprite self
function Sprite:setEvent(eventType, event)
    self.events[eventType] = event
    return self
end

--------------------------------------------------
--- ### Sprite:setPosition(x, y)
--- Sets the sprite's position.
---@param x number
---@param y number
---@return Animango.Sprite self
function Sprite:setPosition(x, y)
    self.x = x
    self.y = y
    return self
end

--------------------------------------------------
--- ### Sprite:setAnimation(animationName)
--- Sets the sprite's current animation and resets all the relevant variables.
---@param animationName string
---@return Animango.Sprite self
function Sprite:setAnimation(animationName)
    self.currentAnimation = animationName
    self.currentFrame = 1
    self.currentIteration = 1
    self.playbackSpeedMultiplier = 1
    return self
end

--------------------------------------------------
--- ### Sprite:changeAnimationFrom(requiredCurrentAnimation, animationName)
--- Like `Sprite:setAnimation()`, but only works if the current animation matches the one specified.
---@param requiredCurrentAnimation string
---@param animationName string
---@return Animango.Sprite self
function Sprite:changeAnimationFrom(requiredCurrentAnimation, animationName)
    if self.currentAnimation == requiredCurrentAnimation then
        return self:setAnimation(animationName)
    end
    return self
end

--------------------------------------------------
--- ### Sprite:setCurrentFrame(frame)
--- Sets the sprite's current frame in the animaton.
---@param frame number
---@return Animango.Sprite self
function Sprite:setCurrentFrame(frame)
    self.currentFrame = frame
    return self
end

--------------------------------------------------
--- ### Sprite:setScale(sx, sy)
--- Sets the sprite's scale. If `sy` is not supplied, sets both axes to the first argument.
---@param sx number Scale on the X axis
---@param sy? number Scale on the Y axis (Default is `sx`)
---@return Animango.Sprite self
function Sprite:setScale(sx, sy)
    self.scaleX = sx
    self.scaleY = sy or sx
    return self
end

--------------------------------------------------
--- ### Sprite:setRotation(rotation)
--- Sets the sprite's rotation.
---@param rotation number
---@return Animango.Sprite self
function Sprite:setRotation(rotation)
    self.rotation = rotation
    return self
end

--------------------------------------------------
--- ### Sprite:setShear(kx, ky)
--- Sets the sprite's shear.
---@param kx number Shear on the X axis
---@param ky number Shear on the Y axis
---@return Animango.Sprite
function Sprite:setShear(kx, ky)
    self.shearX = kx
    self.shearY = ky
    return self
end

--------------------------------------------------
--- ### Sprite:setPlaybackSpeed(speed)
--- Sets the sprite's speed multiplier for its animations.
---@param speed number
---@return Animango.Sprite self
function Sprite:setPlaybackSpeed(speed)
    self.playbackSpeed = speed
    return self
end

--------------------------------------------------
--- ### Sprite:getCurrentFrame()
--- Gets the sprite's current frame in the animaton.
--- If keepDecimal is true, the decimal part of the current frame is kept, signifying timer information.
--- Otherwise, the actual current frame index is returned.
---@param keepDecimal? boolean
---@return number
function Sprite:getCurrentFrame(keepDecimal)
    if keepDecimal then return self.currentFrame end
    return math.floor(self.currentFrame)
end

--------------------------------------------------
--- ### Sprite:getCurrentAnimation()
--- Returns the sprite's selected animation (string), and the animation object itself.
---@return string
---@return Animango.Animation?
function Sprite:getCurrentAnimation()
    local name = self.currentAnimation
    return name, self.animations[name]
end

--------------------------------------------------
--- ### Sprite:update(dt)
--- Update (and animate) the sprite.
---@param dt number The time in seconds since the last call to update
function Sprite:update(dt)
    local animation = self.animations[self.currentAnimation]
    if not animation then return end

    local fps = animation.fps

    -- currentFrame can be a decimal value, the actual displayed frame is currentFrame floored
    local lastFrame = self.currentFrame
    local nextFrame = self.currentFrame + dt * fps * self.playbackSpeed * self.playbackSpeedMultiplier

    local isVeryFirstFrame = self.currentIteration == 1 and lastFrame == 1
    local lastFrameActual = math.floor(lastFrame)
    local nextFrameActual = math.floor(nextFrame)
    local frameChanged = (lastFrameActual ~= nextFrameActual) or isVeryFirstFrame

    local frameCount = #animation.frames
    local looped = (nextFrame >= frameCount + 1) or (nextFrame ~= nextFrame) -- NaN check for 0-frame animation edge case
    nextFrame = ((nextFrame-1) % frameCount) + 1 -- loop the animation

    self.currentFrame = nextFrame

    if isVeryFirstFrame then
        if self.events.start then self:callEvent(self.events.start) end
        if animation.events.start then self:callEvent(animation.events.start) end
    end
    if looped then
        self.currentIteration = self.currentIteration + 1

        if self.events.loop then self:callEvent(self.events.loop) end
        if animation.events.loop then self:callEvent(animation.events.loop) end
    end
    if frameChanged then
        local frame = animation.frames[math.floor(nextFrame)]
        if frame and frame.event then self:callEvent(frame.event) end
        if self.events.frame then self:callEvent(self.events.frame) end
        if animation.events.frame then self:callEvent(animation.events.frame) end
    end
    if self.events.update then self:callEvent(self.events.update) end
    if animation.events.update then self:callEvent(animation.events.update) end
end

--------------------------------------------------
--- ### Sprite:draw()
--- Draws the sprite at its current position, or when supplied, at the specified position. All arguments are optional.
---@param x? number
---@param y? number
---@param r? number
---@param sx? number
---@param sy? number
---@param ox? number
---@param oy? number
---@param kx? number
---@param ky? number
function Sprite:draw(x, y, r, sx, sy, ox, oy, kx, ky)
    x = x or self.x
    y = y or self.y
    r = r or self.rotation
    sx = sx or self.scaleX
    sy = sy or self.scaleY
    kx = kx or self.shearX
    ky = ky or self.shearY

    local animation = self.animations[self.currentAnimation]
    if not animation then return animango.graphics.drawUnknownAnimationError(x, y) end

    ox = ox or animation.originX
    oy = oy or animation.originY

    local currentFrameIndex = self.currentFrame
    local frameCount = #animation.frames
    local frameIndex = math.floor(((currentFrameIndex-1) % frameCount) + 1)

    local frame = animation.frames[frameIndex]
    if not frame then return end -- there are no frames
    animango.graphics.drawFrame(frame, x, y, r, sx, sy, ox, oy, kx, ky)
end

--------------------------------------------------
--- ### Sprite:callEvent(event)
--- Calls the given event on the sprite. This is usually used internally.
---@param event Animango.AnimationEvent
function Sprite:callEvent(event)
    local eventType = type(event)
    if eventType == "string" then
        return self:setAnimation(event)
    end
    if eventType == "number" then
        self.playbackSpeedMultiplier = event
        return
    end
    if eventType == "function" then
        return event(self)
    end
    error("Unknown frame event type: " .. eventType, 2)
end

-- Animations --------------------------------------------------------------------------------------

--------------------------------------------------
--- ### animango.newAnimation()
--- Creates a new blank animation.  
--- You can optionally supply the FPS, origin and/or frames to it immediately, or you may add or generate them later using the appropriate methods.
--- 
--- Example usage:
--- ```
--- local animation = animango.newAnimation()
--- animation:setFps(24):setOrigin(8, 8) -- Methods are chainable
--- animation:appendFramesFromLoveImages({image1, image2, image3})
--- ```
---@param fps? number The FPS to play the animation at
---@param originX? number The X origin of the animation
---@param originY? number The Y origin of the animation
---@param frames? Animango.Frame[] The frames in this animation
---@return Animango.Animation
function animango.newAnimation(fps, originX, originY, frames)
    ---@type Animango.Animation
    local animation = {
        frames = frames or {},
        fps = fps or 1,
        originX = originX or 0,
        originY = originY or 0,
        events = {}
    }
    return setmetatable(animation, AnimationMT)
end

--------------------------------------------------
--- ### Animation:setFps(fps)
--- Sets the animation's frames per second.
---@param fps number
---@return Animango.Animation self
function Animation:setFps(fps)
    self.fps = fps
    return self
end

--------------------------------------------------
--- ### Animation:setOrigin(x, y)
--- Sets the animation's origin.
---@param x number
---@param y number
---@return Animango.Animation self
function Animation:setOrigin(x, y)
    self.originX = x
    self.originY = y
    return self
end

--------------------------------------------------
--- ### Animation:setEvent(eventType, event)
--- Sets the given event of the animation.  
--- For attaching an event to a specific frame of the animation, use `Animation:setFrameEvent()`.
---@param eventType Animango.AnimationEventType
---@param event Animango.AnimationEvent
---@return Animango.Animation self
function Animation:setEvent(eventType, event)
    self.events[eventType] = event
    return self
end

--------------------------------------------------
--- ### Animation:setFrameEvent(frameIndex, event)
--- Attaches an animation event to the frame at the specified index (the event will be called when that frame is played).  
--- A negative frameIndex can be used to index from the end of the animation.  
--- If the frame already has an event assigned to it, it gets overwritten.
---@param frameIndex integer
---@param event Animango.AnimationEvent
---@return Animango.Animation self
function Animation:setFrameEvent(frameIndex, event)
    if frameIndex < 0 then frameIndex = #self.frames + frameIndex + 1 end
    local frame = self.frames[frameIndex]
    if not frame then error("No frame found at index " .. tostring(frameIndex), 2) end

    frame.event = event
    return self
end

--------------------------------------------------
--- ### Animation:appendFrame(frame)
--- Appends a single new frame to the animation.
---@param frame Animango.Frame
---@return Animango.Animation self
function Animation:appendFrame(frame)
    self.frames[#self.frames+1] = frame
    return self
end

--------------------------------------------------
--- ### Animation:appendFrames(frames)
--- Appends new frames to the animation.
---@param frames Animango.Frame[]
---@return Animango.Animation self
function Animation:appendFrames(frames)
    for frameIndex = 1, #frames do
        self.frames[#self.frames+1] = frames[frameIndex]
    end
    return self
end

--------------------------------------------------
--- ### Animation:appendFrameFromLoveImage(image)
--- Appends one new frame to the animation generated from a LÖVE image.
---@diagnostic disable-next-line: undefined-doc-name
---@param image love.Image
---@return Animango.Animation self
function Animation:appendFrameFromLoveImage(image)
    local frames = self.frames
    frames[#frames+1] = {
        loveImage = image
    }
    return self
end

--------------------------------------------------
--- ### Animation:appendFramesFromLoveImages(images)
--- Appends new frames to the animation generated from a list of LÖVE images.
---@diagnostic disable-next-line: undefined-doc-name
---@param images love.Image[]
---@return Animango.Animation self
function Animation:appendFramesFromLoveImages(images)
    local frames = self.frames
    for imageIndex = 1, #images do
        local image = images[imageIndex]
        frames[#frames+1] = {
            loveImage = image
        }
    end
    return self
end

--------------------------------------------------
--- ### Animation:appendFramesFromLoveQuads(image, quads)
--- Appends new frames to the animation generated from a LÖVE image and a list of quads.  
--- Each quad can either be a LÖVE Quad or a table in the format of `{x, y, width, height}`.
---@diagnostic disable-next-line: undefined-doc-name
---@param image love.Image
---@diagnostic disable-next-line: undefined-doc-name
---@param quads (love.Quad|number[])[]
---@return Animango.Animation self
function Animation:appendFramesFromLoveQuads(image, quads)
    ---@diagnostic disable-next-line: undefined-global
    if not love then error("appendFramesFromLoveQuads is only available inside the LÖVE engine", 2) end

    local frames = self.frames
    for quadIndex = 1, #quads do
        local quad = quads[quadIndex]
        if type(quad) == "table" then
            if not type(quad[1]) == "number"
            or not type(quad[2]) == "number"
            or not type(quad[3]) == "number"
            or not type(quad[4]) == "number" then
                error("Quad table is in invalid format", 2)
            end
            ---@diagnostic disable-next-line: undefined-global, undefined-field
            quad = love.graphics.newQuad(quad[1], quad[2], quad[3], quad[4], image:getDimensions())
        end
        frames[#frames+1] = {
            loveImage = image,
            loveQuad = quad
        }
    end
    return self
end

--------------------------------------------------
--- ### Animation:appendFramesFromLoveSpritesheet(image, tileWidth, tileHeight)
--- Appends new frames to the animation generated from a LÖVE image,
--- splitting the image up as a spritesheet where each cell has the specified width and height.
---
--- A crop value can be provided to crop each cell of the spritesheet by that amount in each direction (format is `{cropLeft, cropTop, cropRight, cropBottom}`, or just a single number for all directions).
---
--- A start and end index can be provided to only use those frames from the spritesheet (1 is top-left cell, 2 is the second in the first row, etc).
---
--- Example usage:
--- ```
--- animation:appendFramesFromLoveSpritesheet(spritesheet, 8, 8) -- Splits a spritesheet of 8x8 cells into frames
--- animation:appendFramesFromLoveSpritesheet(spritesheet, 16, 16, {1, 1, 1, 1}, 1, 10) -- Splits a spritesheet of 16x16 cells into frames, cropping 1 pixel from each side, and only using frames 1 through 10
--- animation:appendFramesFromLoveSpritesheet(spritesheet, 16, 16, 1, 1, 10) -- Same as above, but with a more concise way to write the crop value
--- ```
---@diagnostic disable-next-line: undefined-doc-name
---@param image love.Image
---@param tileWidth number
---@param tileHeight number
---@param crop? {[1]: number, [2]: number, [3]: number, [4]: number}|number
---@param startIndex? integer
---@param endIndex? integer
---@return Animango.Animation self
function Animation:appendFramesFromLoveSpritesheet(image, tileWidth, tileHeight, crop, startIndex, endIndex)
    ---@diagnostic disable-next-line: undefined-global
    if not love then error("appendFramesFromLoveSpritesheet is only available inside the LÖVE engine", 2) end

    crop = crop or 0
    startIndex = startIndex or 1
    endIndex = endIndex or math.huge

    if type(crop) == "number" then crop = {crop, crop, crop, crop} end
    if startIndex < 1 then error("startIndex cannot be less than 1", 2) end
    if endIndex < startIndex then error("endIndex cannot be less than startIndex", 2) end
    if tileWidth < 0 then error("tileWidth can't be negative", 2) end
    if tileHeight < 0 then error("tileHeight can't be negative", 2) end

    ---@diagnostic disable-next-line: undefined-field
    local imageWidth, imageHeight = image:getDimensions()
    local gridColumns = math.floor(imageWidth / tileWidth)
    local gridRows = math.floor(imageHeight / tileHeight)
    local cellCount = gridColumns * gridRows

    startIndex = math.min(startIndex, cellCount)
    endIndex = math.min(endIndex, cellCount)

    local frames = self.frames
    for cellIndex = startIndex, endIndex do
        local cellX = (cellIndex - 1) % gridColumns
        local cellY = math.floor((cellIndex - 1) / gridColumns)
        local x = cellX * tileWidth
        local y = cellY * tileHeight
        local w = tileWidth
        local h = tileHeight

        x = x + crop[1]
        y = y + crop[2]
        w = w - crop[1] - crop[3]
        h = h - crop[2] - crop[4]

        frames[#frames+1] = {
            loveImage = image,
            ---@diagnostic disable-next-line: undefined-global
            loveQuad = love.graphics.newQuad(x, y, w, h, imageWidth, imageHeight)
        }
    end

    return self
end

-- Frames ------------------------------------------------------------------------------------------

--------------------------------------------------
--- ### animango.newFrame(data)
--- Creates a new animango frame.
--- 
--- Note that the definition of an animango frame is just a table, and so by default,
--- this function is nothing but a shallow copy of a table.  
--- You likely won't need to call this manually for most purposes,
--- and instead just use the frame-generating methods on animations.
---@param data? table Any values you want to copy over to the frame table
---@return Animango.Frame
function animango.newFrame(data)
    local frame = {}
    if not data then return frame end

    for key, value in pairs(data) do
        frame[key] = value
    end
    return frame
end


-- Abstraction for possible usage outside LÖVE -----------------------------------------------------

-- Can be replaced with functions to perform these actions in non-love2d environments
animango.graphics = {}

---@diagnostic disable-next-line: undefined-global
local love = love

---@param frame Animango.Frame
---@param x? number
---@param y? number
---@param r? number
---@param sx? number
---@param sy? number
---@param ox? number
---@param oy? number
---@param kx? number
---@param ky? number
function animango.graphics.drawFrame(frame, x, y, r, sx, sy, ox, oy, kx, ky)
    if not frame.loveImage then return end
    x = x or 0
    y = y or 0

    if frame.loveQuad then
        love.graphics.draw(frame.loveImage, frame.loveQuad, x, y, r, sx, sy, ox, oy, kx, ky)
    else
        love.graphics.draw(frame.loveImage, x, y, r, sx, sy, ox, oy, kx, ky)
    end
end

---@param x? number
---@param y? number
function animango.graphics.drawUnknownAnimationError(x, y)
    x = x or 0
    y = y or 0
    local cr, cg, cb, ca = love.graphics.getColor()
    love.graphics.setColor(1, 0, 0)

    love.graphics.line(x - 50, y - 50, x + 50, y + 50)
    love.graphics.line(x + 50, y - 50, x - 50, y + 50)

    love.graphics.setColor(cr, cg, cb, ca)
end

local emptyFunction = function () end
if not love then
    animango.drawFrame = emptyFunction
    animango.drawUnknownAnimationError = emptyFunction
end

animango.Sprite = Sprite       -- The definition of the `Sprite` class, mostly exposed for possible inheritance purposes
animango.Animation = Animation -- The definition of the `Animation` class, mostly exposed for possible inheritance purposes

return animango