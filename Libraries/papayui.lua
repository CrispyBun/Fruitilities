local papayui = {}

-- Global UI values --------------------------------------------------------------------------------

-- Feel free to add as many of your own colors to this as you want (or overwrite it with a different colors table)
papayui.colors = {}
papayui.colors.background = {0.25, 0.25, 0.5}
papayui.colors.foreground = {0.1, 0.1,  0.2}
papayui.colors.primary = {0.75, 0.75, 0.5}
papayui.colors.secondary = {0.6, 0.4, 0.3}
papayui.colors.highlight = {1, 1, 1}
papayui.colors.hover = {0.5, 0.5, 1}
papayui.colors.text = {0.9, 0.9, 0.9}
papayui.colors.title = {1, 1, 1}

-- Change and then refresh any UIs
papayui.scale = 1

-- Class definitions -------------------------------------------------------------------------------

---@alias PapayuiElementLayout
---| '"none"' # The elements are not displayed
---| '"singlerow"' # A single horizontal row of elements
---| '"singlecolumn"' # A single vertical column of elements
---| '"rows"' # Horizontal rows of elements
---| '"columns"' # Vertical columns of elements

---@alias PapayuiAlignment
---| '"start"' # Aligns to the left or top
---| '"center"' # Aligns to the center
---| '"end"' # Aligns to the right or bottom
---| '"left"' # Same as 'start'
---| '"top"' # Same as 'start'
---| '"right"' # Same as 'end'
---| '"bottom"' # Same as 'end'
---| '"middle"' # Same as 'center'

---@class PapayuiElementStyle
---@field width number The width of the element
---@field height number The height of the element
---@field growHorizontal boolean Whether the element should grow horizontally to take up full parent space
---@field growVertical boolean Whether the element should grow vertically to take up full parent space
---@field padding number[] The padding of the element, in the format {left, top, right, bottom}
---@field margin number[] The margin of the element, in the format {left, top, right, bottom}
---@field color? string The background color of this element, from the ui.colors table
---@field colorHover? string The background color of this element when it's hovered over
---@field layout PapayuiElementLayout The way this element's children will be laid out
---@field alignHorizontal PapayuiAlignment The horizontal alignment of the element's children
---@field alignVertical PapayuiAlignment The vertical alignment of the element's children
---@field alignInside PapayuiAlignment The alignment of all the individual child elements within a line
---@field scrollHorizontal boolean Whether or not any horizontal overflow in the element's children should scroll
---@field scrollVertical boolean Whether or not any vertical overflow in the element's children should scroll
---@field gap number[] The gap between its child elements in the layout, in the format {horizontal, vertical}
---@field maxLineElements (number|nil)|(number|nil)[] Sets a limit to the amount of elements that can be present in a given row/column. If set to a number, all lines get this limit. If set to an array of numbers, each array index corresponds to a given line index. Nil for unlimited.
---@field ignoreScale boolean Determines if papayui.scale has an effect on the size of this element (useful to enable for root elements which fill screen space)
local ElementStyle = {}
local ElementStyleMT = {__index = ElementStyle}

---@class PapayuiElementBehavior

---@class PapayuiElement
---@field style PapayuiElementStyle The style this element uses
---@field behavior PapayuiElementBehavior The behavior this element uses
---@field children PapayuiElement[] The children of this element (can be empty)
local Element = {}
local ElementMT = {__index = Element}

---@class PapayuiUI
---@field members PapayuiLiveMember[] All the elements in the UI, in the drawn order
local UI = {}
local UIMT = {__index = UI}

--- The instanced element in an actual UI, with a state. You don't really have to worry about these, they're used internally
---@class PapayuiLiveMember
---@field element PapayuiElement The element this is an instance of
---@field parent? PapayuiLiveMember The parent of this member
---@field x number The x position of the element
---@field y number The y position of the element
---@field width number The actual width of the element
---@field height number The actual height of the element
---@field scrollX number The amount of scroll in the X direction
---@field scrollY number The amount of scroll in the Y direction
local LiveMember = {}
local LiveMemberMT = {__index = LiveMember}

-- Element creation --------------------------------------------------------------------------------

