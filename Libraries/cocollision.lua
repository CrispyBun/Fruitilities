local cocollision = {}

---@diagnostic disable-next-line: deprecated
local unpack = table.unpack or unpack

-- Config stuff ------------------------------------------------------------------------------------

-- If this is 0, resolving collisions with the push vector will resolve the shapes
-- into a position where they are just barely touching.  
-- This is just a number added to the push vector's distance to make sure the collision is fully resolved.
cocollision.pushVectorIncrease = 1e-10

-- The margin of error for point on point and point on line intersections.  
-- * If this is 0, the point must be *exactly* on the other point or line to intersect, which might not be what you want.  
-- * If this is >0, it's the distance from the true colliding location that's still considered colliding.
cocollision.pointIntersectionMargin = 0.5

-- Shapes for which a bounding box is not calculated or checked.  
-- There's likely no reason for you to change this table, unless you're adding your own shape types.
cocollision.boundlessShapes = {
    rectangle = true, -- Doesn't need bounds, it *is* the bounds
    point = true, -- Can't have a bbox check because that would make `pointIntersectionMargin` not work
    none = true,
    ray = true,
    line = true,
}

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
local Shape = {}
local ShapeMT = {__index = Shape}

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
    ---@type Cocollision.Shape
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
--- ### Shape:setPosition(x, y)
--- Sets the shape's position.
---@param x number
---@param y number
---@return Cocollision.Shape self
function Shape:setPosition(x, y)
    self.x = x
    self.y = y
    return self
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

    local checkBounds = not (cocollision.boundlessShapes[selfShapeType] or cocollision.boundlessShapes[otherShapeType])
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
--- ### Shape:removeShape()
--- Sets the shape type to "none" and removes all vertices.
---@return Cocollision.Shape self
function Shape:removeShape()
    self.shapeType = "none"
    self.vertices = {}
    self:refreshTransform()
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
---@return Cocollision.Shape self
function Shape:setVertex(n, x, y)
    local vertices = self.vertices
    vertices[n * 2 - 1] = x
    vertices[n * 2] = y
    self:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:removeVertex(n)
--- Removes the nth vertex of the shape.
---@param n integer
---@return Cocollision.Shape self
function Shape:removeVertex(n)
    local vertices = self.vertices
    table.remove(vertices, n * 2 - 1)
    table.remove(vertices, n * 2 - 1)
    self:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:addVertex(x, y)
