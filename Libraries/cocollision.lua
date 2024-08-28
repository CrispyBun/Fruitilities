local cocollision = {}

-- Definitions -------------------------------------------------------------------------------------

---@alias Cocollision.ShapeType
---| '"none"' # An empty shape that doesn't collide with anything
---| '"rectangle"' # An axis aligned rectangle

---@class Cocollision.Shape
---@field shapeType Cocollision.ShapeType
---@field x number
---@field y number
---@field vertices number[] A flat array of the shape's vertices (x and y are alternating)
local Shape = {}
local ShapeMT = {__index = Shape}

-- Shapes ------------------------------------------------------------------------------------------

--------------------------------------------------
--- ### cocollision.newShape()
--- Creates a new shape.
---@return Cocollision.Shape
function cocollision.newShape()
    ---@type Cocollision.Shape
    local shape = {
        shapeType = "none",
        x = 0,
        y = 0,
        vertices = {}
    }
    return setmetatable(shape, ShapeMT)
end

--------------------------------------------------
--- ### cocollision.newRectangleShape(x, y, width, height)
--- ### cocollision.newRectangleShape(width, height)
--- Creates a new axis aligned rectangle shape.
---@param x number
---@param y number
---@param width number
---@param height number
---@return Cocollision.Shape
---@overload fun(width: number, height: number): Cocollision.Shape
function cocollision.newRectangleShape(x, y, width, height)
    return cocollision.newShape():setShapeToRectangle(x, y, width, height)
end

--------------------------------------------------
--- ### Shape:removeShape()
--- Sets the shape type to "none" and removes all vertices.
---@return Cocollision.Shape self
function Shape:removeShape()
    self.shapeType = "none"
    self.vertices = {}
    return self
end

--------------------------------------------------
--- ### Shape:setShapeToRectangle(x, y, width, height)
--- ### Shape:setShapeToRectangle(width, height)
--- Sets the shape to be an axis aligned rectangle.
---@param x number
---@param y number
---@param width number
---@param height number
---@return Cocollision.Shape self
---@overload fun(self: Cocollision.Shape, width: number, height: number): Cocollision.Shape
function Shape:setShapeToRectangle(x, y, width, height)
    if not (width and height) then
        width = x
        height = y
        x = 0
        y = 0
    end

    self.shapeType = "rectangle"
    self.x = x
    self.y = y
    self.vertices = {
        x, y,
        x + width, y,
        x + width, y + height,
        x, y + height,
    }
    return self
end
Shape.setShapeToAABB = Shape.setShapeToRectangle

--------------------------------------------------
--- ### Shape:debugDraw(fullColor)
--- Draws the shape for debugging purposes (just visualises the shape's vertices, doesn't reflect the shape's type in any way).  
--- This is the only platform dependent function. If shape drawing isn't implemented, this function does nothing.
function Shape:debugDraw(fullColor)
    return cocollision.graphics.debugDrawShape(self, fullColor)
end

-- Abstraction for possible usage outside LÖVE -----------------------------------------------------
-- These are just for visual debugging, and arent't necessary for cocollision to work.

-- Can be replaced with functions to perform these actions in non-love2d environments
cocollision.graphics = {}

---@diagnostic disable-next-line: undefined-global
local love = love

local colorMild = {0.25, 0.5, 1, 0.25}
local colorFull = {0.25, 0.5, 1}

---@param shape Cocollision.Shape
---@param fullColor boolean
cocollision.graphics.debugDrawShape = function(shape, fullColor)
    local color = fullColor and colorFull or colorMild

    local vertices = shape.vertices

    local cr, cg, cb, ca = love.graphics.getColor()

    if #vertices >= 6 then
        love.graphics.setColor(color)
        love.graphics.polygon("fill", vertices)
    end

    if #vertices >= 4 then
        love.graphics.setColor(colorFull)
        love.graphics.line(vertices)
        love.graphics.line(vertices[#vertices-1], vertices[#vertices], vertices[1], vertices[2])
    end

    if #vertices >= 2 then
        love.graphics.setColor(colorFull)
        love.graphics.points(vertices)
    end

    love.graphics.setColor(cr, cg, cb, ca)
end

local emptyFunction = function () end
if not love then
    cocollision.graphics.debugDrawShape = emptyFunction
end

return cocollision