--------------------------------------------------
--- ### papayui.newElementStyle()
--- Creates a new blank papayui element style.
---
--- Optionally, you can supply an array of tables, each of which can contain values for the style.
--- If values are present in multiple of these tables, the last table in the list has priority.
---
--- Example usage:
--- ```
--- local style = papayui.newElementStyle()
--- style.width = 200
--- style.height = 150
--- style.color = "background"
--- style.layout = "singlecolumn"
--- ```
---@param mixins? table[]
---@return PapayuiElementStyle
function papayui.newElementStyle(mixins)
    ---@type PapayuiElementStyle
    local style = {
        width = 0,
        height = 0,
        growHorizontal = false,
        growVertical = false,
        padding = {0, 0, 0, 0},
        margin = {0, 0, 0, 0},
        layout = "singlerow",
        alignHorizontal = "start",
        alignVertical = "start",
        alignInside = "start",
        scrollHorizontal = false,
        scrollVertical = false,
        gap = {0, 0},
        ignoreScale = false
    }

    if mixins then
        for mixinIndex = 1, #mixins do
            for key, value in pairs(mixins[mixinIndex]) do
                style[key] = value
            end
        end
    end

    return setmetatable(style, ElementStyleMT)
end

--------------------------------------------------
--- ### papayui.newElementBehavior()
--- Creates a new blank papayui element behavior.
---@return PapayuiElementBehavior
function papayui.newElementBehavior()
    ---@type PapayuiElementBehavior
    local behavior = {
    }
    return behavior
end

--------------------------------------------------
--- ### papayui.newElement()
--- Creates a new blank papayui element.
--- You can give it a style and behavior, but if not provided, they will be default blank ones (no visual style, no behavior)
---
--- Example usage:
--- ```
--- local element = papayui.newElement(style, behavior)
--- element.children = {otherElement1, otherElement2}
--- ```
---@param style? PapayuiElementStyle
---@param behavior? PapayuiElementBehavior
---@return PapayuiElement
function papayui.newElement(style, behavior)
    style = style or papayui.newElementStyle()
    behavior = behavior or papayui.newElementBehavior()

    ---@type PapayuiElement
    local element = {
        style = style,
        behavior = behavior,
        children = {}
    }

    return setmetatable(element, ElementMT)
end

