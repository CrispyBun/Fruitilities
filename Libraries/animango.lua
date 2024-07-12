local animango = {}

-- Definitions -------------------------------------------------------------------------------------

--- A single frame of animation.  
--- Comes with definitions for a LÖVE implementation, for use of Animango outside LÖVE, inject any fields necessary into this class.
---@class Animango.Frame
---@diagnostic disable-next-line: undefined-doc-name
---@field loveImage? love.Image The LÖVE image used to draw the frame
---@diagnostic disable-next-line: undefined-doc-name
---@field loveQuad? love.Quad The LÖVE quad used to crop the frame's image

---@class Animango.Animation
---@field frames Animango.Frame[]
---@field fps number
local Animation = {}
local AnimationMT = {__index = Animation}

---@class Animango.Sprite
---@field x number The X position of the sprite
---@field y number The Y position of the sprite
---@field scaleX number The scale of the sprite on the X axis
---@field scaleY number The scale of the sprite on the Y axis
---@field rotation number The rotation of the sprite
---@field currentAnimation string The current active animation
---@field currentFrame number The current frame index within the animation
---@field animations table<string, Animango.Animation>
local Sprite = {}
local SpriteMT = {__index = Sprite}

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
        currentAnimation = "default",
        currentFrame = 1,
        animations = {}
    }
    return setmetatable(sprite, SpriteMT)
end

--------------------------------------------------
--- ### Sprite:addAnimation()
--- Adds a new animation to the sprite.
---@param name string The name to identify the animation
---@param animation Animango.Animation The animation in question
---@return Animango.Sprite self
function Sprite:addAnimation(name, animation)
    self.animations[name] = animation
    return self
end

--------------------------------------------------
--- ### Sprite:setPosition()
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
--- ### Sprite:setAnimation()
--- Sets the sprite's current animation (and resets current frame to 1).
---@param animationName string
---@return Animango.Sprite self
function Sprite:setAnimation(animationName)
    self.currentAnimation = animationName
    self.currentFrame = 1
    return self
end

--------------------------------------------------
--- ### Sprite:setCurrentFrame()
--- Sets the sprite's current frame in the animaton.
---@param frame number
---@return Animango.Sprite self
function Sprite:setCurrentFrame(frame)
    self.currentFrame = frame
    return self
end

--------------------------------------------------
--- ### Sprite:setScale()
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
--- ### Sprite:setRotation()
--- Sets the sprite's rotation.
---@param rotation number
---@return Animango.Sprite self
function Sprite:setRotation(rotation)
    self.rotation = rotation
    return self
end

--------------------------------------------------
--- ### Sprite:draw()
--- Draws the sprite at its current position.
function Sprite:draw()
    return self:drawAt(self.x, self.y)
end

--------------------------------------------------
--- ### Sprite:drawAt()
--- Draws the sprite at the specified position.
---@param x number
---@param y number
---@param r? number
---@param sx? number
---@param sy? number
function Sprite:drawAt(x, y, r, sx, sy)
    r = r or self.rotation
    sx = sx or self.scaleX
    sy = sy or self.scaleY

    local animation = self.animations[self.currentAnimation]
    if not animation then return animango.graphics.drawUnknownAnimationError(x, y) end

    local currentFrameIndex = self.currentFrame
    local frameCount = #animation.frames
    local frameIndex = math.floor(((currentFrameIndex-1) % frameCount) + 1)

    local frame = animation.frames[frameIndex]
    if not frame then return end -- there are no frames
    animango.graphics.drawFrame(frame, x, y, r, sx, sy)
end

-- Animations --------------------------------------------------------------------------------------

--------------------------------------------------
--- ### animango.newAnimation()
--- Creates a new animation.  
--- You can optionally supply the frames and/or FPS to it immediately, or you may add or generate them later using the appropriate methods
---@param frames? Animango.Frame[] The frames in this animation
---@param fps? number The FPS to play the animation at
---@return Animango.Animation
function animango.newAnimation(frames, fps)
    ---@type Animango.Animation
    local animation = {
        frames = frames or {},
        fps = fps or 1
    }
    return setmetatable(animation, AnimationMT)
end

--------------------------------------------------
--- ### Animation:setFps()
--- Sets the animation's frames per second.
---@param fps number
---@return Animango.Animation self
function Animation:setFps(fps)
    self.fps = fps
    return self
end

--------------------------------------------------
--- ### Animation:appendFrame()
--- Appends a single new frame to the animation.
---@param frame Animango.Frame
---@return Animango.Animation self
function Animation:appendFrame(frame)
    self.frames[#self.frames+1] = frame
    return self
end

--------------------------------------------------
--- ### Animation:appendFrames()
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
--- ### Animation:appendFrameFromLoveImage()
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
--- ### Animation:appendFramesFromLoveImages()
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
--- ### Animation:appendFramesFromLoveQuads()
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
--- ### Animation:appendFramesFromLoveSpritesheet()
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

return animango