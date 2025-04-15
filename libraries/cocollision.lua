----------------------------------------------------------------------------------------------------
-- A shaped up collision library
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

local cocollision = {}

---@diagnostic disable-next-line: deprecated
local unpack = table.unpack or unpack

-- Config stuff ------------------------------------------------------------------------------------

-- If this is 0, resolving collisions with the push vector will resolve the shapes
-- into a position where they are just barely touching.  
-- This is just a number added to the push vector's distance to make sure the collision is fully resolved.
cocollision.pushVectorIncrease = 1e-10

-- Shapes for which a bounding box is not calculated or checked.  
-- There's likely no reason for you to change this table, unless you're adding your own shape types.
cocollision.boundlessShapes = {
    none = true,
    ray = true,
    line = true,
}

-- If a circle shape gets turned into a polygon using `Shape:polygonify()`, this is the amount of segments the resulting polygon will have.
cocollision.polygonCircleSegments = 16

cocollision.doPushVectorCalculation = true -- If false, collisions that normally calculate a push vector will not calculate or return it

-- Definitions -------------------------------------------------------------------------------------

---@alias Cocollision.ShapeType
---| '"none"' # An empty shape that doesn't collide with anything
---| '"point"' # A single vertex
---| '"edge"' # A line segment
---| '"ray"' # A ray (half-line)
---| '"line"' # An infinite line
---| '"rectangle"' # An axis aligned rectangle
---| '"polygon"' # A convex polygon
---| '"circle"' # A circle
---| '"donut"' # A donut (annulus) shape, because why not

---@class Cocollision.Shape
---@field shapeType Cocollision.ShapeType
---@field x number The X position of the shape
---@field y number The Y position of the shape
---@field rotation number The rotation of the shape. If you change this value directly, call `Shape:refreshTransform()` to put the change into effect.
---@field scaleX number The scale of the shape on the X axis. If you change this value directly, call `Shape:refreshTransform()` to put the change into effect.
---@field scaleY number The scale of the shape on the Y axis. If you change this value directly, call `Shape:refreshTransform()` to put the change into effect.
---@field originX number The X coordinate of the origin to transform the shape around. If you change this value directly, call `Shape:refreshTransform()` to put the change into effect.
---@field originY number The Y coordinate of the origin to transform the shape around. If you change this value directly, call `Shape:refreshTransform()` to put the change into effect.
---@field translateX number The amount to translate the shape on the X axis. Unlike the X position, this is actually baked into the shape's transform. If you change this value directly, call `Shape:refreshTransform()` to put the change into effect.
---@field translateY number The amount to translate the shape on the Y axis. Unlike the Y position, this is actually baked into the shape's transform. If you change this value directly, call `Shape:refreshTransform()` to put the change into effect.
---@field doRectangularRotation boolean By default, `rectangle` shape types do not rotate. If this is true, this shape will rotate even if its type is `rectangle`.
---@field vertices number[] A flat array of the shape's vertices (x and y are alternating). You may change these directly, but `Shape:refreshTransform()` should be called afterwards to put the change into effect.
---@field transformedVertices number[] The shape's vertices after being transformed (set automatically). This table may be empty or incorrect if indexed directly, to ensure you get the updated vertices, use `Shape:getTransformedVertices()`.
---@field boundingBox number[] The transformed vertices' bounding box (set automatically). This table may be empty or incorrect if indexed directly, to ensure you get the updated bounding box, use `Shape:getBoundingBox()`. For consistency with other vertices in the library, the bounding box contains all four corners, not just two.
---@field owner? any Doesn't do anything, but can be useful to set to an object that this shape belongs to, to be able to easily find it in collisions.
local Shape = {}
local ShapeMT = {__index = Shape}

---@class Cocollision.SpatialPartition
---@field shapes table<Cocollision.Shape, [integer, integer, integer, integer]> The shapes in the partition and the range of cells they occupy
---@field cellSize number The size of each cell in the grid. This shouldn't be changed after creation.
---@field cells table<string, Cocollision.Shape[]> The individual cells of the grid and the shapes contained in them. The keys are in the format of `"x;y"`, a string made from the cell's position. This was the easiest way to make an infinite grid and still seems to perform fast.
local SpatialPartition = {}
local SpatialPartitionMT = {__index = SpatialPartition}

-- Misc functions ----------------------------------------------------------------------------------

--------------------------------------------------
--- ### cocollision.lineParameterToCoordinates(line, t)
--- Converts a parameter of a line to the position in space it represents.  
--- The line can be a line/ray/edge Shape object or a flat table of vertices defining the line.
---@param line Cocollision.Shape|number[] The line
---@param t number The parameter
---@return number x The X coordinate
---@return number y The Y coordinate
function cocollision.lineParameterToCoordinates(line, t)
    local vertices = line.vertices or line
    local offsetX = line.x or 0
    local offsetY = line.y or 0

    local x1, y1 = vertices[1] + offsetX, vertices[2] + offsetY
    local x2, y2 = vertices[3] + offsetX, vertices[4] + offsetY
    local dx = x2 - x1
    local dy = y2 - y1
    return x1 + dx * t, y1 + dy * t
end

--------------------------------------------------
--- ### cocollision.transformVertices(vertices, translateX, translateY, originX, originY)
--- Transforms the given vertices in place.
---@param vertices number[] A flat array of the vertices to transform (with alternating x and y values)
---@param translateX number The amount to translate the vertices on the X axis
---@param translateY number The amount to translate the vertices on the Y axis
---@param originX number The X coordinate of the origin
---@param originY number The Y coordinate of the origin
function cocollision.transformVertices(vertices, translateX, translateY, rotation, scaleX, scaleY, originX, originY)
    for vertexIndex = 1, #vertices, 2 do
        local x = vertices[vertexIndex]
        local y = vertices[vertexIndex + 1]

        x = x - originX
        y = y - originY

        if rotation ~= 0 then
            local sinr = math.sin(rotation)
            local cosr = math.cos(rotation)
            local xRotated = x * cosr - y * sinr
            local yRotated = x * sinr + y * cosr
            x = xRotated
            y = yRotated
        end

        x = x * scaleX
        y = y * scaleY

        x = x + translateX
        y = y + translateY

        vertices[vertexIndex] = x
        vertices[vertexIndex + 1] = y
    end
end

--------------------------------------------------
--- ### cocollision.generateBoundingBox(vertices)
--- Generates and returns a bounding box from a set of vertices. The outputted table contains all four vertices of the bounding box, not just the two corners.  
--- You can also supply a table as the second argument to have it receive the bounding box, instead of a new table being created.
---@param vertices number[]
---@param _receivingTable? table
---@return number[]
function cocollision.generateBoundingBox(vertices, _receivingTable)
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for vertexIndex = 1, #vertices, 2 do
        local x = vertices[vertexIndex]
        local y = vertices[vertexIndex + 1]
        minX = math.min(minX, x)
        minY = math.min(minY, y)
        maxX = math.max(maxX, x)
        maxY = math.max(maxY, y)
    end

    _receivingTable = _receivingTable or {}
    for vertexIndex = 1, #_receivingTable do
        _receivingTable[vertexIndex] = nil
    end
    if #vertices == 0 then -- No vertices, just make bbox 0,0,0,0
        _receivingTable[1] = 0
        _receivingTable[2] = 0
        _receivingTable[3] = 0
        _receivingTable[4] = 0
        _receivingTable[5] = 0
        _receivingTable[6] = 0
        _receivingTable[7] = 0
        _receivingTable[8] = 0
        return _receivingTable
    end

    _receivingTable[1] = minX
    _receivingTable[2] = minY

    _receivingTable[3] = maxX
    _receivingTable[4] = minY

    _receivingTable[5] = maxX
    _receivingTable[6] = maxY

    _receivingTable[7] = minX
    _receivingTable[8] = maxY

    return _receivingTable
end

--------------------------------------------------
--- ### cocollision.boundsIntersect(bbox1, bbox2)
--- Checks if two bounding boxes intersect.
---@param bbox1 number[]
---@param bbox2 number[]
---@param x1? number
---@param y1? number
---@param x2? number
---@param y2? number
---@return boolean
function cocollision.boundsIntersect(bbox1, bbox2, x1, y1, x2, y2)
    -- Allow for: `x1, y1, x2, y2, x3, y3, x4, y4`
    local ax1, ay1, ax2, ay2 = bbox1[1], bbox1[2], bbox1[5], bbox1[6]
    local bx1, by1, bx2, by2 = bbox2[1], bbox2[2], bbox2[5], bbox2[6]

    -- Allow for: `x1, y1, x2, y2`
    ax2 = ax2 or bbox1[3]
    ay2 = ay2 or bbox1[4]
    bx2 = bx2 or bbox2[3]
    by2 = by2 or bbox2[4]

    -- Offset
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0
    ax1 = ax1 + x1
    ay1 = ay1 + y1
    ax2 = ax2 + x1
    ay2 = ay2 + y1
    bx1 = bx1 + x2
    by1 = by1 + y2
    bx2 = bx2 + x2
    by2 = by2 + y2

    if ax1 > bx2 then return false end
    if ax2 < bx1 then return false end
    if ay1 > by2 then return false end
    if ay2 < by1 then return false end
    return true
end

-- Shapes ------------------------------------------------------------------------------------------

--------------------------------------------------
--- ### cocollision.newShape()
--- Creates a new shape.
---@return Cocollision.Shape
function cocollision.newShape()
    -- new Cocollision.Shape
    local shape = {
        shapeType = "none",
        x = 0,
        y = 0,
        rotation = 0,
        scaleX = 1,
        scaleY = 1,
        originX = 0,
        originY = 0,
        translateX = 0,
        translateY = 0,
        doRectangularRotation = false,
        vertices = {},
        transformedVertices = {},
        boundingBox = {},
    }
    return setmetatable(shape, ShapeMT)
end

--------------------------------------------------
--- ### cocollision.newRectangleShape(x, y, width, height)
--- ### cocollision.newRectangleShape(width, height)
--- Creates a new axis aligned rectangle shape.  
--- Rectangles output a push vector as the second argument in collisions with other rectangles, polygons or circles.
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
--- ### cocollision.newPolygonShape(...)
--- ### cocollision.newPolygonShape(vertices)
--- Creates a new convex polygon shape. The vertices may be supplied as alternating X and Y coordinates in either a single flat array or a vararg. The polygon shape type also supports any amount of vertices, and can be basically a point or a segment.  
--- Polygons output a push vector as the second argument in collisions with other rectangles, polygons or circles.
---@param ... number
---@return Cocollision.Shape
---@overload fun(vertices: number[]): Cocollision.Shape
function cocollision.newPolygonShape(...)
    return cocollision.newShape():setShapeToPolygon(...)
end

--------------------------------------------------
--- ### cocollision.newPointShape(x, y)
--- Creates a new point shape.
---@param x? number
---@param y? number
---@return Cocollision.Shape
function cocollision.newPointShape(x, y)
    return cocollision.newShape():setShapeToPoint(x, y)
end
cocollision.newVertexShape = cocollision.newPointShape

--------------------------------------------------
--- ### cocollision.newEdgeShape(x1, y1, x2, y2)
--- ### cocollision.newEdgeShape(x2, y2)
--- Creates a new line segment shape.  
--- Line segments may output the intersection parameters `t` and `u` when intersecting with other segments, rays, or lines.
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return Cocollision.Shape
---@overload fun(x2: number, y2: number): Cocollision.Shape
function cocollision.newEdgeShape(x1, y1, x2, y2)
    return cocollision.newShape():setShapeToEdge(x1, y1, x2, y2)
