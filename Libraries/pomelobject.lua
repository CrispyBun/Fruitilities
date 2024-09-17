----------------------------------------------------------------------------------------------------
-- An objectifying GameObject library
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

local pomelobject = {}

---@diagnostic disable-next-line: deprecated
local unpack = table.unpack or unpack
local PATH = (...):match("(.-)[^%.]+$")

-- You can edit these lines to require the libraries yourself if the auto-search doesn't find them:
local animango
local cocollision
local camberry

if not animango then _, animango = pcall(require, PATH .. 'animango') end
if not animango then _, animango = pcall(require, 'animango') end
if not animango then _, animango = pcall(require, 'lib.animango') end
if not animango then error("Pomelobject requires the animango library, and can't find it") end

if not cocollision then _, cocollision = pcall(require, PATH .. 'cocollision') end
if not cocollision then _, cocollision = pcall(require, 'cocollision') end
if not cocollision then _, cocollision = pcall(require, 'lib.cocollision') end
if not cocollision then error("Pomelobject requires the cocollision library, and can't find it") end

if not camberry then _, camberry = pcall(require, PATH .. 'camberry') end
if not camberry then _, camberry = pcall(require, 'camberry') end
if not camberry then _, camberry = pcall(require, 'lib.camberry') end
if not camberry then error("Pomelobject requires the camberry library, and can't find it") end

local Sprite = animango.Sprite
local Shape = cocollision.Shape
local RigReceiver = camberry.RigReceiver

-- Definitions -------------------------------------------------------------------------------------

---@class Pomelobject.GameObject : Animango.Sprite, Cocollision.Shape, Camberry.RigReceiver
local GameObject = {}
local GameObjectMT = {__index = GameObject}

-- Object creation ---------------------------------------------------------------------------------

--------------------------------------------------
--- ### pomelobject.newGameObject()
--- Creates a new GameObject.
---@return Pomelobject.GameObject
function pomelobject.newGameObject()
    ---@type Pomelobject.GameObject
    local object = {
        -- Shared values
        x = 0,
        y = 0,
        scaleX = 1,
        scaleY = 1,
        rotation = 0,
        originX = 0,
        originY = 0,

        -- Sprite values
        currentAnimation = "default",
        shearX = 0,
        shearY = 0,
        playbackSpeed = 1,
        playbackSpeedMultiplier = 1,
        currentFrame = 1,
        currentIteration = 1,
        animations = {},
        animationEvents = {},

        -- Shape values
        shapeType = "none",
        translateX = 0, -- Translate is a shape-only property. Maybe it should be in sprites too?
        translateY = 0,
        doRectangularRotation = false,
        vertices = {},
        transformedVertices = {},
        boundingBox = {},

        -- RigReceiver values
        attachedRigs = {},
        waitForAllRigs = false,
        stackableRigValues = {}
    }
    return setmetatable(object, GameObjectMT)
end
pomelobject.newObject = pomelobject.newGameObject

-- Implementation ----------------------------------------------------------------------------------

for key, method in pairs(RigReceiver) do
    GameObject[key] = method
end
for key, method in pairs(Shape) do
    GameObject[key] = method
end
for key, method in pairs(Sprite) do
    GameObject[key] = method
end

--------------------------------------------------
--- ### GameObject:instance()
--- Creates a new instance of the same GameObject
--- by generating a new object that references the same `animations` table, `animationEvents` table,
--- and copies over all the shape-exclusive properties.
---@return Pomelobject.GameObject
function GameObject:instance()
    local inst = pomelobject.newGameObject()

    inst.animations = self.animations
    inst.animationEvents = self.animationEvents

    inst.shapeType = self.shapeType
    inst.doRectangularRotation = self.doRectangularRotation
    inst.vertices = {unpack(self.vertices)}

    -- Since translate is a shape-only property, and shape properties should be copied,
    -- it gets copied too. This shouldn't be the case though if sprites also implement translate at some point.
    inst.translateX = self.translateX
    inst.translateY = self.translateY

    return inst
end

--------------------------------------------------
--- ### GameObject:clone()
--- Creates a copy of the GameObject.
---@return Pomelobject.GameObject
function GameObject:clone()
    ---@type Pomelobject.GameObject
    local copy = pomelobject.newGameObject()

    -- Base values
    for key, value in pairs(self) do
        if type(value) == "table" then
            copy[key] = {} -- Tables need new references, values will be copied in after
        else
            copy[key] = value
        end
    end

    -- Deeper copies
    for key, value in pairs(self.animations) do
        copy.animations[key] = value
    end
    for key, value in pairs(self.animationEvents) do
        copy.animationEvents[key] = value
    end
    for key, value in pairs(self.stackableRigValues) do
        copy.stackableRigValues[key] = value
    end
    copy.vertices = {unpack(self.vertices)}

    return copy
end

--------------------------------------------------
--- ### GameObject:update(dt)
--- Updates the object. Animates sprites and updates its attached rigs (if any).
---@param dt number The time in seconds since the last call to update
function GameObject:update(dt)
    Sprite.update(self, dt)
    self:updateRigs(dt)
end

-- Transform setting methods need to come from the Shape class;
-- they are identical in both, but the Shape class also refreshes its cached transform after.

GameObject.setOrigin = Shape.setOrigin
GameObject.setScale = Shape.setScale
GameObject.setRotation = Shape.setRotation
GameObject.setTranslate = Shape.setTranslate

return pomelobject