--------------------------------------------------
--- ### papayui.newUI(rootElement)
--- Creates a new usable UI, using the given element as the main parent element. Can specify an X and Y location for the UI.
---@param rootElement PapayuiElement The root element of the whole UI
---@param x? number The X coordinate of the UI (Default is 0)
---@param y? number The Y coordinate of the UI (Default is 0)
---@return PapayuiUI
function papayui.newUI(rootElement, x, y)
    ---@type PapayuiUI
    local ui = {
        members = {}
    }

    local rootMember = papayui.newLiveMember(rootElement, x, y)

    local memberQueueFirst = {value = rootMember, next = nil}
    local memberQueueLast = memberQueueFirst
    while memberQueueFirst do
        ---@type PapayuiLiveMember
        local member = memberQueueFirst.value
        local layout = member.element.style.layout

        if layout and papayui.layouts[layout] then
            ---@type PapayuiLiveMember[]
            local addedMembers = papayui.layouts[layout](member)

            for addedIndex = 1, #addedMembers do
                local addedMember = addedMembers[addedIndex]
                local nextQueueItem = {value = addedMember, next = nil}
                memberQueueLast.next = nextQueueItem
                memberQueueLast = nextQueueItem
            end
        end

        ui.members[#ui.members+1] = member
        memberQueueFirst = memberQueueFirst.next
    end

    return setmetatable(ui, UIMT)
end

-- UI methods --------------------------------------------------------------------------------------

--------------------------------------------------
--- ### UI.draw()
--- Draws the UI.
function UI:draw()
    local members = self.members
    for memberIndex = 1, #members do
        local member = members[memberIndex]
        member.element:draw(member:getBounds())
    end
end

-- Style methods -----------------------------------------------------------------------------------

local function generateDirectionalValue(left, top, right, bottom)
    left = left or 0
    top = top or left
    right = right or left
    bottom = bottom or top
    return {left, top, right, bottom}
end

local function deepCopy(t, _seenTables)
    _seenTables = _seenTables or {}
    if type(t) == "table" then
        local copiedTable = {}

        if _seenTables[t] then
            return _seenTables[t]
        else
            _seenTables[t] = copiedTable
        end

        for key, value in pairs(t) do
            copiedTable[key] = deepCopy(value, _seenTables)
        end
        return copiedTable
    end
    return t
end

--------------------------------------------------
--- ### ElementStyle:setPadding(left, top, right, bottom)
--- Sets the style's padding.
---
--- * If no parameters are entered, the padding is set to 0.
--- * If one parameter is entered, padding in all directions is set to that number.
--- * If two parameters are entered, the horizontal padding is set to the first number, and the vertical padding is set to the second number.
--- * If three parameters are entered, they set the left, vertical, and right padding, respectively.
--- * If four parameters are entered, they set the left, top, right, and bottom padding, respectively.
---@param left? number
---@param top? number
---@param right? number
---@param bottom? number
function ElementStyle:setPadding(left, top, right, bottom)
    self.padding = generateDirectionalValue(left, top, right, bottom)
end

--------------------------------------------------
--- ### ElementStyle:setMargin(left, top, right, bottom)
--- Sets the style's margin, following the same rules as in ElementStyle:setPadding().
---@param left? number
---@param top? number
---@param right? number
---@param bottom? number
function ElementStyle:setMargin(left, top, right, bottom)
    self.margin = generateDirectionalValue(left, top, right, bottom)
end

--------------------------------------------------
--- ### ElementStyle:setGap(horizontalGap, verticalGap)
--- Sets the style's gap between the children elements in the layout.
---
--- If only one number is supplied, both the horizontal and vertical gap is set to it. <br>
--- If no number is supplied, the gap is set to 0.
---@param horizontalGap? number
---@param verticalGap? number
function ElementStyle:setGap(horizontalGap, verticalGap)
    horizontalGap = horizontalGap or 0
    verticalGap = verticalGap or horizontalGap
    self.gap = {horizontalGap, verticalGap}
end

--------------------------------------------------
--- ### ElementStyle:setGrow(horizontalGrow, verticalGrow)
--- Sets the style's horizontal and vertical grow.
---
--- If only the first value is supplied, it is applied to both horizontal and vertical grow.
---@param horizontalGrow boolean
---@param verticalGrow? boolean
function ElementStyle:setGrow(horizontalGrow, verticalGrow)
    if verticalGrow == nil then verticalGrow = horizontalGrow end
    self.growHorizontal = horizontalGrow
    self.growVertical = verticalGrow
end

--------------------------------------------------
--- ### ElementStyle:setLayout(layout, alignHorizontal, alignVertical)
--- Sets the style's layout as well as alignment.
--- 
--- If verticalAlign isn't supplied, it is set to the same align as horizontalAlign.  
--- If alignInside isn't supplied, it will set itself to be same as the align on the cross axis, based on the selected layout.
---@param layout PapayuiElementLayout
---@param alignHorizontal PapayuiAlignment
---@param alignVertical? PapayuiAlignment
---@param alignInside? PapayuiAlignment
function ElementStyle:setLayout(layout, alignHorizontal, alignVertical, alignInside)
    alignVertical = alignVertical or alignHorizontal

    if not alignInside then
        local alignCross = alignVertical
        if layout == "singlecolumn" or layout == "columns" then
            alignCross = alignHorizontal
        end
        alignInside = alignCross
    end

    self.layout = layout
    self.alignHorizontal = alignHorizontal
    self.alignVertical = alignVertical
    self.alignInside = alignInside
end

--------------------------------------------------
--- ### ElementStyle:clone()
--- Returns a copy of the style
---@return PapayuiElementStyle
function ElementStyle:clone()
    local copiedTable = deepCopy(self)
    return setmetatable(copiedTable, ElementStyleMT)
end

-- Element methods ---------------------------------------------------------------------------------

---@param x? number The X coordinate to draw at (Default is 0)
---@param y? number The Y coordinate to draw at (Default is 0)
---@param width? number The width to draw the element as (Default is element's width)
---@param height? number The height to draw the element as (Default is the element's height)
function Element:draw(x, y, width, height)
    local style = self.style
    x = x or 0
    y = y or 0
    width = width or style.width
    height = height or style.height

    local color = papayui.colors[style.color]
    if style.color and not color then
        color = {1, 0, 0} -- "Invalid color" redness
    end

    if color then
        papayui.drawRectangle(x, y, width, height, color)
    end
end

-- Abstraction for possible usage outside LÖVE -----------------------------------------------------

local emptyFunction = function () end

function papayui.drawRectangle(x, y, width, height, color)
    local cr, cg, cb, ca = love.graphics.getColor()
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x, y, width, height)
    love.graphics.setColor(cr, cg, cb, ca)
end
if not love then papayui.drawRectangle = emptyFunction end

-- Element layouts ---------------------------------------------------------------------------------

local alignEnum = {
    start = -1,
    ["end"] = 1,
    left = -1,
    top = -1,
    center = 0,
    middle = 0,
    right = 1,
    bottom = 1
}

local function getNudgeValue(usableSpace, usedSpace, align)
    local unusedSpace = usableSpace - usedSpace
    return (align * unusedSpace + unusedSpace) / 2
end

---@param elements PapayuiElement[]
---@param parentMember PapayuiLiveMember
---@return PapayuiLiveMember[]
local function generateMembers(elements, parentMember)
    ---@type PapayuiLiveMember[]
    local members = {}
    for elementIndex = 1, #elements do
        local element = elements[elementIndex]
        members[elementIndex] = papayui.newLiveMember(element, 0, 0, parentMember)
    end
    return members
end

---@param members PapayuiLiveMember[]
---@param gap number
---@param isVertical boolean
---@return number lineSizeMain
---@return number lineSizeCross
local function layMembersInLine(members, gap, alignInside, isVertical)
    local marginStart = isVertical and 2 or 1
    local marginEnd = isVertical and 4 or 3
    local sizeMain = isVertical and "height" or "width"
    local sizeCross = isVertical and "width" or "height"

    -- Find tallest member
    local tallestMember = 0
    for memberIndex = 1, #members do
        tallestMember = math.max(tallestMember, members[memberIndex][sizeCross])
    end

    -- Lay them out
    local nextPos = 0
    for memberIndex = 1, #members do
        local member = members[memberIndex]
        local style = member.element.style

        local marginStartValue = style.margin[marginStart]
        local marginEndValue = style.margin[marginEnd]
        if memberIndex == 1 then marginStartValue = 0 end      -- Ignore the start and end margins,
        if memberIndex == #members then marginEndValue = 0 end -- the line doesnt take any container into account yet

        -- Alignment inside line
        local insideNudge = getNudgeValue(tallestMember, member[sizeCross], alignInside)

        nextPos = nextPos + marginStartValue
        local memberX = isVertical and insideNudge or nextPos
        local memberY = isVertical and nextPos or insideNudge

        member.x = memberX
        member.y = memberY

        nextPos = nextPos + member[sizeMain] + marginEndValue + gap
    end

    local lineSizeMain = nextPos - gap
    local lineSizeCross = tallestMember

    return lineSizeMain, lineSizeCross
end

local function memberIsLessWide(a, b) return a.width < b.width end
local function memberIsLessTall(a, b) return a.height < b.height end
---@param members PapayuiLiveMember
---@param usableSpaceWidth number
---@param usableSpaceHeight number
---@param gap number
---@param lineIsVertical boolean
---@param dontFillCrossSpace? boolean
local function growLineMembers(members, usableSpaceWidth, usableSpaceHeight, gap, lineIsVertical, dontFillCrossSpace)
    local sortFunction = lineIsVertical and memberIsLessTall or memberIsLessWide
    local usableSpaceMain = lineIsVertical and usableSpaceHeight or usableSpaceWidth
    local usableSpaceCross = lineIsVertical and usableSpaceWidth or usableSpaceHeight
    local sizeMain = lineIsVertical and "height" or "width"
    local sizeCross = lineIsVertical and "width" or "height"
    local growMain = lineIsVertical and "growVertical" or "growHorizontal"
    local growCross = lineIsVertical and "growHorizontal" or "growVertical"
    local marginStart = lineIsVertical and 2 or 1
    local marginEnd = lineIsVertical and 4 or 3

    if dontFillCrossSpace then
        local tallestMember = 0
        for memberIndex = 1, #members do
            tallestMember = math.max(tallestMember, members[memberIndex][sizeCross])
        end
        usableSpaceCross = tallestMember
    end

    -- Exclude the gaps between elements from being usable for space distribution
    usableSpaceMain = usableSpaceMain - (#members - 1) * gap

    local growingMembers = {}
    for memberIndex = 1, #members do
        local member = members[memberIndex]
        local style = member.element.style

        if member.element.style[growMain] then
            growingMembers[#growingMembers+1] = member
        else
            -- Exclude space taken up by non-growing elements
            usableSpaceMain = usableSpaceMain - member[sizeMain]
        end

        -- Exclude space taken up by all margins, those don't grow either
        usableSpaceMain = usableSpaceMain - style.margin[marginStart] - style.margin[marginEnd]

        -- Grow the cross axis
        if member.element.style[growCross] then
            local currentSizeCross = member[sizeCross]
            member[sizeCross] = math.max(currentSizeCross, usableSpaceCross)
        end
    end

    table.sort(growingMembers, sortFunction)

    for memberIndex = #growingMembers, 1, -1 do
        local member = growingMembers[memberIndex]

        local assignedSize = usableSpaceMain / memberIndex
        if member[sizeMain] <= assignedSize then
            -- Min grow element size found
            for grownMemberIndex = memberIndex, 1, -1 do
                growingMembers[grownMemberIndex][sizeMain] = assignedSize
            end
            break
        end

        -- Member is too big to grow, exclude it from the usable space
        usableSpaceMain = usableSpaceMain - member[sizeMain]
    end
end

---@param members PapayuiLiveMember[]
---@param usableSpaceMain number
---@param gap number
---@param mainAxisIsVertical boolean
---@param maxLineElements? number|table
---@return PapayuiLiveMember[][]
local function splitMembersToLines(members, usableSpaceMain, gap, mainAxisIsVertical, maxLineElements)
    local sizeMain = mainAxisIsVertical and "height" or "width"
    local marginStart = mainAxisIsVertical and 2 or 1
    local marginEnd = mainAxisIsVertical and 4 or 3

    maxLineElements = maxLineElements or math.huge

    local lines = {}
    local currentLineIndex = 1
    local currentLineSize = 0
    local currentMemberIndex = 1
    for memberIndex = 1, #members do
        local member = members[memberIndex]
        local memberMargin = member.element.style.margin

        local memberSize = member[sizeMain] + memberMargin[marginStart] + memberMargin[marginEnd]
        local maxMemberIndex = type(maxLineElements) == "number" and maxLineElements or maxLineElements[currentLineIndex]
        maxMemberIndex = maxMemberIndex or math.huge

        local memberFits = (currentLineSize + memberSize <= usableSpaceMain) and (currentMemberIndex <= maxMemberIndex)
        currentMemberIndex = currentMemberIndex + 1

        if not lines[currentLineIndex] then
            -- Prevent 0 members on line
            -- (would cause an infinite loop of a member always being too big)
            lines[currentLineIndex] = {member}
        else
            -- Add member if it still fits or start a new one
            if memberFits then
                local currentLine = lines[currentLineIndex]
                currentLine[#currentLine+1] = member
            else
                currentLineIndex = currentLineIndex + 1
                currentLineSize = 0
                currentMemberIndex = 2 -- 2 because we're already adding the first
                lines[currentLineIndex] = {member}
            end
        end

        currentLineSize = currentLineSize + memberSize + gap
    end
    return lines
end

---@param members PapayuiLiveMember[]
---@param x number
---@param y number
---@param width number
---@param height number
---@param alignHorizontal number
---@param alignVertical number
local function alignMembers(members, x, y, width, height, alignHorizontal, alignVertical)

    -- Get space taken up by members
    local leftmostPoint = math.huge
    local topmostPoint = math.huge
    local rightmostPoint = -math.huge
    local bottommostPoint = -math.huge
    for memberIndex = 1, #members do
        local member = members[memberIndex]

        local memberMargin = member.element.style.margin
        local memberX = member.x
        local memberY = member.y
        local memberWidth = member.width
        local memberHeight = member.height

        leftmostPoint = math.min(leftmostPoint, memberX - memberMargin[1])
        topmostPoint = math.min(topmostPoint, memberY - memberMargin[2])
        rightmostPoint = math.max(rightmostPoint, memberX + memberWidth + memberMargin[3])
        bottommostPoint = math.max(bottommostPoint, memberY + memberHeight + memberMargin[4])
    end
    local contentWidth = rightmostPoint - leftmostPoint
    local contentHeight = bottommostPoint - topmostPoint

    local xNudge = x + getNudgeValue(width, contentWidth, alignHorizontal) - leftmostPoint -- Top left point subtraction
    local yNudge = y + getNudgeValue(height, contentHeight, alignVertical) - topmostPoint  -- to start at [0; 0]
    for memberIndex = 1, #members do
        local member = members[memberIndex]

        member.x = member.x + xNudge
        member.y = member.y + yNudge
    end

    return contentWidth, contentHeight
end

---@type table<string, fun(member: PapayuiLiveMember, ...?): PapayuiLiveMember[]>
papayui.layouts = {}

function papayui.layouts.none()
    return {}
end

function papayui.layouts.singlerow(parentMember, flipAxis)
    local style = parentMember.element.style
    local children = parentMember.element.children
    local originX = parentMember.x + style.padding[1]
    local originY = parentMember.y + style.padding[2]
    local gap = flipAxis and style.gap[2] or style.gap[1]

    local alignHorizontal = alignEnum[style.alignHorizontal]
    local alignVertical = alignEnum[style.alignVertical]
    local alignInside = alignEnum[style.alignInside]
    local usableSpaceWidth = parentMember.width - style.padding[1] - style.padding[3]
    local usableSpaceHeight = parentMember.height - style.padding[2] - style.padding[4]

    local outMembers = generateMembers(children, parentMember)
    growLineMembers(outMembers, usableSpaceWidth, usableSpaceHeight, gap, flipAxis)
    layMembersInLine(outMembers, gap, alignInside, flipAxis)
    alignMembers(outMembers, originX, originY, usableSpaceWidth, usableSpaceHeight, alignHorizontal, alignVertical)

    return outMembers
end

function papayui.layouts.singlecolumn(parentMember)
    return papayui.layouts.singlerow(parentMember, true)
end

function papayui.layouts.rows(parentMember, flipAxis)
    local style = parentMember.element.style
    local children = parentMember.element.children
    local originX = parentMember.x + style.padding[1]
    local originY = parentMember.y + style.padding[2]
    local gapMain = flipAxis and style.gap[2] or style.gap[1]
    local gapCross = flipAxis and style.gap[1] or style.gap[2]
    local maxLineMembers = style.maxLineElements

    local alignHorizontal = alignEnum[style.alignHorizontal]
    local alignVertical = alignEnum[style.alignVertical]
    local alignInside = alignEnum[style.alignInside]
    local usableSpaceWidth = parentMember.width - style.padding[1] - style.padding[3]
    local usableSpaceHeight = parentMember.height - style.padding[2] - style.padding[4]
    local usableSpaceMain =  flipAxis and usableSpaceHeight or usableSpaceWidth

    local outMembers = {}
    local generatedMembers = generateMembers(children, parentMember)
    local lines = splitMembersToLines(generatedMembers, usableSpaceMain, gapMain, flipAxis, maxLineMembers)

    local lineOffset = 0
    for lineIndex = 1, #lines do
        local line = lines[lineIndex]
        growLineMembers(line, usableSpaceWidth, usableSpaceHeight, gapMain, flipAxis, true)
        layMembersInLine(line, gapMain, alignInside, flipAxis)

        local lineX = flipAxis and lineOffset or 0
        local lineY = flipAxis and 0 or lineOffset
        local alignX = flipAxis and -1 or alignHorizontal
        local alignY = flipAxis and alignVertical or -1

        local lineWidth, lineHeight = alignMembers(line, lineX, lineY, usableSpaceWidth, usableSpaceHeight, alignX, alignY)
        local lineSizeCross = flipAxis and lineWidth or lineHeight
        lineOffset = lineOffset + lineSizeCross + gapCross

        for memberIndex = 1, #line do
            outMembers[#outMembers+1] = line[memberIndex]
        end
    end

    alignMembers(outMembers, originX, originY, usableSpaceWidth, usableSpaceHeight, alignHorizontal, alignVertical)

    return outMembers
end

function papayui.layouts.columns(parentMember)
    return papayui.layouts.rows(parentMember, true)
end

-- Members -----------------------------------------------------------------------------------------

--- Used internally by the library
---@param element PapayuiElement
---@param x? number
---@param y? number
---@param parent? PapayuiLiveMember
---@return PapayuiLiveMember
function papayui.newLiveMember(element, x, y, parent)
    x = x or 0
    y = y or 0
    local style = element.style
    local scale = style.ignoreScale and 1 or papayui.scale

    ---@type PapayuiLiveMember
    local member = {
        element = element,
        x = x,
        y = y,
        width = style.width * scale,
        height = style.height * scale,
        scrollX = 0,
        scrollY = 0,
        parent = parent
    }

    return setmetatable(member, LiveMemberMT)
end

---@param addX? number Addition to the scrollX
---@param addY? number Addition to the scrollY
---@return number scrollX
---@return number scrollY
function LiveMember:getScroll(addX, addY)
    addX = addX or 0
    addY = addY or 0
    local parent = self.parent
    local x, y = self.scrollX + addX, self.scrollY + addY

    if parent then return parent:getScroll(x, y) end
    return x, y
end

function LiveMember:getBounds()
    local xOffset, yOffset = 0, 0
    if self.parent then xOffset, yOffset = self.parent:getScroll() end

    local x, y = self.x + xOffset, self.y + yOffset
    local width, height = self.width, self.height
    return x, y, width, height
end

-- Fin ---------------------------------------------------------------------------------------------

return papayui