end
cocollision.newSegmentShape = cocollision.newEdgeShape

--------------------------------------------------
--- ### cocollision.newRayShape(x1, y1, x2, y2)
--- ### cocollision.newRayShape(x2, y2)
--- Creates a new ray shape.  
--- Rays may output the intersection parameters `t` and `u` when intersecting with other segments, rays, or lines.
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return Cocollision.Shape
---@overload fun(x2: number, y2: number): Cocollision.Shape
function cocollision.newRayShape(x1, y1, x2, y2)
    return cocollision.newShape():setShapeToRay(x1, y1, x2, y2)
end
cocollision.newRaycastShape = cocollision.newRayShape

--------------------------------------------------
--- ### cocollision.newLineShape(x1, y1, x2, y2)
--- ### cocollision.newLineShape(x2, y2)
--- Creates a new infinite line shape.  
--- Lines may output the intersection parameters `t` and `u` when intersecting with other segments, rays, or lines.
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return Cocollision.Shape
---@overload fun(x2: number, y2: number): Cocollision.Shape
function cocollision.newLineShape(x1, y1, x2, y2)
    return cocollision.newShape():setShapeToLine(x1, y1, x2, y2)
end

--------------------------------------------------
--- ### cocollision.newCircleShape(radius)
--- ### cocollision.newCircleShape(x, y, radius)
--- Creates a new circle shape.  
--- Circles output a push vector as the second argument in collisions with other rectangles, polygons, or circles.
---@param x number
---@param y number
---@param radius number
---@return Cocollision.Shape
---@overload fun(radius: number): Cocollision.Shape
function cocollision.newCircleShape(x, y, radius)
    return cocollision.newShape():setShapeToCircle(x, y, radius)
end

--------------------------------------------------
--- ### cocollision.newDonutShape(radius1, radius2)
--- ### cocollision.newDonutShape(x, y, radius1, radius2)
--- Creates a new annulus shape.
---@param x number
---@param y number
---@param radius1 number
---@param radius2 number
---@return Cocollision.Shape
---@overload fun(radius1: number, radius2: number): Cocollision.Shape
function cocollision.newDonutShape(x, y, radius1, radius2)
    return cocollision.newShape():setShapeToDonut(x, y, radius1, radius2)
end
cocollision.newAnnulusShape = cocollision.newDonutShape

--------------------------------------------------
--- ### Shape:clone()
--- Creates a copy of the shape.
function Shape:clone()
    -- new Cocollision.Shape
    local inst = {
        shapeType = self.shapeType,
        x = self.x,
        y = self.y,
        rotation = self.rotation,
        scaleX = self.scaleX,
        scaleY = self.scaleY,
        originX = self.originX,
        originY = self.originY,
        translateX = self.translateX,
        translateY = self.translateY,
        doRectangularRotation = self.doRectangularRotation,
        vertices = {unpack(self.vertices)},
        transformedVertices = {},
        boundingBox = {},
    }
    return setmetatable(inst, ShapeMT)
end

--------------------------------------------------
--- ### Shape:setPosition(x, y)
--- Sets the shape's position.
---@param x number
---@param y number
---@generic T : Cocollision.Shape
---@param self T
---@return T self
function Shape:setPosition(x, y)
    self.x = x
    self.y = y
    return self
end

--------------------------------------------------
--- ### Shape:getPosition()
--- Returns the shape's position.
---@return number x
---@return number y
function Shape:getPosition()
    return self.x, self.y
end

--------------------------------------------------
--- ### Shape:intersects(shape)
--- ### Shape:collidesWith(shape)
--- Checks for a collision between two shapes.  
--- Also may return extra information about the collision as the second return value, depending on the shape types.
---@param shape Cocollision.Shape The shape to check against
---@return boolean intersects
---@return table? collisionInfo
function Shape:intersects(shape)
    return self:intersectsAt(shape)
end
Shape.collidesWith = Shape.intersects

--------------------------------------------------
--- ### Shape:intersectsAt(shape, x1, y1, x2, y2)
--- ### Shape:collisionAt(shape, x1, y1, x2, y2)
--- Like `Shape:intersects()`, but allows for overriding the positions of the shapes.
---@param shape Cocollision.Shape The shape to check against
---@param x1? number The X position of the first shape
---@param y1? number The Y position of the first shape
---@param x2? number The X position of the second shape
---@param y2? number The Y position of the second shape
---@return boolean intersects
---@return table? collisionInfo
function Shape:intersectsAt(shape, x1, y1, x2, y2)
    x1 = x1 or self.x
    y1 = y1 or self.y
    x2 = x2 or shape.x
    y2 = y2 or shape.y

    local selfVertices = self:getTransformedVertices()
    local otherVertices = shape:getTransformedVertices()

    local selfShapeType = self.shapeType
    local otherShapeType = shape.shapeType

    local checkBounds = not ((cocollision.boundlessShapes[selfShapeType] or cocollision.boundlessShapes[otherShapeType]) or (selfShapeType == "rectangle" and otherShapeType == "rectangle"))
    if checkBounds then
        local selfBounds = self:getBoundingBox()
        local otherBounds = shape:getBoundingBox()
        if not cocollision.boundsIntersect(selfBounds, otherBounds, x1, y1, x2, y2) then return false end
    end

    local collisionFunction = cocollision.collisionLookup[selfShapeType][otherShapeType]
    return collisionFunction(selfVertices, otherVertices, x1, y1, x2, y2)
end
Shape.collisionAt = Shape.intersectsAt

--------------------------------------------------
--- ### Shape:intersectsAnyInPartition(partition)
--- Checks for an intersection between the shape and the shapes in the given spatial partition, returning true for the first shape it intersects with (along with any possible collision info, and the intersected shape).  
--- You can optionally supply a filter function which must return true for a given shape to be tested.
---@param partition Cocollision.SpatialPartition
---@param filterFunction? fun(shape: Cocollision.Shape): boolean
---@return boolean intersects
---@return table? collisionInfo
---@return Cocollision.Shape? intersectedShape
function Shape:intersectsAnyInPartition(partition, filterFunction)
    local x1, y1, x2, y2 = partition:shapeToCellRange(self)

    -- not using `partition:getCellRange()` to be able to early return in the middle of the search

    local seenShapes = {}
    for cellX = x1, x2 do
        for cellY = y1, y2 do
            local cellKey = cellX .. ";" .. cellY
            local cell = partition.cells[cellKey]
            if cell then
                for shapeIndex = 1, #cell do
                    local otherShape = cell[shapeIndex]
                    local canTest = (self ~= otherShape) and (not seenShapes[otherShape]) and (not filterFunction or filterFunction(otherShape))
                    seenShapes[otherShape] = true
                    if canTest then
                        local intersects, info = self:intersects(otherShape)
                        if intersects then return true, info, otherShape end -- yay for nesting :-)
                    end
                end
            end
        end
    end

    return false
end

--------------------------------------------------
--- ### Shape:findAllPartitionIntersections(partition)
--- Like `Shape:intersectsAnyInPartition()`, but tests for all intersections and returns them in an array. The `collisionInfos` array may have holes in it.
---@param partition Cocollision.SpatialPartition
---@param filterFunction? fun(shape: Cocollision.Shape): boolean
---@return boolean intersectedAny
---@return (table?)[]? collisionInfos
---@return Cocollision.Shape[]? intersectedShapes
function Shape:findAllPartitionIntersections(partition, filterFunction)
    local otherShapes = partition:getShapeCellRange(self)
    local collisionInfos = {}
    local intersectedShapes = {}
    local nextIntersectionIndex = 1

    for otherShapeIndex = 1, #otherShapes do
        local otherShape = otherShapes[otherShapeIndex]
        local canTest = (self ~= otherShape) and (not filterFunction or filterFunction(otherShape))
        if canTest then
            local intersects, info = self:intersects(otherShape)
            if intersects then
                collisionInfos[nextIntersectionIndex] = info
                intersectedShapes[nextIntersectionIndex] = otherShape
                nextIntersectionIndex = nextIntersectionIndex + 1
            end
        end
    end

    if #intersectedShapes == 0 then return false end
    return true, collisionInfos, intersectedShapes
end

--------------------------------------------------
--- ### Shape:removeShape()
--- Sets the shape type to "none" and removes all vertices.
---@generic T : Cocollision.Shape
---@param self T
---@return T self
function Shape:removeShape()
    self.shapeType = "none"
    self.vertices = {}
    self--[[@as Cocollision.Shape]]:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:setShapeToRectangle(x, y, width, height)
--- ### Shape:setShapeToRectangle(width, height)
--- Sets the shape to be an axis aligned rectangle.  
--- Rectangles output a push vector as the second argument in collisions with other rectangles, polygons, or circles.
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
    self.vertices = {
        x, y,
        x + width, y,
        x + width, y + height,
        x, y + height,
    }

    self:refreshTransform()
    return self
end
Shape.setShapeToAABB = Shape.setShapeToRectangle

--------------------------------------------------
--- ### Shape:setShapeToPolygon(...)
--- ### Shape:setShapeToPolygon(vertices)
--- Sets the shape to be a convex polygon. The vertices may be supplied as alternating X and Y coordinates in either a single flat array or a vararg. The polygon shape type also supports any amount of vertices, and can be basically a point or a segment.  
--- Polygons output a push vector as the second argument in collisions with other rectangles, polygons, or circles.
---@param ... number
---@return Cocollision.Shape self
---@overload fun(self: Cocollision.Shape, vertices: number[]): Cocollision.Shape
function Shape:setShapeToPolygon(...)
    local vertices

    if select("#", ...) == 0 then
        vertices = {}
    elseif type(...) == "table" then
        ---@diagnostic disable-next-line: param-type-mismatch
        vertices = {unpack((...))}
    else
        vertices = {...}
    end

    self.shapeType = "polygon"
    self.vertices = vertices

    self:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:setShapeToPoint(x, y)
--- Sets the shape to be a single point.
---@param x? number
---@param y? number
---@return Cocollision.Shape self
function Shape:setShapeToPoint(x, y)
    self.shapeType = "point"
    self.vertices = {x or 0, y or 0}
    self:refreshTransform()
    return self
end
Shape.setShapeToVertex = Shape.setShapeToPoint

--------------------------------------------------
--- ### Shape:setShapeToEdge(x1, y1, x2, y2)
--- ### Shape:setShapeToEdge(x2, y2)
--- Sets the shape to be a line segment.  
--- Line segments may output the intersection parameters `t` and `u` when intersecting with other segments, rays, or lines.
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return Cocollision.Shape self
---@overload fun(self: Cocollision.Shape, x2: number, y2: number): Cocollision.Shape
function Shape:setShapeToEdge(x1, y1, x2, y2)
    if not (x2 and y2) then
        x2 = x1
        y2 = y1
        x1 = 0
        y1 = 0
    end

    self.shapeType = "edge"
    self.vertices = {x1, y1, x2, y2}

    self:refreshTransform()
    return self
end
Shape.setShapeToSegment = Shape.setShapeToEdge

