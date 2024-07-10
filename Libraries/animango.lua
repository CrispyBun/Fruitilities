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
function Animation:appendFramesFromLoveImage(image)
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
---@param width number
---@param height number
---@param crop? {[1]: number, [2]: number, [3]: number, [4]: number}|number
---@param startIndex? integer
---@param endIndex? integer
---@return Animango.Animation self
function Animation:appendFramesFromLoveSpritesheet(image, width, height, crop, startIndex, endIndex)
    ---@diagnostic disable-next-line: undefined-global
    if not love then error("appendFramesFromLoveSpritesheet is only available inside the LÖVE engine", 2) end

    crop = crop or 0
    startIndex = startIndex or 1
    endIndex = endIndex or math.huge

    if type(crop) == "number" then crop = {crop, crop, crop, crop} end
    if startIndex < 1 then error("startIndex cannot be less than 1", 2) end
    if endIndex < startIndex then error("endIndex cannot be less than startIndex", 2) end
    if width < 0 then error("width can't be negative", 2) end
    if height < 0 then error("height can't be negative", 2) end

    ---@diagnostic disable-next-line: undefined-field
    local imageWidth, imageHeight = image:getDimensions()
    local gridColumns = math.floor(imageWidth / width)
    local gridRows = math.floor(imageHeight / height)
    local cellCount = gridColumns * gridRows

    startIndex = math.min(startIndex, cellCount)
    endIndex = math.min(endIndex, cellCount)

    local frames = self.frames
    for cellIndex = startIndex, endIndex do
        local cellX = (cellIndex - 1) % gridColumns
        local cellY = math.floor((cellIndex - 1) / gridColumns)
        local x = cellX * width
        local y = cellY * height
        local w = width
        local h = height

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

return animango