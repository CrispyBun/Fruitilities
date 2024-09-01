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
    rectangle = true
}

-- Definitions -------------------------------------------------------------------------------------

---@alias Cocollision.ShapeType
---| '"none"' # An empty shape that doesn't collide with anything
---| '"rectangle"' # An axis aligned rectangle
---| '"polygon"' # A convex polygon

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
    if #vertices == 0 then return _receivingTable end

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
--- Rectangles output a push vector as the second argument in collisions with other rectangles or polygons.
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
--- Creates a new convex polygon shape. The vertices may be supplied as alternating X and Y coordinates in either a single flat array or a vararg.  
--- Polygons output a push vector as the second argument in collisions with other rectangles or polygons.
---@param ... number
---@return Cocollision.Shape
---@overload fun(vertices: number[]): Cocollision.Shape
function cocollision.newPolygonShape(...)
    return cocollision.newShape():setShapeToPolygon(...)
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
--- Rectangles output a push vector as the second argument in collisions with other rectangles or polygons.
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
--- Sets the shape to be a convex polygon. The vertices may be supplied as alternating X and Y coordinates in either a single flat array or a vararg.  
--- Polygons output a push vector as the second argument in collisions with other rectangles or polygons.
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
        cocollision.generateBoundingBox(transformedVertices, bbox)
        self.boundingBox = bbox
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

            local perpendicularX = -edgeY
            local perpendicularY = edgeX

            -- Bounds of the projections onto the perpendicular vector
            local min1, max1 = math.huge, -math.huge
            local min2, max2 = math.huge, -math.huge

            for projectedVertexIndex1 = 1, #polygon1, 2 do
                local x = polygon1[projectedVertexIndex1] + x1
                local y = polygon1[projectedVertexIndex1 + 1] + y1

                local projection1 = x * perpendicularX + y * perpendicularY -- dot
                min1 = math.min(min1, projection1)
                max1 = math.max(max1, projection1)
            end
            for projectedVertexIndex2 = 1, #polygon2, 2 do
                local x = polygon2[projectedVertexIndex2] + x2
                local y = polygon2[projectedVertexIndex2 + 1] + y2

                local projection2 = x * perpendicularX + y * perpendicularY -- dot
                min2 = math.min(min2, projection2)
                max2 = math.max(max2, projection2)
            end

            if max1 < min2 or min1 > max2 then
                -- Separating axis found
                return false
            end

            -- Collison not ruled out yet, calculate push vector for this edge

            local pushDistance = math.min(max2 - min1, max1 - min2)

            local distanceNormaliser = pushDistance / (perpendicularX * perpendicularX + perpendicularY * perpendicularY)
            local testPushVectorX = perpendicularX * distanceNormaliser
            local testPushVectorY = perpendicularY * distanceNormaliser

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

-- Contains a pair of every combination of two shapes, pointing to the appropriate collision functions
---@type table<Cocollision.ShapeType, table<Cocollision.ShapeType, fun(shape1: number[], shape2: number[], x1?: number, y1?: number, x2?: number, y2?: number): boolean, table?>>
cocollision.collisionLookup = {}
local lookup = cocollision.collisionLookup

lookup.none = {}
lookup.none.none = returnFalse
lookup.none.rectangle = returnFalse
lookup.none.polygon = returnFalse

lookup.rectangle = {}
lookup.rectangle.none = returnFalse
lookup.rectangle.rectangle = cocollision.rectanglesIntersect
lookup.rectangle.polygon = cocollision.polygonsIntersect

lookup.polygon = {}
lookup.polygon.none = returnFalse
lookup.polygon.rectangle = cocollision.polygonsIntersect
lookup.polygon.polygon = cocollision.polygonsIntersect

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

    local cr, cg, cb, ca = love.graphics.getColor()

    if drawBounds then
        love.graphics.setColor(colorMild)
        local bbox = shape:getBoundingBox()
        if #bbox == 8 then
            love.graphics.line(bbox[1] + x, bbox[2] + y, bbox[3] + x, bbox[4] + y)
            love.graphics.line(bbox[3] + x, bbox[4] + y, bbox[5] + x, bbox[6] + y)
            love.graphics.line(bbox[5] + x, bbox[6] + y, bbox[7] + x, bbox[8] + y)
            love.graphics.line(bbox[7] + x, bbox[8] + y, bbox[1] + x, bbox[2] + y)
        end
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