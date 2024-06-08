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

-- Definitions -------------------------------------------------------------------------------------

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
---@field cropContent boolean Whether or not overflow in the element's content should be cropped
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
---@field selectedMember? PapayuiLiveMember The member that is currently selected
---@field actionDown boolean If the action key is currently down (set automatically by the appropriate methods)
---@field cursorXPrevious number The previous cursor X coordinate (used internally)
---@field cursorYPrevious number The previous cursor Y coordinate (used internally)
local UI = {}
local UIMT = {__index = UI}

--- The instanced element in an actual UI, with a state. You don't really have to worry about these, they're used internally
---@class PapayuiLiveMember
---@field element PapayuiElement The element this is an instance of
---@field parent? PapayuiLiveMember The parent of this member
---@field children PapayuiLiveMember[] The children of this member
---@field x number The x position of the element
---@field y number The y position of the element
---@field width number The actual width of the element
---@field height number The actual height of the element
---@field scrollX number The amount of scroll in the X direction
---@field scrollY number The amount of scroll in the Y direction
---@field nav (PapayuiLiveMember?)[] {navLeft, navUp, navRight, navDown}
local LiveMember = {}
local LiveMemberMT = {__index = LiveMember}

-- Element creation --------------------------------------------------------------------------------

--------------------------------------------------
--- ### papayui.newElementStyle()
--- Creates a new blank papayui element style.
---
--- Optionally, you can supply mixins to set the style.  
--- * A mixin can be a table containing values for the style, such as `{width = 10, height = 10}`.  
--- * A mixin can also be an array of other mixins, such as `{mixin1, mixin2, mixin3}`.  
--- * Lastly, a mixin can be a combination of the two, such as `{width = 10, height = 10, [1] = mixin2, [2] = mixin3}`.
---
--- Example usage:
--- ```
--- local style = papayui.newElementStyle()
--- style.width = 200
--- style.height = 150
--- style.color = "background"
--- style.layout = "singlecolumn"
--- ```
---@param mixins? table
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
        cropContent = false,
        ignoreScale = false
    }

    if mixins then
        papayui.applyMixins(style, mixins)
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
--- You can give it a style and behavior, but if not provided, default blank ones will be generated (no visual style, no behavior)
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
--- Creates a new usable UI, using the given element as the topmost parent element. Can specify an X and Y location for the UI.
---@param rootElement PapayuiElement The root element of the whole UI
---@param x? number The X coordinate of the UI (Default is 0)
---@param y? number The Y coordinate of the UI (Default is 0)
---@return PapayuiUI
function papayui.newUI(rootElement, x, y)
    ---@type PapayuiUI
    local ui = {
        members = {},
        selectedMember = nil,
        actionDown = false,
        cursorXPrevious = 0,
        cursorYPrevious = 0
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
--- ### UI:draw()
--- Draws the UI.
function UI:draw()
    local members = self.members
    local selectedMember = self.selectedMember
    for memberIndex = 1, #members do
        local member = members[memberIndex]
        member:draw(member == selectedMember)
    end
end

local dirEnum = { left = 1, up = 2, right = 3, down = 4 }
--------------------------------------------------
--- ### UI:navigate(direction)
--- Instructs the UI to change the currently selected element
---@param direction "left"|"up"|"right"|"down"
function UI:navigate(direction)
    local selectedMember = self.selectedMember
    if not selectedMember then
        self.selectedMember = self:findDefaultSelectable()
        return
    end

    local dir = dirEnum[direction]
    if not dir then error("Invalid direction: " .. tostring(direction), 2) end

    -- todo: user defined navigation

    local nextSelected = selectedMember:forwardNavigation(selectedMember, dir)
    self.selectedMember = nextSelected or selectedMember
end

--------------------------------------------------
--- ### UI:updateCursor(x, y)
--- Updates the input cursor location
---@param x number
---@param y number
function UI:updateCursor(x, y)
    if x == self.cursorXPrevious and y == self.cursorYPrevious then return end
    self.cursorXPrevious = x
    self.cursorYPrevious = y

    if self.actionDown then
        self.selectedMember = nil
        return
    end

    local foundSelection = false
    for memberIndex = 1, #self.members do
        local member = self.members[memberIndex]
        local memberX, memberY, memberWidth, memberHeight = member:getCroppedBounds()
        if x > memberX and y > memberY and x < memberX + memberWidth and y < memberY + memberHeight then
            if member:isSelectable() then
                self.selectedMember = member
                foundSelection = true
            end
        end
    end
    if not foundSelection then self.selectedMember = nil end
end

--------------------------------------------------
--- ### UI:actionPress()
--- Tells the UI that the action key (typically enter, left click, etc.) has been pressed
function UI:actionPress()
    self.actionDown = true
end

--------------------------------------------------
--- ### UI:actionRelease()
--- Tells the UI that the action key has been released
function UI:actionRelease()
    self.actionDown = false
end

--------------------------------------------------
--- Returns the first selectable member it finds. Used internally.
---@return PapayuiLiveMember?
function UI:findDefaultSelectable()
    local members = self.members
    for memberIndex = 1, #members do
        local member = members[memberIndex]
        local _, _, croppedWidth, croppedHeight = member:getCroppedBounds()

        if member:isSelectable() and croppedWidth > 0 and croppedHeight > 0 then return member end
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
---@return PapayuiElementStyle
function ElementStyle:setPadding(left, top, right, bottom)
    self.padding = generateDirectionalValue(left, top, right, bottom)
    return self
end

--------------------------------------------------
--- ### ElementStyle:setMargin(left, top, right, bottom)
--- Sets the style's margin, following the same rules as in ElementStyle:setPadding().
---@param left? number
---@param top? number
---@param right? number
---@param bottom? number
---@return PapayuiElementStyle
function ElementStyle:setMargin(left, top, right, bottom)
    self.margin = generateDirectionalValue(left, top, right, bottom)
    return self
end

--------------------------------------------------
--- ### ElementStyle:setGap(horizontalGap, verticalGap)
--- Sets the style's gap between the children elements in the layout.
---
--- If only one number is supplied, both the horizontal and vertical gap is set to it. <br>
--- If no number is supplied, the gap is set to 0.
---@param horizontalGap? number
---@param verticalGap? number
---@return PapayuiElementStyle
function ElementStyle:setGap(horizontalGap, verticalGap)
    horizontalGap = horizontalGap or 0
    verticalGap = verticalGap or horizontalGap
    self.gap = {horizontalGap, verticalGap}
    return self
end

--------------------------------------------------
--- ### ElementStyle:setGrow(horizontalGrow, verticalGrow)
--- Sets the style's horizontal and vertical grow.
---
--- If only the first value is supplied, it is applied to both horizontal and vertical grow.
---@param horizontalGrow boolean
---@param verticalGrow? boolean
---@return PapayuiElementStyle
function ElementStyle:setGrow(horizontalGrow, verticalGrow)
    if verticalGrow == nil then verticalGrow = horizontalGrow end
    self.growHorizontal = horizontalGrow
    self.growVertical = verticalGrow
    return self
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
---@return PapayuiElementStyle
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

    return self
end

--------------------------------------------------
--- ### ElementStyle:setScroll(horizontalScroll, verticalScroll)
--- Sets the style's enabled horizontal and vertical scrolling.
---
--- If only the first value is supplied, it is applied to both horizontal and vertical scroll.
---@param horizontalScroll boolean
---@param verticalScroll? boolean
---@return PapayuiElementStyle
function ElementStyle:setScroll(horizontalScroll, verticalScroll)
    if verticalScroll == nil then verticalScroll = horizontalScroll end
    self.scrollHorizontal = horizontalScroll
    self.scrollVertical = verticalScroll
    return self
end

--------------------------------------------------
--- ### ElementStyle:setSize(width, height)
--- Sets the style's size.
---
--- If only one number is supplied, both the horizontal and vertical size is set to it.  
--- If no number is supplied, the size in both axis is set to 0.
---@param width? number
---@param height? number
---@return PapayuiElementStyle
function ElementStyle:setSize(width, height)
    width = width or 0
    height = height or width
    self.width = width
    self.height = height
    return self
end

--------------------------------------------------
--- ### ElementStyle:setColor(color, colorHover)
--- Sets the element's color and/or its hover color.
---
--- If a color is not supplied, it is to nil (no color)
---@param color? string
---@param colorHover? string
---@return PapayuiElementStyle
function ElementStyle:setColor(color, colorHover)
    self.color = color
    self.colorHover = colorHover
    return self
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
---@param isSelected? boolean If the element should be drawn as if it was selected (hovered over)
function Element:draw(x, y, width, height, isSelected)
    local style = self.style
    x = x or 0
    y = y or 0
    width = width or style.width
    height = height or style.height

    local color = papayui.colors[style.color]
    local colorHover = papayui.colors[style.colorHover]
    if isSelected and colorHover then color = colorHover end

    if style.color and not color then
        color = {1, 0, 0} -- "Invalid color" redness
    end

    if color then
        papayui.graphics.drawRectangle(x, y, width, height, color)
    end
end

-- Misc stuff --------------------------------------------------------------------------------------

--- Used internally by the library.  
--- Applies mixins onto the receiving table (copies the mixins' values to it).  
--- * A mixin can be a table containing values, such as `{width = 10, height = 10}`.  
--- * A mixin can also be an array of other mixins, such as `{mixin1, mixin2, mixin3}`.  
--- * Lastly, a mixin can be a combination of the two, such as `{width = 10, height = 10, [1] = mixin2, [2] = mixin3}`.
---@param receivingTable table
---@param mixins table
function papayui.applyMixins(receivingTable, mixins)
    local mixinQueueFirst = {value = mixins, next = nil}
    local mixinQueueLast = mixinQueueFirst
    while mixinQueueFirst do
        local mixin = mixinQueueFirst.value

        for _, queuedMixin in ipairs(mixin) do
            mixinQueueLast.next = {value = queuedMixin, next = nil}
            mixinQueueLast = mixinQueueLast.next
        end

        for key, value in pairs(mixin) do
            if type(key) == "string" then
                receivingTable[key] = value
            end
        end

        mixinQueueFirst = mixinQueueFirst.next
    end
end

-- Abstraction for possible usage outside LÖVE -----------------------------------------------------

-- Can be replaced with functions to perform these actions in non-love2d environments
papayui.graphics = {}

function papayui.graphics.drawRectangle(x, y, width, height, color)
    local cr, cg, cb, ca = love.graphics.getColor()
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x, y, width, height)
    love.graphics.setColor(cr, cg, cb, ca)
end

function papayui.graphics.setCrop(x, y, width, height)
    if not (x or y or width or height) then return love.graphics.setScissor() end
    if width < 0 or height < 0 then return love.graphics.setScissor(0,0,0,0) end

    return love.graphics.setScissor(x, y, width, height)
end

papayui.graphics.getCrop = love.graphics.getScissor

local emptyFunction = function () end
if not love then
    papayui.graphics.drawRectangle = emptyFunction
    papayui.graphics.getCrop = emptyFunction
    papayui.graphics.setCrop = emptyFunction
end

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
    local parentChildren = parentMember.children
    ---@type PapayuiLiveMember[]
    local members = {}
    for elementIndex = 1, #elements do
        local element = elements[elementIndex]

        local member = papayui.newLiveMember(element, 0, 0, parentMember)
        members[elementIndex] = member
        parentChildren[#parentChildren+1] = member
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
    local navPrev = marginStart
    local navNext = marginEnd

    -- Find tallest member and set inline navigation
    local tallestMember = 0
    for memberIndex = 1, #members do
        local member = members[memberIndex]
        tallestMember = math.max(tallestMember, member[sizeCross])
        if memberIndex > 1 then member.nav[navPrev] = members[memberIndex-1] end
        if memberIndex < #members then member.nav[navNext] = members[memberIndex+1] end
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

---@param member PapayuiLiveMember
---@param otherMembers PapayuiLiveMember[]
---@param axisIsVertical boolean
---@return PapayuiLiveMember?
local function findLargestAxisOverlap(member, otherMembers, axisIsVertical)
    local position = axisIsVertical and "y" or "x"
    local size = axisIsVertical and "height" or "width"

    local selfPosition = member[position]
    local selfSize = member[size]

    local maxOverlap = 0
    local maxOverlapMember

    for otherMemberIndex = 1, #otherMembers do
        local otherMember = otherMembers[otherMemberIndex]
        local otherMemberPosition = otherMember[position]
        local otherMemberSize = otherMember[size]

        local a1, a2 = selfPosition, selfPosition + selfSize
        local b1, b2 = otherMemberPosition, otherMemberPosition + otherMemberSize

        local overlapStart = math.max(a1, b1)
        local overlapEnd   = math.min(a2, b2)

        local overlap = overlapEnd - overlapStart
        if overlap > maxOverlap then
            maxOverlap = overlap
            maxOverlapMember = otherMember
        end
    end

    return maxOverlapMember
end

---@param lines PapayuiLiveMember[][]
---@param mainAxisIsVertical boolean
local function assignCrossAxisLineNavigation(lines, mainAxisIsVertical)
    local navPrev = mainAxisIsVertical and 1 or 2
    local navNext = mainAxisIsVertical and 3 or 4

    for lineIndex = 1, #lines do
        local line = lines[lineIndex]
        local prevLine = lines[lineIndex-1]
        local nextLine = lines[lineIndex+1]

        for lineMemberIndex = 1, #line do
            local member = line[lineMemberIndex]
            if prevLine then
                local prevMember = findLargestAxisOverlap(member, prevLine, mainAxisIsVertical)
                if prevMember then member.nav[navPrev] = prevMember end
            end
            if nextLine then
                local nextMember = findLargestAxisOverlap(member, nextLine, mainAxisIsVertical)
                if nextMember then member.nav[navNext] = nextMember end
            end
        end
    end
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

        -- Align the line on the main axis, relative to its assigned position
        local lineX = flipAxis and lineOffset or 0
        local lineY = flipAxis and 0 or lineOffset
        local alignX = flipAxis and -1 or alignHorizontal
        local alignY = flipAxis and alignVertical or -1

        local lineWidth, lineHeight = alignMembers(line, lineX, lineY, usableSpaceWidth, usableSpaceHeight, alignX, alignY)
        local lineSizeCross = flipAxis and lineWidth or lineHeight
        lineOffset = lineOffset + lineSizeCross + gapCross

        -- Insert line into output members
        for memberIndex = 1, #line do
            outMembers[#outMembers+1] = line[memberIndex]
        end
    end

    assignCrossAxisLineNavigation(lines, flipAxis)
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
        children = {},
        x = x,
        y = y,
        width = style.width * scale,
        height = style.height * scale,
        scrollX = 0,
        scrollY = 0,
        parent = parent,
        nav = {}
    }

    return setmetatable(member, LiveMemberMT)
end

---@param isSelected? boolean
function LiveMember:draw(isSelected)
    local cropX, cropY, cropWidth, cropHeight = papayui.graphics.getCrop()
    if self.parent then papayui.graphics.setCrop(self.parent:getCropArea()) end

    local x, y, width, height = self:getBounds()
    self.element:draw(x, y, width, height, isSelected)

    papayui.graphics.setCrop(cropX, cropY, cropWidth, cropHeight)
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

---@return number x
---@return number y
---@return number width
---@return number height
function LiveMember:getBounds()
    local xOffset, yOffset = 0, 0
    if self.parent then xOffset, yOffset = self.parent:getScroll() end

    local x, y = self.x + xOffset, self.y + yOffset
    local width, height = self.width, self.height
    return x, y, width, height
end

---@param overlapX1? number
---@param overlapY1? number
---@param overlapX2? number
---@param overlapY2? number
---@return number? cropX
---@return number? cropY
---@return number? cropWidth
---@return number? cropHeight
function LiveMember:getCropArea(overlapX1, overlapY1, overlapX2, overlapY2)
    local style = self.element.style
    if not style.cropContent then
        if self.parent then
            return self.parent:getCropArea(overlapX1, overlapY1, overlapX2, overlapY2)
        end
        if not (overlapX1 and overlapY1 and overlapX2 and overlapY2) then return end
        return overlapX1, overlapY1, overlapX2 - overlapX1, overlapY2 - overlapY1
    end

    local x, y, width, height = self:getBounds()
    local contentX1 = x + style.padding[1]
    local contentY1 = y + style.padding[2]
    local contentX2 = contentX1 + width - style.padding[1] - style.padding[3]
    local contentY2 = contentY1 + height - style.padding[2] - style.padding[4]

    overlapX1 = overlapX1 or contentX1
    overlapY1 = overlapY1 or contentY1
    overlapX2 = overlapX2 or contentX2
    overlapY2 = overlapY2 or contentY2

    contentX1 = math.max(contentX1, overlapX1)
    contentY1 = math.max(contentY1, overlapY1)
    contentX2 = math.min(contentX2, overlapX2)
    contentY2 = math.min(contentY2, overlapY2)

    if self.parent then return self.parent:getCropArea(contentX1, contentY1, contentX2, contentY2) end
    return contentX1, contentY1, contentX2 - contentX1, contentY2 - contentY1
end

---@return number
---@return number
---@return number
---@return number
function LiveMember:getCroppedBounds()
    local x, y, width, height = self:getBounds()
    local parent = self.parent
    if not parent then return x, y, width, height end

    local cropX, cropY, cropWidth, cropHeight = parent:getCropArea(x, y, x + width, y + height)
    if cropX and cropY and cropWidth and cropHeight then
        return cropX, cropY, cropWidth, cropHeight
    end

    -- Technically it can't ever get here but it makes the language server happy to do it this way
    return x, y, width, height
end

function LiveMember:isSelectable()
    if self.element.style.colorHover then return true end
    return false
end

--- Tries to select self or any child. If provided, will find the selection closest to the source member.
---@param source? PapayuiLiveMember
---@return PapayuiLiveMember?
function LiveMember:selectAny(source)
    local sourceX, sourceY
    local closestMemberDistance = math.huge
    local closestMember
    if source then
        local x, y, w, h = source:getBounds()
        sourceX = x + w / 2
        sourceY = y + h / 2
    end

    local stack = {self}
    while #stack > 0 do
        local member = stack[#stack]
        stack[#stack] = nil

        local croppedX, croppedY, croppedWidth, croppedHeight = member:getCroppedBounds()
        local canSelect = member:isSelectable() and croppedWidth > 0 and croppedHeight > 0
        if canSelect and not source then return member end

        if canSelect and sourceX and sourceY then
            local memberX = croppedX + croppedWidth / 2
            local memberY = croppedY + croppedHeight / 2
            local offsetX = memberX - sourceX
            local offsetY = memberY - sourceY
            local distanceSquared = offsetX * offsetX + offsetY * offsetY
            if distanceSquared < closestMemberDistance then
                closestMemberDistance = distanceSquared
                closestMember = member
            end
        end

        for childIndex = #member.children, 1, -1  do
            local child = member.children[childIndex]
            stack[#stack+1] = child
        end
    end

    if closestMember then return closestMember end
    return nil
end

--- Passes the navigation request forward.  
--- Call `select` on element in the given direction (if known) or forward navigation to parent (if there is one)
---@param source PapayuiLiveMember
---@param direction 1|2|3|4
---@return PapayuiLiveMember?
function LiveMember:forwardNavigation(source, direction)
    if self.nav[direction] then return self.nav[direction]:select(source, direction) end
    if self.parent then return self.parent:forwardNavigation(source, direction) end
end

--- Return self or a child if a selectable element is present, or simply forward navigation if not
---@param source PapayuiLiveMember
---@param direction 1|2|3|4
---@return PapayuiLiveMember?
function LiveMember:select(source, direction)
    if self:isSelectable() then return self end

    local selectedChild = self:selectAny(source)
    if selectedChild then return selectedChild end

    return self:forwardNavigation(source, direction)
end

-- Fin ---------------------------------------------------------------------------------------------

return papayui