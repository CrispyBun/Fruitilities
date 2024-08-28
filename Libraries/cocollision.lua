local cocollision = {}

-- Definitions -------------------------------------------------------------------------------------

---@alias Cocollision.Vertex [number, number]

---@alias Cocollision.ShapeType
---| '"none"' # An empty shape that doesn't collide with anything
---| '"rectangle"' # An axis aligned rectangle

---@class Cocollision.Shape
---@field shapeType Cocollision.ShapeType
---@field x number
---@field y number
---@field vertices Cocollision.Vertex[]
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
        {x, y},
        {x + width, y},
        {x + width, y + height},
        {x, y + height}
    }
    return self
end
Shape.setShapeToAABB = Shape.setShapeToRectangle

return cocollision