--- Appends a new vertex to the shape (after the last vertex).
---@param x number
---@param y number
---@return Cocollision.Shape self
function Shape:addVertex(x, y)
    local vertices = self.vertices
    vertices[#vertices + 1] = x
    vertices[#vertices + 1] = y
    self:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:insertVertex(n, x, y)
--- Inserts a new vertex into the shape before the nth vertex.
---@param n integer
---@param x number
---@param y number
---@return Cocollision.Shape self
function Shape:insertVertex(n, x, y)
    local vertices = self.vertices
    table.insert(vertices, n * 2 - 1, x)
    table.insert(vertices, n * 2, y)
    self:refreshTransform()
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
---@return Cocollision.Shape self
function Shape:setOrigin(x, y)
    self.originX = x
    self.originY = y
    self:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:setRotation(rotation)
--- Sets the shape's rotation.
---@param r number
---@return Cocollision.Shape self
function Shape:setRotation(r)
    self.rotation = r
    self:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:setScale(sx, sy)
--- Sets the shape's scale. If `sy` is not supplied, sets both axes to the first argument.
---@param sx number
---@param sy? number
---@return Cocollision.Shape self
function Shape:setScale(sx, sy)
    self.scaleX = sx
    self.scaleY = sy or sx
    self:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:setTranslate(x, y)
--- Sets the shape's translate.
---@param x number
---@param y number
---@return Cocollision.Shape self
function Shape:setTranslate(x, y)
    self.translateX = x
    self.translateY = y
    self:refreshTransform()
    return self
end

--------------------------------------------------
--- ### Shape:setRectangularRotation(doRectangularRotation)
--- Sets whether the shape should rotate if its type is a rectangle. This is false by default.
---@param doRectangularRotation boolean
---@return Cocollision.Shape self
function Shape:setRectangularRotation(doRectangularRotation)
    self.doRectangularRotation = doRectangularRotation
    self:refreshTransform()
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
        if self.shapeType == "circle" then rotation = 0 end

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

        if self.shapeType == "circle" then
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
--- ### Shape:debugDraw()
--- Draws the shape for debugging purposes.  
--- This is the only platform dependent function. If shape drawing isn't implemented, this function does nothing.
---@param fullColor? boolean
---@param drawBounds? boolean
function Shape:debugDraw(fullColor, drawBounds)
    return cocollision.graphics.debugDrawShape(self, fullColor, drawBounds)
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

    -- If we made it here, there was a collision

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

--- Checks if a point is on top of another point.
---@param p1x number The X position of the first point
---@param p1y number The Y position of the first point
---@param p2x number The X position of the second point
---@param p2y number The Y position of the second point
---@return boolean intersected
function cocollision.pointIsOnPoint(p1x, p1y, p2x, p2y)
    local differenceX = p1x - p2x
    local differenceY = p1y - p2y
    local distance = math.sqrt(differenceX * differenceX + differenceY * differenceY)
    return distance <= cocollision.pointIntersectionMargin
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
    return circleOnLine(pointX, pointY, cocollision.pointIntersectionMargin, lineX1, lineY1, lineX2, lineY2, lineEndpointCount)
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

lookup.point = {}
lookup.point.none = returnFalse
lookup.point.point = pointIsOnPointVert
lookup.point.edge = pointOnSegmentVert
lookup.point.ray = pointOnRayVert
lookup.point.line = pointOnLineVert
lookup.point.rectangle = pointInRectangleVert
lookup.point.polygon = pointInPolygonVert
lookup.point.circle = pointInCircleVert

lookup.edge = {}
lookup.edge.none = returnFalse
lookup.edge.point = segmentIsUnderPointVert
lookup.edge.edge = segmentsIntersectVert
lookup.edge.ray = segmentCrossesRayVert
lookup.edge.line = segmentCrossesLineVert
lookup.edge.rectangle = segmentCrossesPolygonVert
lookup.edge.polygon = segmentCrossesPolygonVert
lookup.edge.circle = segmentIsUnderCircleVert

lookup.ray = {}
lookup.ray.none = returnFalse
lookup.ray.point = rayIsUnderPointVert
lookup.ray.edge = rayCrossesSegmentVert
lookup.ray.ray = raysIntersectVert
lookup.ray.line = rayCrossesLineVert
lookup.ray.rectangle = rayCrossesPolygonVert
lookup.ray.polygon = rayCrossesPolygonVert
lookup.ray.circle = rayIsUnderCircleVert

lookup.line = {}
lookup.line.none = returnFalse
lookup.line.point = lineIsUnderPointVert
lookup.line.edge = lineCrossesSegmentVert
lookup.line.ray = lineCrossesRayVert
lookup.line.line = linesIntersectVert
lookup.line.rectangle = lineCrossesPolygonVert
lookup.line.polygon = lineCrossesPolygonVert
lookup.line.circle = lineIsUnderCircleVert

lookup.rectangle = {}
lookup.rectangle.none = returnFalse
lookup.rectangle.point = rectangleIsUnderPointVert
lookup.rectangle.edge = polygonGetsHitBySegmentVert
lookup.rectangle.ray = polygonGetsHitByRayVert
lookup.rectangle.line = polygonGetsHitByLineVert
lookup.rectangle.rectangle = rectanglesIntersect
lookup.rectangle.polygon = polygonsIntersect
lookup.rectangle.circle = returnFalse -- todo

lookup.polygon = {}
lookup.polygon.none = returnFalse
lookup.polygon.point = polygonIsUnderPointVert
lookup.polygon.edge = polygonGetsHitBySegmentVert
lookup.polygon.ray = polygonGetsHitByRayVert
lookup.polygon.line = polygonGetsHitByLineVert
lookup.polygon.rectangle = polygonsIntersect
lookup.polygon.polygon = polygonsIntersect
lookup.polygon.circle = returnFalse -- todo

lookup.circle = {}
lookup.circle.none = returnFalse
lookup.circle.point = circleUnderPointVert
lookup.circle.edge = circleOnSegmentVert
lookup.circle.ray = circleOnRayVert
lookup.circle.line = circleOnLineVert
lookup.circle.rectangle = returnFalse -- todo
lookup.circle.polygon = returnFalse -- todo
lookup.circle.circle = returnFalse -- todo

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

return cocollision