--------------------------------------------------
--- ### Shape:setShapeToRay(x1, y1, x2, y2)
--- ### Shape:setShapeToRay(x2, y2)
--- Sets the shape to be a ray.  
--- Rays may output the intersection parameters `t` and `u` when intersecting with other segments, rays, or lines.
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return Cocollision.Shape self
---@overload fun(self: Cocollision.Shape, x2: number, y2: number): Cocollision.Shape
function Shape:setShapeToRay(x1, y1, x2, y2)
    self:setShapeToEdge(x1, y1, x2, y2)
    self.shapeType = "ray"
    return self
end
Shape.setShapeToRaycast = Shape.setShapeToRay

--------------------------------------------------
--- ### Shape:setShapeToLine(x1, y1, x2, y2)
--- ### Shape:setShapeToLine(x2, y2)
--- Sets the shape to be an infinite line.  
--- Lines may output the intersection parameters `t` and `u` when intersecting with other segments, rays, or lines.
---@param x1 number
---@param y1 number
---@param x2 number
---@param y2 number
---@return Cocollision.Shape self
---@overload fun(self: Cocollision.Shape, x2: number, y2: number): Cocollision.Shape
function Shape:setShapeToLine(x1, y1, x2, y2)
    self:setShapeToEdge(x1, y1, x2, y2)
    self.shapeType = "line"
    return self
end

--------------------------------------------------
--- ### Shape:setShapeToCircle(radius)
--- ### Shape:setShapeToCircle(x, y, radius)
--- Sets the shape to be a circle.  
--- Circles output a push vector as the second argument in collisions with other rectangles, polygons, or circles.
---@param x number
---@param y number
---@param radius number
---@return Cocollision.Shape self
---@overload fun(radius: number): Cocollision.Shape
function Shape:setShapeToCircle(x, y, radius)
    x = x or 0
    y = y or 0
    if not radius then
        radius = x
        x = 0
        y = 0
    end

    self.shapeType = "circle"
    self.vertices = {
        x, y,
        x + radius, y
    }

    self:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:setShapeToDonut(radius1, radius2)
--- ### Shape:setShapeToDonut(x, y, radius1, radius2)
--- Sets the shape to be an annulus.
---@param x number
---@param y number
---@param radius1 number
---@param radius2 number
---@return Cocollision.Shape self
---@overload fun(radius1: number, radius2: number): Cocollision.Shape
function Shape:setShapeToDonut(x, y, radius1, radius2)
    if not (radius1 and radius2) then
        radius1 = x
        radius2 = y
        x = 0
        y = 0
    end
    if not (radius1 and radius2) then error("Two radius values must be supplied", 2) end
    if (radius2 > radius1) then error("The second radius can't be greater than the first radius", 2) end

    x = x or 0
    y = y or 0

    self.shapeType = "donut"
    self.vertices = {
        x, y,
        x + radius1, y,
        x + radius2, y
    }

    self:refreshTransform()
    return self
end
Shape.setShapeToAnnulus = Shape.setShapeToDonut

--------------------------------------------------
--- ### Shape:polygonify()
--- Converts the shape to a polygon shape (if possible). Circle shapes will convert too, but will lose some of their roundness (based on `cocollision.polygonCircleSegments`).
---@generic T : Cocollision.Shape
---@param self T
---@return T self
function Shape:polygonify()
    local sourceShapeType = self.shapeType
    self.shapeType = "polygon"

    if sourceShapeType == "point" then return self end
    if sourceShapeType == "edge" then return self end
    if sourceShapeType == "rectangle" then return self end
    if sourceShapeType == "polygon" then return self end

    if sourceShapeType == "none" then
        for vertexIndex = 1, #self.vertices do
            self.vertices[vertexIndex] = nil
        end
        return self
    end

    if sourceShapeType == "circle" then
        local segments = cocollision.polygonCircleSegments
        local vertices = self.vertices
        local x, y = vertices[1], vertices[2]
        local radius = vertices[3] - vertices[1]

        for vertexIndex = 1, #vertices do
            vertices[vertexIndex] = nil
        end

        for vertexIndex = 1, segments do
            local angle = (vertexIndex / segments) * math.pi * 2
            local vertexX = x + math.cos(angle) * radius
            local vertexY = y + math.sin(angle) * radius
            vertices[#vertices + 1] = vertexX
            vertices[#vertices + 1] = vertexY
        end

        return self
    end

    error("Shape type '" .. tostring(sourceShapeType) .. "' can't be turned into a polygon", 2)
end

--------------------------------------------------
--- ### Shape:getVertexCount()
--- Returns the amount of vertices in the shape.
---@return number
function Shape:getVertexCount()
    return #self.vertices / 2
end

--------------------------------------------------
--- ### Shape:getVertex(n)
--- Returns the nth vertex of the shape.
---@param n integer
---@return number x
---@return number y
function Shape:getVertex(n)
    local vertices = self.vertices
    return vertices[n * 2 - 1], vertices[n * 2]
end

--------------------------------------------------
--- ### Shape:setVertex(n, x, y)
--- Sets the nth vertex of the shape to a new position.
---@param n integer
---@param x number
---@param y number
---@generic T : Cocollision.Shape
---@param self T
---@return T self
function Shape:setVertex(n, x, y)
    local vertices = self--[[@as Cocollision.Shape]].vertices
    vertices[n * 2 - 1] = x
    vertices[n * 2] = y
    self--[[@as Cocollision.Shape]]:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:removeVertex(n)
--- Removes the nth vertex of the shape.
---@param n integer
---@generic T : Cocollision.Shape
---@param self T
---@return T self
function Shape:removeVertex(n)
    local vertices = self--[[@as Cocollision.Shape]].vertices
    table.remove(vertices, n * 2 - 1)
    table.remove(vertices, n * 2 - 1)
    self--[[@as Cocollision.Shape]]:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:addVertex(x, y)
--- Appends a new vertex to the shape (after the last vertex).
---@param x number
---@param y number
---@generic T : Cocollision.Shape
---@param self T
---@return T self
function Shape:addVertex(x, y)
    local vertices = self--[[@as Cocollision.Shape]].vertices
    vertices[#vertices + 1] = x
    vertices[#vertices + 1] = y
    self--[[@as Cocollision.Shape]]:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:insertVertex(n, x, y)
--- Inserts a new vertex into the shape before the nth vertex.
---@param n integer
---@param x number
---@param y number
---@generic T : Cocollision.Shape
---@param self T
---@return T self
function Shape:insertVertex(n, x, y)
    local vertices = self--[[@as Cocollision.Shape]].vertices
    table.insert(vertices, n * 2 - 1, x)
    table.insert(vertices, n * 2, y)
    self--[[@as Cocollision.Shape]]:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:getVertexWorldPosition(n)
--- Returns the actual position (post transform and movement) of the nth vertex of the shape.
---@param n integer
---@return number x
---@return number y
function Shape:getVertexWorldPosition(n)
    local verties = self:getTransformedVertices()
    return self.x + verties[n * 2 - 1], self.y + verties[n * 2]
end

--------------------------------------------------
--- ### Shape:setOrigin(x, y)
--- Sets the origin of the shape.
---@param x number
---@param y number
---@generic T : Cocollision.Shape
---@param self T
---@return T self
function Shape:setOrigin(x, y)
    self.originX = x
    self.originY = y
    self--[[@as Cocollision.Shape]]:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:setRotation(rotation)
--- Sets the shape's rotation.
---@param r number
---@generic T : Cocollision.Shape
---@param self T
---@return T self
function Shape:setRotation(r)
    self.rotation = r
    self--[[@as Cocollision.Shape]]:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:setScale(sx, sy)
--- Sets the shape's scale. If `sy` is not supplied, sets both axes to the first argument.
---@param sx number
---@param sy? number
---@generic T : Cocollision.Shape
---@param self T
---@return T self
function Shape:setScale(sx, sy)
    self.scaleX = sx
    self.scaleY = sy or sx
    self--[[@as Cocollision.Shape]]:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:setTranslate(x, y)
--- Sets the shape's translate.
---@param x number
---@param y number
---@generic T : Cocollision.Shape
---@param self T
---@return T self
function Shape:setTranslate(x, y)
    self.translateX = x
    self.translateY = y
    self--[[@as Cocollision.Shape]]:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:setRectangularRotation(doRectangularRotation)
--- Sets whether the shape should rotate if its type is a rectangle. This is false by default.
---@param doRectangularRotation boolean
---@generic T : Cocollision.Shape
---@param self T
---@return T self
function Shape:setRectangularRotation(doRectangularRotation)
    self.doRectangularRotation = doRectangularRotation
    self--[[@as Cocollision.Shape]]:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:refreshTransform()
--- Refreshes the transformed vertices to update any changes to the transform that have been made. This is called automatically if the transform is changed using setters.
function Shape:refreshTransform()
    local transformedVertices = self.transformedVertices
    local boundingBox = self.boundingBox
    for vertexIndex = 1, #transformedVertices do
        transformedVertices[vertexIndex] = nil
    end
    for vertexIndex = 1, #boundingBox do
        boundingBox[vertexIndex] = nil
    end
end

--------------------------------------------------
--- ### Shape:getTransformedVertices()
--- Returns the shape's vertices after being transformed. Note that this does not take into account the position of the shape.
---@return number[] transformedVertices
function Shape:getTransformedVertices()
    local transformedVertices = self.transformedVertices

    if #transformedVertices == 0 then
        local vertices = self.vertices
        for vertexIndex = 1, #vertices do
            transformedVertices[vertexIndex] = vertices[vertexIndex]
        end

        local rotation = self.rotation
        if self.shapeType == "rectangle" and not self.doRectangularRotation then rotation = 0 end
        if self.shapeType == "circle" or self.shapeType == "donut" then rotation = 0 end

        cocollision.transformVertices(transformedVertices, self.translateX, self.translateY, rotation, self.scaleX, self.scaleY, self.originX, self.originY)
        if self.shapeType == "rectangle" and rotation ~= 0 then cocollision.generateBoundingBox(transformedVertices, transformedVertices) end

        self.transformedVertices = transformedVertices
    end

    return transformedVertices
end

--------------------------------------------------
--- ### Shape:getBoundingBox()
--- Returns the shape's (post-transform) bounding box. It does not take into account the position of the shape.
function Shape:getBoundingBox()
    local bbox = self.boundingBox
    if #bbox == 0 then
        local transformedVertices = self:getTransformedVertices()

        if self.shapeType == "circle" or self.shapeType == "donut" then
            local radius = transformedVertices[3] - transformedVertices[1]
            bbox[1] = transformedVertices[1] - radius
            bbox[2] = transformedVertices[2] - radius
            bbox[3] = transformedVertices[1] + radius
            bbox[4] = transformedVertices[2] - radius
            bbox[5] = transformedVertices[1] + radius
            bbox[6] = transformedVertices[2] + radius
            bbox[7] = transformedVertices[1] - radius
            bbox[8] = transformedVertices[2] + radius
            return bbox
        end

        cocollision.generateBoundingBox(transformedVertices, bbox)
    end
    return bbox
end

--------------------------------------------------
--- ### Shape:isBoundless()
--- Returns if the shape type the shape is set to is boundless.
---@return boolean
function Shape:isBoundless()
    return cocollision.boundlessShapes[self.shapeType] or false
end

--------------------------------------------------
--- ### Shape:debugDraw()
--- Draws the shape for debugging purposes.  
--- This is the only platform dependent function. If shape drawing isn't implemented, this function does nothing.
---@param fullColor? boolean
---@param drawBounds? boolean
function Shape:debugDraw(fullColor, drawBounds)
    return cocollision.graphics.debugDrawShape(self, fullColor, drawBounds)
end

-- Spatial partitions ------------------------------------------------------------------------------

--------------------------------------------------
--- ### cocollision.newSpatialPartition(cellSize)
--- Creates a new spatial partition with the specified cell size.
---@param cellSize number
---@return Cocollision.SpatialPartition
function cocollision.newSpatialPartition(cellSize)
    -- new Cocollision.SpatialPartition
    local partition = {
        shapes = {},
        cellSize = cellSize,
        cells = {}
    }

    return setmetatable(partition, SpatialPartitionMT)
end

--------------------------------------------------
--- ### SpatialPartition:addShape(shape)
--- Adds a shape to the partition. If this shape ever moves or transforms in any way,
--- make sure to call `SpatialPartition:refreshShape(shape)` to keep it in the correct place in the partition.
--- 
--- Boundless shapes (besides `"none"`) are not supported.
---@param shape Cocollision.Shape
function SpatialPartition:addShape(shape)
    if self.shapes[shape] then error("Shape is already present in the partition", 2) end

    -- `"none"` shape types are boundless, but it seems worth it to make an exception for them.
    -- they'll all just be stored at cell x=y=0 but that shouldn't matter too much.
    local shapeType = shape.shapeType
    if shapeType ~= "none" and cocollision.boundlessShapes[shapeType] then error("Boundless shapes are not supported in spatial partitions", 2) end

    local x1, y1, x2, y2 = self:shapeToCellRange(shape)

    self.shapes[shape] = {x1, y1, x2, y2}
    self:addShapeToCellRange(shape, x1, y1, x2, y2)
end

--------------------------------------------------
--- ### SpatialPartition:removeShape(shape)
--- Removes a shape from the partition (if it's present).
---@param shape Cocollision.Shape
function SpatialPartition:removeShape(shape)
    if not self.shapes[shape] then return end

    local cellRange = self.shapes[shape]
    self:removeShapeFromCellRange(shape, cellRange[1], cellRange[2], cellRange[3], cellRange[4])
    self.shapes[shape] = nil
end

--------------------------------------------------
--- ### SpatialPartition:hasShape(shape)
--- Checks whether or not the given shape is present in the partition.
---@param shape Cocollision.Shape
---@return boolean
function SpatialPartition:hasShape(shape)
    return not not self.shapes[shape]
end

--------------------------------------------------
--- ### SpatialPartition:refreshShape(shape)
--- Refreshes where the shape is in the partition (based on its position and transform).  
--- This needs to be called every time the shape moves or transforms.
---@param shape Cocollision.Shape
function SpatialPartition:refreshShape(shape)
    local cellRange = self.shapes[shape]
    if not cellRange then error("The given shape is not in the partition", 2) end

    local shapeType = shape.shapeType
    if shapeType ~= "none" and cocollision.boundlessShapes[shapeType] then error("Boundless shapes are not supported in spatial partitions", 2) end

    local x1, y1, x2, y2 = self:shapeToCellRange(shape)

    if x1 == cellRange[1] and y1 == cellRange[2] and x2 == cellRange[3] and y2 == cellRange[4] then return end

    -- Going with the easiest option - remove all and then re-add to all.  
    -- Not sure how worth it it'd be to calculate the intersection and only remove and add to the cells that changed,
    -- but generally for large enough cell sizes this shouldn't be an issue.
    self:removeShapeFromCellRange(shape, cellRange[1], cellRange[2], cellRange[3], cellRange[4])
    self:addShapeToCellRange(shape, x1, y1, x2, y2)
    cellRange[1] = x1
    cellRange[2] = y1
    cellRange[3] = x2
    cellRange[4] = y2
end

--------------------------------------------------
--- ### SpatialPartition:boundsToCellRange(boundingBox)
--- Converts a bounding box into a range of cells it occupies in the partition.
---@param boundsX1 number
---@param boundsY1 number
---@param boundsX2 number
---@param boundsY2 number
---@return integer x1
---@return integer y1
---@return integer x2
---@return integer y2
function SpatialPartition:boundsToCellRange(boundsX1, boundsY1, boundsX2, boundsY2)
    local cellSize = self.cellSize
    local cellsX1 = math.floor(boundsX1 / cellSize)
    local cellsY1 = math.floor(boundsY1 / cellSize)
    local cellsX2 = math.floor(boundsX2 / cellSize)
    local cellsY2 = math.floor(boundsY2 / cellSize)

    return cellsX1, cellsY1, cellsX2, cellsY2
end

--------------------------------------------------
--- ### SpatialPartition:shapeToCellRange(shape)
--- Like `SpatialPartition:boundsToCellRange()`, but takes in a shape instead of bounds.
---@param shape Cocollision.Shape
---@return integer x1
---@return integer y1
---@return integer x2
---@return integer y2
function SpatialPartition:shapeToCellRange(shape)
    local bbox = shape:getBoundingBox()
    local shapeX, shapeY = shape.x, shape.y
    return self:boundsToCellRange(shapeX + bbox[1], shapeY + bbox[2], shapeX + bbox[5], shapeY + bbox[6])
end

--------------------------------------------------
--- ### SpatialPartition:getCell(x, y)
--- Returns the shapes in the cell at the given cell coordinates.
---@param x integer
---@param y integer
---@return Cocollision.Shape[]
function SpatialPartition:getCell(x, y)
    local outShapes = {}

    -- If this turns out to be too slow, it could be worth a refactor to use a pairing function for the cell keys.
    -- For now though, I enjoy the cell keys being readable.
    local cellKey = x .. ";" .. y

    local shapesArray = self.cells[cellKey]
    if shapesArray then
        for shapeIndex = 1, #shapesArray do
            outShapes[#outShapes+1] = shapesArray[shapeIndex]
        end
    end
    return outShapes
end

--------------------------------------------------
--- ### SpatialPartition:getCellRange(x1, y1, x2, y2)
--- Returns the shapes in the given range of cells (without repeats).
---@param x1 integer
---@param y1 integer
---@param x2 integer
---@param y2 integer
---@return Cocollision.Shape[]
function SpatialPartition:getCellRange(x1, y1, x2, y2)
    local outShapes = {}
    local seenShapes = {}
    for cellX = x1, x2 do
        for cellY = y1, y2 do
            local cellKey = cellX .. ";" .. cellY
            local shapesArray = self.cells[cellKey]

            if shapesArray then
                for shapeIndex = 1, #shapesArray do
                    local shape = shapesArray[shapeIndex]
                    if not seenShapes[shape] then
                        outShapes[#outShapes+1] = shape
                        seenShapes[shape] = true
                    end
                end
            end
        end
    end
    return outShapes
end

--------------------------------------------------
--- ### SpatialPartition:getShapesInBounds(boundsX1, boundsY1, boundsX2, boundsY2)
--- Like `SpatialPartition:getCellRange()`, but takes in a bounding box instead of cell coordinates.
---@param boundsX1 number
---@param boundsY1 number
---@param boundsX2 number
---@param boundsY2 number
---@return Cocollision.Shape[]
function SpatialPartition:getShapesInBounds(boundsX1, boundsY1, boundsX2, boundsY2)
    local x1, y1, x2, y2 = self:boundsToCellRange(boundsX1, boundsY1, boundsX2, boundsY2)
    return self:getCellRange(x1, y1, x2, y2)
end

--------------------------------------------------
--- ### SpatialPartition:getShapeCellRange(shape)
--- Like `SpatialPartition:getShapesInBounds()`, but takes in a shape instead of a bounding box.
---@param shape Cocollision.Shape
---@return Cocollision.Shape[]
function SpatialPartition:getShapeCellRange(shape)
    local bbox = shape:getBoundingBox()
    local shapeX, shapeY = shape.x, shape.y
    return self:getShapesInBounds(shapeX + bbox[1], shapeY + bbox[2], shapeX + bbox[5], shapeY + bbox[6])
end

--------------------------------------------------
--- ### SpatialPartition:addShapeToCellRange(shape, x1, y1, x2, y2)
--- Adds a shape to the specified range of cells. For most purposes, it is better to simply call
--- `SpatialPartition:addShape()`, which will call this method automatically, and will allow you to refresh the shape easily later.
--- 
--- If you use this function to add a shape to the partition, the shape will NOT be considered present in the partition.
---@param shape Cocollision.Shape
---@param x1 integer
---@param y1 integer
---@param x2 integer
---@param y2 integer
function SpatialPartition:addShapeToCellRange(shape, x1, y1, x2, y2)
    for cellX = x1, x2 do
        for cellY = y1, y2 do
            local cellKey = cellX .. ";" .. cellY

            local shapesArray = self.cells[cellKey] or {}
            shapesArray[#shapesArray+1] = shape
            self.cells[cellKey] = shapesArray
        end
    end
end

--------------------------------------------------
--- ### SpatialPartition:removeShapeFromCellRange(shape)
--- Removes a shape from the specified range of cells (if it finds it there).
--- If you're trying to remove a shape which was previously added using `SpatialPartition:addShape()`,
--- you should instead remove it using `SpatialPartition:removeShape()`.
---@param shape Cocollision.Shape
---@param x1 integer
---@param y1 integer
---@param x2 integer
---@param y2 integer
function SpatialPartition:removeShapeFromCellRange(shape, x1, y1, x2, y2)
    for cellX = x1, x2 do
        for cellY = y1, y2 do
            local cellKey = cellX .. ";" .. cellY

            local shapesArray = self.cells[cellKey]
            if shapesArray then
                for shapeIndex = 1, #shapesArray do
                    if shapesArray[shapeIndex] == shape then -- yay for nesting :-)
                        shapesArray[shapeIndex], shapesArray[#shapesArray] = shapesArray[#shapesArray], shapesArray[shapeIndex]
                        shapesArray[#shapesArray] = nil
                        break
                    end
                end
                if #shapesArray == 0 then
                    self.cells[cellKey] = nil
                end
            end
        end
    end
end

-- Collision functions -----------------------------------------------------------------------------

-- :-)
local function returnFalse()
    return false
end

--- Checks if two rectangles intersect. Note that the vertices of each rectangle are in absolute positions, not in the `x, y, width, height` format.
---@param rectangle1 number[] The vertices of the first rectangle
---@param rectangle2 number[] The vertices of the second rectangle
---@param x1? number X offset for the first rectangle
---@param y1? number Y offset for the first rectangle
---@param x2? number X offset for the second rectangle
---@param y2? number Y offset for the second rectangle
---@return boolean intersected
---@return [number, number]? pushVector
function cocollision.rectanglesIntersect(rectangle1, rectangle2, x1, y1, x2, y2)
    -- Allow for: `x1, y1, x2, y2, x3, y3, x4, y4`
    local ax1, ay1, ax2, ay2 = rectangle1[1], rectangle1[2], rectangle1[5], rectangle1[6]
    local bx1, by1, bx2, by2 = rectangle2[1], rectangle2[2], rectangle2[5], rectangle2[6]

    -- Allow for: `x1, y1, x2, y2`
    ax2 = ax2 or rectangle1[3]
    ay2 = ay2 or rectangle1[4]
    bx2 = bx2 or rectangle2[3]
    by2 = by2 or rectangle2[4]

    -- Offset
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0
    ax1 = ax1 + x1
    ay1 = ay1 + y1
    ax2 = ax2 + x1
    ay2 = ay2 + y1
    bx1 = bx1 + x2
    by1 = by1 + y2
    bx2 = bx2 + x2
    by2 = by2 + y2

    local leftPush  = bx1 - ax2
    local rightPush = bx2 - ax1
    local upPush    = by1 - ay2
    local downPush  = by2 - ay1

    if leftPush > 0 then return false end
    if rightPush < 0 then return false end
    if upPush > 0 then return false end
    if downPush < 0 then return false end

    if not cocollision.doPushVectorCalculation then return true end

    local pushX = -leftPush < rightPush and leftPush or rightPush
    local pushY = -upPush < downPush and upPush or downPush
    if math.abs(pushX) < math.abs(pushY) then
        pushX = pushX + (pushX > 0 and cocollision.pushVectorIncrease or -cocollision.pushVectorIncrease)
        pushY = 0
    else
        pushX = 0
        pushY = pushY + (pushY > 0 and cocollision.pushVectorIncrease or -cocollision.pushVectorIncrease)
    end

    return true, {pushX, pushY}
end
local rectanglesIntersect = cocollision.rectanglesIntersect

-- http://programmerart.weebly.com/separating-axis-theorem.html
-- https://hackmd.io/@US4ofdv7Sq2GRdxti381_A/ryFmIZrsl?type=view

--- Checks if two (convex) polygons intersect.
---@param polygon1 number[] The vertices of the first polygon
---@param polygon2 number[] The vertices of the second polygon
---@param x1? number X offset for the first polygon
---@param y1? number Y offset for the first polygon
---@param x2? number X offset for the second polygon
---@param y2? number Y offset for the second polygon
---@return boolean intersected
---@return [number, number]? pushVector
function cocollision.polygonsIntersect(polygon1, polygon2, x1, y1, x2, y2)
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0

    local pushVectorX, pushVectorY
    local pushVectorMinDistanceSquared = math.huge

    -- Center calculated for determining push vector's direction (if needed)
    local polygon1CenterX, polygon1CenterY = 0, 0
    local polygon2CenterX, polygon2CenterY = 0, 0

    if #polygon1 == 0 or #polygon2 == 0 then return false end

    -- Do all the following for both polygons (or more precisely, for each possible separating axis)
    for loopIndex = 1, 2 do
        if loopIndex == 2 then
            polygon1, polygon2 = polygon2, polygon1
            polygon1CenterX, polygon2CenterX = polygon2CenterX, polygon1CenterX
            polygon1CenterY, polygon2CenterY = polygon2CenterY, polygon1CenterY
            x1, y1, x2, y2 = x2, y2, x1, y1
        end

        for vertexIndex = 1, #polygon1, 2 do
            local edgeX1 = polygon1[vertexIndex]
            local edgeY1 = polygon1[vertexIndex + 1]
            local edgeX2 = polygon1[vertexIndex + 2] or polygon1[1]
            local edgeY2 = polygon1[vertexIndex + 3] or polygon1[2]

            polygon1CenterX = polygon1CenterX + x1 + edgeX1
            polygon1CenterY = polygon1CenterY + y1 + edgeY1

            local edgeX = edgeX2 - edgeX1
            local edgeY = edgeY2 - edgeY1

            local orthogonalX = -edgeY
            local orthogonalY = edgeX

            -- Bounds of the projections onto the orthogonal vector
            local min1, max1 = math.huge, -math.huge
            local min2, max2 = math.huge, -math.huge

            for projectedVertexIndex1 = 1, #polygon1, 2 do
                local x = polygon1[projectedVertexIndex1] + x1
                local y = polygon1[projectedVertexIndex1 + 1] + y1

                local projection1 = x * orthogonalX + y * orthogonalY -- dot
                min1 = math.min(min1, projection1)
                max1 = math.max(max1, projection1)
            end
            for projectedVertexIndex2 = 1, #polygon2, 2 do
                local x = polygon2[projectedVertexIndex2] + x2
                local y = polygon2[projectedVertexIndex2 + 1] + y2

                local projection2 = x * orthogonalX + y * orthogonalY -- dot
                min2 = math.min(min2, projection2)
                max2 = math.max(max2, projection2)
            end

            if max1 < min2 or min1 > max2 then
                -- Separating axis found
                return false
            end

            -- Collison not ruled out yet, calculate push vector for this edge

            if cocollision.doPushVectorCalculation then
                local pushDistance = math.min(max2 - min1, max1 - min2)

                local distanceNormaliser = pushDistance / (orthogonalX * orthogonalX + orthogonalY * orthogonalY)
                local testPushVectorX = orthogonalX * distanceNormaliser
                local testPushVectorY = orthogonalY * distanceNormaliser

                -- Technically the wrong way to do the pushVectorIncrease (adds it to both axes) but no one's gonna know
                testPushVectorX = testPushVectorX + (testPushVectorX > 0 and cocollision.pushVectorIncrease or testPushVectorX < 0 and -cocollision.pushVectorIncrease or 0)
                testPushVectorY = testPushVectorY + (testPushVectorY > 0 and cocollision.pushVectorIncrease or testPushVectorY < 0 and -cocollision.pushVectorIncrease or 0)

                pushDistance = testPushVectorX * testPushVectorX + testPushVectorY * testPushVectorY

                if pushDistance < pushVectorMinDistanceSquared then
                    pushVectorMinDistanceSquared = pushDistance
                    pushVectorX = testPushVectorX
                    pushVectorY = testPushVectorY
                end
            end
        end
    end

    -- If we made it here, there was a collision
    if not cocollision.doPushVectorCalculation then return true end

    -- Make sure the push vector is pointing in the right direction
    polygon1CenterX = polygon1CenterX / (#polygon1 / 2)
    polygon1CenterY = polygon1CenterY / (#polygon1 / 2)
    polygon2CenterX = polygon2CenterX / (#polygon2 / 2)
    polygon2CenterY = polygon2CenterY / (#polygon2 / 2)
    local centerDifferenceX = polygon1CenterX - polygon2CenterX -- first minus second because they're actually swapped - polygon1Center becomes the center of polygon2. :p
    local centerDifferenceY = polygon1CenterY - polygon2CenterY
    local projection = pushVectorX * centerDifferenceX + pushVectorY * centerDifferenceY
    if projection > 0 then
        pushVectorX = -pushVectorX
        pushVectorY = -pushVectorY
    end

    return true, {pushVectorX, pushVectorY}
end
local polygonsIntersect = cocollision.polygonsIntersect

-- https://www.sevenson.com.au/programming/sat/

---@param polygon number[]
---@param polygonX number
---@param polygonY number
---@param circleX number
---@param circleY number
---@param circleRadius number
---@param _reversePushVector? boolean
---@return boolean intersected
---@return [number, number]? pushVector
function cocollision.polygonIntersectsCircle(polygon, polygonX, polygonY, circleX, circleY, circleRadius, _reversePushVector)
    polygonX = polygonX or 0
    polygonY = polygonY or 0

    -- Closest vertex to the circle
    local closestVertexDistanceSquared = math.huge
    local closestVertexDifferenceX, closestVertexDifferenceY

    local pushVectorX, pushVectorY
    local pushVectorMinDistance = math.huge

    local polygonCenterX, polygonCenterY = 0, 0

    if #polygon == 0 then return false end

    for vertexIndex = 1, #polygon, 2 do
        local differenceX = polygon[vertexIndex] + polygonX - circleX
        local differenceY = polygon[vertexIndex + 1] + polygonY - circleY
        local distanceSquared = differenceX * differenceX + differenceY * differenceY
        if distanceSquared < closestVertexDistanceSquared then
            closestVertexDistanceSquared = distanceSquared
            closestVertexDifferenceX = differenceX
            closestVertexDifferenceY = differenceY
        end

        local edgeX1 = polygon[vertexIndex]
        local edgeY1 = polygon[vertexIndex + 1]
        local edgeX2 = polygon[vertexIndex + 2] or polygon[1]
        local edgeY2 = polygon[vertexIndex + 3] or polygon[2]

        polygonCenterX = polygonCenterX + polygonX + edgeX1
        polygonCenterY = polygonCenterY + polygonY + edgeY1

        local edgeX = edgeX2 - edgeX1
        local edgeY = edgeY2 - edgeY1

        local orthogonalX = -edgeY
        local orthogonalY = edgeX

        -- The orthogonal needs to be normalised here
        local orthogonalLength = math.sqrt(orthogonalX * orthogonalX + orthogonalY * orthogonalY)
        orthogonalX = orthogonalX / orthogonalLength
        orthogonalY = orthogonalY / orthogonalLength

        -- Bounds of the projections onto the orthogonal vector
        local min1, max1 = math.huge, -math.huge
        local min2, max2

        for projectedVertexIndex1 = 1, #polygon, 2 do
            local x = polygon[projectedVertexIndex1] + polygonX
            local y = polygon[projectedVertexIndex1 + 1] + polygonY

            local projection = x * orthogonalX + y * orthogonalY
            min1 = math.min(min1, projection)
            max1 = math.max(max1, projection)
        end

        local projectedPoint = circleX * orthogonalX + circleY * orthogonalY
        min2 = projectedPoint - circleRadius
        max2 = projectedPoint + circleRadius

        if max1 < min2 or min1 > max2 then
            -- Separating axis found
            return false
        end

        local pushDistance = math.min(max2 - min1, max1 - min2)
        if pushDistance < pushVectorMinDistance then
            pushVectorMinDistance = pushDistance
            pushVectorX = orthogonalX * pushDistance
            pushVectorY = orthogonalY * pushDistance
        end
    end

    -- Check the axis for the circle
    local closestVertexDistance = math.sqrt(closestVertexDistanceSquared)
    local orthogonalX = closestVertexDifferenceX / closestVertexDistance
    local orthogonalY = closestVertexDifferenceY / closestVertexDistance

    local min1, max1 = math.huge, -math.huge
    local min2, max2
    for projectedVertexIndex1 = 1, #polygon, 2 do
        local x = polygon[projectedVertexIndex1] + polygonX
        local y = polygon[projectedVertexIndex1 + 1] + polygonY

        local projection = x * orthogonalX + y * orthogonalY
        min1 = math.min(min1, projection)
        max1 = math.max(max1, projection)
    end
    local projectedPoint = circleX * orthogonalX + circleY * orthogonalY
    min2 = projectedPoint - circleRadius
    max2 = projectedPoint + circleRadius

    if max1 < min2 or min1 > max2 then
        return false
    end

    local pushDistance = math.min(max2 - min1, max1 - min2)
    if pushDistance < pushVectorMinDistance then
        pushVectorMinDistance = pushDistance
        pushVectorX = orthogonalX * pushDistance
        pushVectorY = orthogonalY * pushDistance
    end

    if not cocollision.doPushVectorCalculation then return true end

    -- Make sure the push vector is pointing in the right direction
    polygonCenterX = polygonCenterX / (#polygon / 2)
    polygonCenterY = polygonCenterY / (#polygon / 2)
    local centerDifferenceX = circleX - polygonCenterX
    local centerDifferenceY = circleY - polygonCenterY
    local projection = pushVectorX * centerDifferenceX + pushVectorY * centerDifferenceY
    if projection > 0 then
        pushVectorX = -pushVectorX
        pushVectorY = -pushVectorY
    end
    if _reversePushVector then
        pushVectorX = -pushVectorX
        pushVectorY = -pushVectorY
    end

    return true, {pushVectorX, pushVectorY}
end
local polygonIntersectsCircle = cocollision.polygonIntersectsCircle

local function polygonIntersectsCircleVert(polygon, circle, x1, y1, x2, y2, _reversePushVector)
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0
    local radius = circle[3] - circle[1]
    return polygonIntersectsCircle(polygon, x1, y1, circle[1] + x2, circle[2] + y2, radius, _reversePushVector)
end
local function circleIntersectsPolygonVert(circle, polygon, x1, y1, x2, y2) return polygonIntersectsCircleVert(polygon, circle, x2, y2, x1, y1, true) end

---@param circle1X number
---@param circle1Y number
---@param circle1Radius number
---@param circle2X number
---@param circle2Y number
---@param circle2Radius number
---@return boolean intersected
---@return [number, number]? pushVector
function cocollision.circlesIntersect(circle1X, circle1Y, circle1Radius, circle2X, circle2Y, circle2Radius)
    local differenceX = circle1X - circle2X
    local differenceY = circle1Y - circle2Y
    local distance = math.sqrt(differenceX * differenceX + differenceY * differenceY)
    if distance > circle1Radius + circle2Radius then return false end
    if not cocollision.doPushVectorCalculation then return true end

    local pushDistance = circle1Radius + circle2Radius - distance
    local pushVectorX = differenceX / distance * pushDistance
    local pushVectorY = differenceY / distance * pushDistance
    return true, {pushVectorX, pushVectorY}
end
local circlesIntersect = cocollision.circlesIntersect

local function circlesIntersectVert(circle1, circle2, x1, y1, x2, y2)
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0
    local radius1 = circle1[3] - circle1[1]
    local radius2 = circle2[3] - circle2[1]
    return circlesIntersect(circle1[1] + x1, circle1[2] + y1, radius1, circle2[1] + x2, circle2[2] + y2, radius2)
end

--- Checks if a point is on top of another point.
---@param p1x number The X position of the first point
---@param p1y number The Y position of the first point
---@param p2x number The X position of the second point
---@param p2y number The Y position of the second point
---@return boolean intersected
function cocollision.pointIsOnPoint(p1x, p1y, p2x, p2y)
    return p1x == p2x and p1y == p2y
end
local pointIsOnPoint = cocollision.pointIsOnPoint

local function pointIsOnPointVert(point1, point2, x1, y1, x2, y2)
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0
    return pointIsOnPoint(point1[1] + x1, point1[2] + y1, point2[1] + x2, point2[2] + y2)
end

---@param pointX number
---@param pointY number
---@param circleX number
---@param circleY number
---@param circleRadius number
---@return boolean intersects
function cocollision.pointInCircle(pointX, pointY, circleX, circleY, circleRadius)
    local differenceX = pointX - circleX
    local differenceY = pointY - circleY
    local distance = math.sqrt(differenceX * differenceX + differenceY * differenceY)
    return distance <= circleRadius
end
local pointInCircle = cocollision.pointInCircle

local function pointInCircleVert(point, circle, x1, y1, x2, y2)
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0
    local radius = circle[3] - circle[1]
    return pointInCircle(point[1] + x1, point[2] + y1, circle[1] + x2, circle[2] + y2, radius)
end
local function circleUnderPointVert(circle, point, x1, y1, x2, y2) return pointInCircleVert(point, circle, x2, y2, x1, y1) end

--- Checks if a circle is on a line. The line is an infinite line by default, but can be configured to be a ray or a segment using the `lineEndpointCount` parameter - see `cocollision.linesIntersect` for details.
---@param circleX number The X position of the point
---@param circleY number The Y position of the point
---@param circleRadius number The radius of the circle
---@param lineX1 number The X position of the first vertex of the line
---@param lineY1 number The Y position of the first vertex of the line
---@param lineX2 number The X position of the second vertex of the line
---@param lineY2 number The Y position of the second vertex of the line
---@param lineEndpointCount? number How many endpoints the line has
---@return boolean intersects
function cocollision.circleOnLine(circleX, circleY, circleRadius, lineX1, lineY1, lineX2, lineY2, lineEndpointCount)
    lineEndpointCount = lineEndpointCount or 0

    local pointX = circleX
    local pointY = circleY
    local radius = circleRadius
    local lineX = lineX2 - lineX1
    local lineY = lineY2 - lineY1

    -- The point's position relative to the line's first vertex
    local lineToPointX = pointX - lineX1
    local lineToPointY = pointY - lineY1

    local slope = lineY / lineX

    if slope ~= slope then
        -- slope is NaN => line distance is 0 => line is actually just a point
        -- which is an invalid line, so for consistency with the line-on-line function:
        return false
    end

    local distanceFromLine

    if slope == math.huge or slope == -math.huge then
        -- slope is infinite => lineX is 0 => line is vertical
        distanceFromLine = math.abs(lineToPointX)
    else
        local orthogonalX = -lineY
        local orthogonalY = lineX
        local orthogonalLength = math.sqrt(orthogonalX * orthogonalX + orthogonalY * orthogonalY)

        -- point's position relative to the line, projected onto line's orthogonal vector
        -- leaves us with how far along the orthogonal vector the point is, which is the distance from the line
        distanceFromLine = math.abs(lineToPointX * orthogonalX + lineToPointY * orthogonalY) / orthogonalLength
    end

    if distanceFromLine > radius then return false end
    if lineEndpointCount == 0 then return true end -- lines solved

    local lineLength = math.sqrt(lineX * lineX + lineY * lineY)

    -- how far away from the edge of the line the circle can go
    -- (distance from the edge of the line to the point on the circle it crosses)
    --
    --      _ _ _ _ _ _
    --    /             \
    --  /                 \
    -- |  radius           |
    -- |     _ - X         |
    -- | _ ⁻     |   <- distanceFromLine
    -- |/________|         |
    --  \     ^ segmentMargin
    --    \ _ _ _ _ _ _ /
    --
    local segmentMargin = math.sqrt(radius * radius - distanceFromLine * distanceFromLine)

    -- project to get the value of how far along the line the circle is
    local unnormalisedParameter = (lineX * lineToPointX + lineY * lineToPointY) / lineLength

    if unnormalisedParameter < -segmentMargin then return false end -- circle is behind the line
    if lineEndpointCount == 1 then return true end -- rays solved

    if unnormalisedParameter > lineLength + segmentMargin then return false end -- point is in front of the line

    return true -- segments solved
end
local circleOnLine = cocollision.circleOnLine

local function circleOnLineVert(circle, line, x1, y1, x2, y2, lineEndpointCount)
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0
    local radius = circle[3] - circle[1]
    return circleOnLine(circle[1] + x1, circle[2] + y1, radius, line[1] + x2, line[2] + y2, line[3] + x2, line[4] + y2, lineEndpointCount)
end

local function circleOnRayVert(circle, ray, x1, y1, x2, y2) return circleOnLineVert(circle, ray, x1, y1, x2, y2, 1) end
local function circleOnSegmentVert(circle, segment, x1, y1, x2, y2) return circleOnLineVert(circle, segment, x1, y1, x2, y2, 2) end
local function lineIsUnderCircleVert(line, circle, x1, y1, x2, y2) return circleOnLineVert(circle, line, x2, y2, x1, y1) end
local function rayIsUnderCircleVert(ray, circle, x1, y1, x2, y2) return circleOnLineVert(circle, ray, x2, y2, x1, y1, 1) end
local function segmentIsUnderCircleVert(segment, circle, x1, y1, x2, y2) return circleOnLineVert(circle, segment, x2, y2, x1, y1, 2) end

--- Checks if a point is on a line. The line is an infinite line by default, but can be configured to be a ray or a segment using the `lineEndpointCount` parameter - see `cocollision.linesIntersect` for details.
---@param pointX number The X position of the point
---@param pointY number The Y position of the point
---@param lineX1 number The X position of the first vertex of the line
---@param lineY1 number The Y position of the first vertex of the line
---@param lineX2 number The X position of the second vertex of the line
---@param lineY2 number The Y position of the second vertex of the line
---@param lineEndpointCount? number How many endpoints the line has
---@return boolean intersects
function cocollision.pointOnLine(pointX, pointY, lineX1, lineY1, lineX2, lineY2, lineEndpointCount)
    return circleOnLine(pointX, pointY, 1e-10, lineX1, lineY1, lineX2, lineY2, lineEndpointCount) -- the 1e-10 is necessary because of float imprecision
end
local pointOnLine = cocollision.pointOnLine

local function pointOnLineVert(point, line, x1, y1, x2, y2, lineEndpointCount)
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0
    return pointOnLine(point[1] + x1, point[2] + y1, line[1] + x2, line[2] + y2, line[3] + x2, line[4] + y2, lineEndpointCount)
end

local function pointOnRayVert(point, ray, x1, y1, x2, y2) return pointOnLineVert(point, ray, x1, y1, x2, y2, 1) end
local function pointOnSegmentVert(point, segment, x1, y1, x2, y2) return pointOnLineVert(point, segment, x1, y1, x2, y2, 2) end
local function lineIsUnderPointVert(line, point, x1, y1, x2, y2) return pointOnLineVert(point, line, x2, y2, x1, y1) end
local function rayIsUnderPointVert(ray, point, x1, y1, x2, y2) return pointOnLineVert(point, ray, x2, y2, x1, y1, 1) end
local function segmentIsUnderPointVert(segment, point, x1, y1, x2, y2) return pointOnLineVert(point, segment, x2, y2, x1, y1, 2) end

-- https://stackoverflow.com/a/565282
-- https://paulbourke.net/geometry/pointlineplane/javascript.txt
-- https://www.shadertoy.com/view/sl3XRn

--- Checks if two lines intersect. By default checks for infinite lines, but each line can be changed to be either a ray or a segment using the endpoint count parameter:  
--- * `lineEndpointCount = 0` - Infinite line
--- * `lineEndpointCount = 1` - Ray
--- * `lineEndpointCount = 2` - Segment
--- 
--- The function may return the intersection parameters `t` and `u` as the second return, which determine how far along the line the intersection happened, for each line respectively.
---@param ax1 number The X position of the first line's first point
---@param ay1 number The Y position of the first line's first point
---@param ax2 number The X position of the first line's second point
---@param ay2 number The Y position of the first line's second point
---@param bx1 number The X position of the second line's first point
---@param by1 number The Y position of the second line's first point
---@param bx2 number The X position of the second line's second point
---@param by2 number The Y position of the second line's second point
---@param line1EndpointCount? integer How many endpoints the first line has
---@param line2EndpointCount? integer How many endpoints the second line has
---@return boolean intersected
---@return {t: number, u: number}? lineIntersectionParameters
function cocollision.linesIntersect(ax1, ay1, ax2, ay2, bx1, by1, bx2, by2, line1EndpointCount, line2EndpointCount)
    line1EndpointCount = line1EndpointCount or 0
    line2EndpointCount = line2EndpointCount or 0

    -- I have to shorten variable names here because otherwise it's genuinely illegible
    -- lines `a`, `b` (start points), going in directions `aDir`, `bDir`
    -- `t` and `u` are the parameters determining the intersection point for each line respectively

    local aX = ax1
    local aY = ay1
    local aDirX = ax2 - ax1
    local aDirY = ay2 - ay1

    local bX = bx1
    local bY = by1
    local bDirX = bx2 - bx1
    local bDirY = by2 - by1

    local denominator = aDirX * bDirY - aDirY * bDirX -- 2D cross product

    local t = ((bX - aX) * bDirY - (bY - aY) * bDirX) / denominator
    local u = ((bX - aX) * aDirY - (bY - aY) * aDirX) / denominator

    if denominator ~= 0 then -- lines are non-collinear
        local tMin = line1EndpointCount == 0 and -math.huge or 0
        local tMax = line1EndpointCount <= 1 and math.huge or 1
        local uMin = line2EndpointCount == 0 and -math.huge or 0
        local uMax = line2EndpointCount <= 1 and math.huge or 1

        if t >= tMin and t <= tMax and u >= uMin and u <= uMax then
            return true, {t = t, u = u}
        end
    end

    -- lines are collinear
    -- which is a bit trickier to solve:

    if t == t and u == u then
        -- t and u are not NaN
        -- so ((bX - aX) * bDirY - (bY - aY) * bDirX) = 0
        -- so lines are collinear and not intersecting
        return false
    end

    -- if either line is infinite, no point for checking the segments, they'll always intersect
    if line1EndpointCount == 0 or line2EndpointCount == 0 then return true end

    -- for rays and segments, we still need to check if they're overlapping:

    local baX = bX - aX
    local baY = bY - aY

    local t0 = (baX * aDirX + baY * aDirY) / (aDirX * aDirX + aDirY * aDirY)
    local t1 = t0 + (aDirX * bDirX + aDirY * bDirY) / (aDirX * aDirX + aDirY * aDirY)

    local intervalMin = line2EndpointCount == 1 and -math.huge or 0 -- "if you're a ray, you can be as far behind me as you want"
    local intervalMax = line1EndpointCount == 1 and math.huge or 1 -- "if i'm a ray, you can be as far in front of me as you want"

    if aDirX * bDirX + aDirY * bDirY < 0 then -- lines pointing in opposite directions
        t0, t1 = t1, t0 -- interval needs to be swapped
        intervalMin = 0
        intervalMax = line2EndpointCount == 1 and math.huge or intervalMax -- "if you're a ray, nvm, you can be as far *in front* of me as you want"
    end

    if t0 >= intervalMin and t0 <= intervalMax then return true end
    if t1 >= intervalMin and t1 <= intervalMax then return true end
    return false
end
local linesIntersect = cocollision.linesIntersect

local function linesIntersectVert(line1, line2, x1, y1, x2, y2, line1EndpointCount, line2EndpointCount)
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0
    local ax1 = line1[1] + x1
    local ay1 = line1[2] + y1
    local ax2 = line1[3] + x1
    local ay2 = line1[4] + y1
    local bx1 = line2[1] + x2
    local by1 = line2[2] + y2
    local bx2 = line2[3] + x2
    local by2 = line2[4] + y2
    return linesIntersect(ax1, ay1, ax2, ay2, bx1, by1, bx2, by2, line1EndpointCount, line2EndpointCount)
end

local function segmentsIntersectVert(segment1, segment2, x1, y1, x2, y2) return linesIntersectVert(segment1, segment2, x1, y1, x2, y2, 2, 2) end
local function raysIntersectVert(ray1, ray2, x1, y1, x2, y2) return linesIntersectVert(ray1, ray2, x1, y1, x2, y2, 1, 1) end
local function segmentCrossesRayVert(segment, ray, x1, y1, x2, y2) return linesIntersectVert(segment, ray, x1, y1, x2, y2, 2, 1) end
local function segmentCrossesLineVert(segment, line, x1, y1, x2, y2) return linesIntersectVert(segment, line, x1, y1, x2, y2, 2, 0) end
local function rayCrossesSegmentVert(ray, segment, x1, y1, x2, y2) return linesIntersectVert(ray, segment, x1, y1, x2, y2, 1, 2) end
local function rayCrossesLineVert(ray, line, x1, y1, x2, y2) return linesIntersectVert(ray, line, x1, y1, x2, y2, 1, 0) end
local function lineCrossesSegmentVert(line, segment, x1, y1, x2, y2) return linesIntersectVert(line, segment, x1, y1, x2, y2, 0, 2) end
local function lineCrossesRayVert(line, ray, x1, y1, x2, y2) return linesIntersectVert(line, ray, x1, y1, x2, y2, 0, 1) end

local function pointInDonutVert(point, donut, x1, y1, x2, y2)
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0
    local px, py = point[1] + x1, point[2] + y1
    local donutX, donutY = donut[1] + x2, donut[2] + y2
    local r1 = donut[3] - donut[1]
    local r2 = donut[5] - donut[1]
    return pointInCircle(px, py, donutX, donutY, r1) and not pointInCircle(px, py, donutX, donutY, r2)
end
local function donutUnderPointVert(donut, point, x1, y1, x2, y2) return pointInDonutVert(point, donut, x2, y2, x1, y1) end

local function segmentCrossesDonutVert(segment, donut, x1, y1, x2, y2)
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0
    local segmentX1 = segment[1] + x1
    local segmentY1 = segment[2] + y1
    local segmentX2 = segment[3] + x1
    local segmentY2 = segment[4] + y1
    local donutX = donut[1] + x2
    local donutY = donut[2] + y2
    local r1 = donut[3] - donut[1]
    local r2 = donut[5] - donut[1]
    if pointInCircle(segmentX1, segmentY1, donutX, donutY, r2) and pointInCircle(segmentX2, segmentY2, donutX, donutY, r2) then return false end
    return circleOnLine(donutX, donutY, r1, segmentX1, segmentY1, segmentX2, segmentY2, 2)
end
local function donutOnSegmentVert(donut, segment, x1, y1, x2, y2) return segmentCrossesDonutVert(segment, donut, x2, y2, x1, y1) end

local function polygonIntersectsDonutVert(polygon, donut, x1, y1, x2, y2)
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0
    local donutX = donut[1] + x2
    local donutY = donut[2] + y2
    local r1 = donut[3] - donut[1]
    local r2 = donut[5] - donut[1]

    if #polygon == 0 then return false end

    local isWhollyContained = true
    for vertexIndex = 1, #polygon, 2 do
        local vertexX = polygon[vertexIndex] + x1
        local vertexY = polygon[vertexIndex + 1] + y1
        if not pointInCircle(vertexX, vertexY, donutX, donutY, r2) then
            isWhollyContained = false
            break
        end
    end
    if isWhollyContained then return false end

    return (polygonIntersectsCircle(polygon, x1, y1, donutX, donutY, r1))
end
local function donutIntersectsPolygonVert(donut, polygon, x1, y1, x2, y2)
    return polygonIntersectsDonutVert(polygon, donut, x2, y2, x1, y1)
end

local function circleIntersectsDonutVert(circle, donut, x1, y1, x2, y2)
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0

    local circleX = circle[1] + x1
    local circleY = circle[2] + y1
    local circleRadius = circle[3] - circle[1]
    local donutX = donut[1] + x2
    local donutY = donut[2] + y2
    local r1 = donut[3] - donut[1]
    local r2 = donut[5] - donut[1]

    local differenceX = circleX - donutX
    local differenceY = circleY - donutY
    local distance = math.sqrt(differenceX * differenceX + differenceY * differenceY)

    if distance > r1 + circleRadius then return false end
    if distance <= r2 - circleRadius then return false end
    return true
end
local function donutIntersectsCircleVert(donut, circle, x1, y1, x2, y2) return circleIntersectsDonutVert(circle, donut, x2, y2, x1, y1) end

local function donutsIntersectVert(donut1, donut2, x1, y1, x2, y2)
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0

    local donut1X = donut1[1] + x1
    local donut1Y = donut1[2] + y1
    local donut1Radius1 = donut1[3] - donut1[1]
    local donut1Radius2 = donut1[5] - donut1[1]

    local donut2X = donut2[1] + x2
    local donut2Y = donut2[2] + y2
    local donut2Radius1 = donut2[3] - donut2[1]
    local donut2Radius2 = donut2[5] - donut2[1]

    local differenceX = donut2X - donut1X
    local differenceY = donut2Y - donut1Y
    local distance = math.sqrt(differenceX * differenceX + differenceY * differenceY)

    if distance > donut1Radius1 + donut2Radius1 then return false end
    if distance <= donut1Radius2 - donut2Radius1 then return false end
    if distance <= donut2Radius2 - donut1Radius1 then return false end
    return true
end

---@param pointX number
---@param pointY number
---@param rectangle number[]
---@param rectangleX? number
---@param rectangleY? number
---@return boolean intersected
function cocollision.pointInRectangle(pointX, pointY, rectangle, rectangleX, rectangleY)
    -- Allow for: `x1, y1, x2, y2, x3, y3, x4, y4`
    local rectangleX1, rectangleY1, rectangleX2, rectangleY2 = rectangle[1], rectangle[2], rectangle[5], rectangle[6]

    -- Allow for: `x1, y1, x2, y2`
    rectangleX2 = rectangleX2 or rectangle[3]
    rectangleY2 = rectangleY2 or rectangle[4]

    -- Offset
    rectangleX = rectangleX or 0
    rectangleY = rectangleY or 0
    rectangleX1 = rectangleX1 + rectangleX
    rectangleY1 = rectangleY1 + rectangleY
    rectangleX2 = rectangleX2 + rectangleX
    rectangleY2 = rectangleY2 + rectangleY

    if pointX > rectangleX2 then return false end
    if pointX < rectangleX1 then return false end
    if pointY > rectangleY2 then return false end
    if pointY < rectangleY1 then return false end
    return true
end
local pointInRectangle = cocollision.pointInRectangle

local function pointInRectangleVert(point, rectangle, x1, y1, x2, y2)
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0
    return pointInRectangle(point[1] + x1, point[2] + y1, rectangle, x2, y2)
end
local function rectangleIsUnderPointVert(rectangle, point, x1, y1, x2, y2) return pointInRectangleVert(point, rectangle, x2, y2, x1, y1) end

-- https://en.m.wikipedia.org/wiki/Even%E2%8093odd_rule
-- https://www.jeffreythompson.org/collision-detection/poly-point.php

---@param pointX number
---@param pointY number
---@param polygon number[]
---@param polygonX? number
---@param polygonY? number
---@return boolean intersected
function cocollision.pointInPolygon(pointX, pointY, polygon, polygonX, polygonY)
    polygonX = polygonX or 0
    polygonY = polygonY or 0

    local intersected = false
    for vertexIndex = 1, #polygon, 2 do
        local vertexX1 = polygon[vertexIndex] + polygonX
        local vertexY1 = polygon[vertexIndex + 1] + polygonY
        local vertexX2 = (polygon[vertexIndex + 2] or polygon[1]) + polygonX
        local vertexY2 = (polygon[vertexIndex + 3] or polygon[2]) + polygonY

        if pointX == vertexX1 and pointY == vertexY1 then
            return true -- point is on a corner
        end

        if ((vertexY1 > pointY) ~= (vertexY2 > pointY)) then -- point is between the two vertices height-wise
            -- then do whatever the hell this does
            local slope = (pointX - vertexX1) * (vertexY2 - vertexY1) - (vertexX2 - vertexX1) * (pointY - vertexY1)
            if slope == 0 then return true end -- point is on the edge
            if (slope < 0) ~= (vertexY2 < vertexY1) then
                intersected = not intersected
            end
        end
    end

    return intersected
end
local pointInPolygon = cocollision.pointInPolygon

local function pointInPolygonVert(point, polygon, x1, y1, x2, y2)
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0
    return pointInPolygon(point[1] + x1, point[2] + y1, polygon, x2, y2)
end
local function polygonIsUnderPointVert(polygon, point, x1, y1, x2, y2) return pointInPolygonVert(point, polygon, x2, y2, x1, y1) end

---@param lineX1 number
---@param lineY1 number
---@param lineX2 number
---@param lineY2 number
---@param polygon number[]
---@param polygonX? number
---@param polygonY? number
---@param lineEndpointCount? integer
---@return boolean intersected
function cocollision.lineCrossesPolygon(lineX1, lineY1, lineX2, lineY2, polygon, polygonX, polygonY, lineEndpointCount)
    polygonX = polygonX or 0
    polygonY = polygonY or 0
    lineEndpointCount = lineEndpointCount or 0

    if lineEndpointCount >= 2 then -- segment could be wholly contained by the polygon
        if pointInPolygon(lineX1, lineY1, polygon, polygonX, polygonY) then return true end
        if pointInPolygon(lineX2, lineY2, polygon, polygonX, polygonY) then return true end
    end

    local vertexCount = #polygon / 2
    if vertexCount == 0 then return false end
    if vertexCount == 1 then return pointOnLine(polygon[1] + polygonX, polygon[2] + polygonY, lineX1, lineY1, lineX2, lineY2, lineEndpointCount) end

    for vertexIndex = 1, vertexCount do
        local vertexX1 = polygon[vertexIndex * 2 - 1] + polygonX
        local vertexY1 = polygon[vertexIndex * 2] + polygonY
        local vertexX2 = (polygon[vertexIndex * 2 + 1] or polygon[1]) + polygonX
        local vertexY2 = (polygon[vertexIndex * 2 + 2] or polygon[2]) + polygonY

        if linesIntersect(lineX1, lineY1, lineX2, lineY2, vertexX1, vertexY1, vertexX2, vertexY2, lineEndpointCount, 2) then
            return true
        end
    end

    return false
end
local lineCrossesPolygon = cocollision.lineCrossesPolygon

local function lineCrossesPolygonVert(line, polygon, x1, y1, x2, y2, lineEndpointCount)
    x1 = x1 or 0
    y1 = y1 or 0
    x2 = x2 or 0
    y2 = y2 or 0
    return lineCrossesPolygon(line[1] + x1, line[2] + y1, line[3] + x1, line[4] + y1, polygon, x2, y2, lineEndpointCount)
end

local function segmentCrossesPolygonVert(segment, polygon, x1, y1, x2, y2) return lineCrossesPolygonVert(segment, polygon, x1, y1, x2, y2, 2) end
local function rayCrossesPolygonVert(ray, polygon, x1, y1, x2, y2) return lineCrossesPolygonVert(ray, polygon, x1, y1, x2, y2, 1) end
local function polygonGetsHitByLineVert(polygon, line, x1, y1, x2, y2, lineEndpointCount) return lineCrossesPolygonVert(line, polygon, x2, y2, x1, y1, lineEndpointCount) end
local function polygonGetsHitBySegmentVert(polygon, segment, x1, y1, x2, y2) return lineCrossesPolygonVert(segment, polygon, x2, y2, x1, y1, 2) end
local function polygonGetsHitByRayVert(polygon, ray, x1, y1, x2, y2) return lineCrossesPolygonVert(ray, polygon, x2, y2, x1, y1, 1) end

--------------------------------------------------

-- Contains a pair of every combination of two shapes, pointing to the appropriate collision functions
---@type table<Cocollision.ShapeType, table<Cocollision.ShapeType, fun(shape1: number[], shape2: number[], x1?: number, y1?: number, x2?: number, y2?: number): boolean, table?>>
cocollision.collisionLookup = {}
local lookup = cocollision.collisionLookup

lookup.none = {}
lookup.none.none = returnFalse
lookup.none.point = returnFalse
lookup.none.edge = returnFalse
lookup.none.ray = returnFalse
lookup.none.line = returnFalse
lookup.none.rectangle = returnFalse
lookup.none.polygon = returnFalse
lookup.none.circle = returnFalse
lookup.none.donut = returnFalse

lookup.point = {}
lookup.point.none = returnFalse
lookup.point.point = pointIsOnPointVert
lookup.point.edge = pointOnSegmentVert
lookup.point.ray = pointOnRayVert
lookup.point.line = pointOnLineVert
lookup.point.rectangle = pointInRectangleVert
lookup.point.polygon = pointInPolygonVert
lookup.point.circle = pointInCircleVert
lookup.point.donut = pointInDonutVert

lookup.edge = {}
lookup.edge.none = returnFalse
lookup.edge.point = segmentIsUnderPointVert
lookup.edge.edge = segmentsIntersectVert
lookup.edge.ray = segmentCrossesRayVert
lookup.edge.line = segmentCrossesLineVert
lookup.edge.rectangle = segmentCrossesPolygonVert
lookup.edge.polygon = segmentCrossesPolygonVert
lookup.edge.circle = segmentIsUnderCircleVert
lookup.edge.donut = segmentCrossesDonutVert

lookup.ray = {}
lookup.ray.none = returnFalse
lookup.ray.point = rayIsUnderPointVert
lookup.ray.edge = rayCrossesSegmentVert
lookup.ray.ray = raysIntersectVert
lookup.ray.line = rayCrossesLineVert
lookup.ray.rectangle = rayCrossesPolygonVert
lookup.ray.polygon = rayCrossesPolygonVert
lookup.ray.circle = rayIsUnderCircleVert
lookup.ray.donut = rayIsUnderCircleVert

lookup.line = {}
lookup.line.none = returnFalse
lookup.line.point = lineIsUnderPointVert
lookup.line.edge = lineCrossesSegmentVert
lookup.line.ray = lineCrossesRayVert
lookup.line.line = linesIntersectVert
lookup.line.rectangle = lineCrossesPolygonVert
lookup.line.polygon = lineCrossesPolygonVert
lookup.line.circle = lineIsUnderCircleVert
lookup.line.donut = lineIsUnderCircleVert

lookup.rectangle = {}
lookup.rectangle.none = returnFalse
lookup.rectangle.point = rectangleIsUnderPointVert
lookup.rectangle.edge = polygonGetsHitBySegmentVert
lookup.rectangle.ray = polygonGetsHitByRayVert
lookup.rectangle.line = polygonGetsHitByLineVert
lookup.rectangle.rectangle = rectanglesIntersect
lookup.rectangle.polygon = polygonsIntersect
lookup.rectangle.circle = polygonIntersectsCircleVert
lookup.rectangle.donut = polygonIntersectsDonutVert

lookup.polygon = {}
lookup.polygon.none = returnFalse
lookup.polygon.point = polygonIsUnderPointVert
lookup.polygon.edge = polygonGetsHitBySegmentVert
lookup.polygon.ray = polygonGetsHitByRayVert
lookup.polygon.line = polygonGetsHitByLineVert
lookup.polygon.rectangle = polygonsIntersect
lookup.polygon.polygon = polygonsIntersect
lookup.polygon.circle = polygonIntersectsCircleVert
lookup.polygon.donut = polygonIntersectsDonutVert

lookup.circle = {}
lookup.circle.none = returnFalse
lookup.circle.point = circleUnderPointVert
lookup.circle.edge = circleOnSegmentVert
lookup.circle.ray = circleOnRayVert
lookup.circle.line = circleOnLineVert
lookup.circle.rectangle = circleIntersectsPolygonVert
lookup.circle.polygon = circleIntersectsPolygonVert
lookup.circle.circle = circlesIntersectVert
lookup.circle.donut = circleIntersectsDonutVert

lookup.donut = {}
lookup.donut.none = returnFalse
lookup.donut.point = donutUnderPointVert
lookup.donut.edge = donutOnSegmentVert
lookup.donut.ray = circleOnRayVert
lookup.donut.line = circleOnLineVert
lookup.donut.rectangle = donutIntersectsPolygonVert
lookup.donut.polygon = donutIntersectsPolygonVert
lookup.donut.circle = donutIntersectsCircleVert
lookup.donut.donut = donutsIntersectVert

-- Abstraction for possible usage outside LÖVE -----------------------------------------------------
-- These are just for visual debugging, and arent't necessary for cocollision to work.

-- Can be replaced with functions to perform these actions in non-love2d environments
cocollision.graphics = {}

---@diagnostic disable-next-line: undefined-global
local love = love

local colorMild = {0.25, 0.5, 1, 0.25}
local colorFull = {0.25, 0.5, 1, 0.75}

---@param shape Cocollision.Shape
---@param fullColor? boolean
---@param drawBounds? boolean
cocollision.graphics.debugDrawShape = function(shape, fullColor, drawBounds)
    local color = fullColor and colorFull or colorMild

    local x, y = shape.x, shape.y
    local vertices = {unpack(shape:getTransformedVertices())}
    for vertexIndex = 1, #vertices, 2 do
        vertices[vertexIndex] = vertices[vertexIndex] + x
        vertices[vertexIndex + 1] = vertices[vertexIndex + 1] + y
    end

    if shape.shapeType == "ray" then
        vertices[3] = vertices[1] + (vertices[3] - vertices[1]) * 1000
        vertices[4] = vertices[2] + (vertices[4] - vertices[2]) * 1000
    elseif shape.shapeType == "line" then
        local x1 = vertices[1]
        local y1 = vertices[2]
        local x2 = vertices[3]
        local y2 = vertices[4]
        local dx = x2 - x1
        local dy = y2 - y1
        vertices[1] = x2 - dx * 1000
        vertices[2] = y2 - dy * 1000
        vertices[3] = x1 + dx * 1000
        vertices[4] = y1 + dy * 1000
    end

    local cr, cg, cb, ca = love.graphics.getColor()

    local hasBounds = not cocollision.boundlessShapes[shape.shapeType]
    if drawBounds and hasBounds then
        love.graphics.setColor(colorMild)
        local bbox = shape:getBoundingBox()
        if #bbox == 8 then
            love.graphics.line(bbox[1] + x, bbox[2] + y, bbox[3] + x, bbox[4] + y)
            love.graphics.line(bbox[3] + x, bbox[4] + y, bbox[5] + x, bbox[6] + y)
            love.graphics.line(bbox[5] + x, bbox[6] + y, bbox[7] + x, bbox[8] + y)
            love.graphics.line(bbox[7] + x, bbox[8] + y, bbox[1] + x, bbox[2] + y)
        end
    end

    if shape.shapeType == "circle" then
        love.graphics.setColor(color)
        love.graphics.circle("fill", vertices[1], vertices[2], vertices[3] - vertices[1])
        love.graphics.setColor(colorFull)
        love.graphics.circle("line", vertices[1], vertices[2], vertices[3] - vertices[1])

        love.graphics.setColor(cr, cg, cb, ca)
        return
    end

    if shape.shapeType == "donut" then
        local r1 = vertices[3] - vertices[1]
        local r2 = vertices[5] - vertices[1]
        love.graphics.setColor(color)

        love.graphics.stencil(function ()
            love.graphics.circle("fill", vertices[1], vertices[2], r2)
        end)
        love.graphics.setStencilTest("equal", 0)
        love.graphics.circle("fill", vertices[1], vertices[2], r1)
        love.graphics.setStencilTest()

        love.graphics.setColor(colorFull)
        love.graphics.circle("line", vertices[1], vertices[2], r1)
        love.graphics.circle("line", vertices[1], vertices[2], r2)

        love.graphics.setColor(cr, cg, cb, ca)
        return
    end

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

cocollision.Shape = Shape -- The definition of the `Shape` class, mostly exposed for possible inheritance purposes

return cocollision