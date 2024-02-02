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

-- Class definitions -------------------------------------------------------------------------------

---@alias PapayuiElementLayout
---| '"none"' # The elements are not displayed
---| '"singlerow"' # A single horizontal row of elements
---| '"singlecolumn"' # A single vertical column of elements

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
---@field padding number[] The padding of the element, in the format {left, top, right, bottom}
---@field margin number[] The margin of the element, in the format {left, top, right, bottom}
---@field color? string The background color of this element, from the ui.colors table
---@field colorHover? string The background color of this element when it's hovered over
---@field layout PapayuiElementLayout The way this element's children will be laid out
---@field alignHorizontal PapayuiAlignment The horizontal alignment of the element's children
---@field alignVertical PapayuiAlignment The vertical alignment of the element's children
---@field alignInside PapayuiAlignment The alignment of all the individual child elements within a line
---@field gap number[] The gap between its child elements in the layout, in the format {horizontal, vertical}
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
---@field x number The x position of the element
---@field y number The y position of the element
---@field width number The actual width of the element
---@field height number The actual height of the element

-- Element creation --------------------------------------------------------------------------------

--------------------------------------------------
--- ### papayui.newElementStyle()
--- Creates a new blank papayui element style.
---
--- Example usage:
--- ```
--- local style = papayui.newElementStyle()
--- style.width = 200
--- style.height = 150
--- style.color = "background"
--- style.layout = "singlecolumn"
--- ```
---@return PapayuiElementStyle
function papayui.newElementStyle()
    ---@type PapayuiElementStyle
    local style = {
        width = 0,
        height = 0,
        padding = {0, 0, 0, 0},
        margin = {0, 0, 0, 0},
        layout = "singlerow",
        alignHorizontal = "start",
        alignVertical = "start",
        alignInside = "start",
        gap = {0, 0}
    }
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
---@param rootElement PapayuiElement
---@param x? number The X coordinate of the UI (Default is 0)
---@param y? number The Y coordinate of the UI (Default is 0)
---@return PapayuiUI
function papayui.newUI(rootElement, x, y)
    ---@type PapayuiUI
    local ui = {
        members = {}
    }

    ---@type PapayuiLiveMember
    local rootMember = {
        element = rootElement,
        x = x or 0,
        y = y or 0,
        width = rootElement.style.width,
        height = rootElement.style.height
    }

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
        member.element:draw(member.x, member.y, member.width, member.height)
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

-- Element methods ---------------------------------------------------------------------------------

---@param x? number The X coordinate to draw at (Default is 0)
---@param y? number The Y coordinate to daw at (Default is 0)
---@param width? number The width to draw the element as (Default is element's width)
---@param height? number The height to draw the element as (Default is the element's height)
function Element:draw(x, y, width, height)
    local style = self.style
    x = x or 0
    y = y or 0
    width = width or style.width
    height = height or style.height

    if style.color then
        papayui.drawRectangle(x, y, width, height, papayui.colors[style.color])
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

---@param originX number
---@param originY number
---@param elements PapayuiElement[]
---@param gap number
---@param isVertical boolean
---@return PapayuiLiveMember[]
---@return number lineSizeMain
---@return number lineSizeCross
local function layElementsInLine(originX, originY, elements, gap, isVertical)
    local outMembers = {}

    local marginStart = isVertical and 2 or 1
    local marginEnd = isVertical and 4 or 3
    local sizeMain = isVertical and "height" or "width"
    local sizeCross = isVertical and "width" or "height"

    local nextPos = 0
    local tallestElement = 0
    for elementIndex = 1, #elements do
        local element = elements[elementIndex]
        local elementStyle = element.style

        nextPos = nextPos + elementStyle.margin[marginStart]
        local elementX = originX + (isVertical and 0 or nextPos)
        local elementY = originY + (isVertical and nextPos or 0)
        ---@type PapayuiLiveMember
        local member = {
            element = element,
            x = elementX,
            y = elementY,
            width = elementStyle.width,
            height = elementStyle.height
        }
        nextPos = nextPos + elementStyle[sizeMain] + elementStyle.margin[marginEnd] + gap

        tallestElement = math.max(tallestElement, elementStyle[sizeCross])

        outMembers[#outMembers+1] = member
    end

    local lineSizeMain = nextPos - gap
    local lineSizeCross = tallestElement

    return outMembers, lineSizeMain, lineSizeCross
end

---@param lineMembers PapayuiLiveMember[]
---@param alignVertical number
---@param alignHorizontal number
---@param alignInside number
---@param usableSpaceWidth number
---@param usableSpaceHeight number
---@param usedSpaceWidth number
---@param usedSpaceHeight number
---@param lineIsVertical boolean
local function alignLine(lineMembers, alignHorizontal, alignVertical, alignInside, usableSpaceWidth, usableSpaceHeight, usedSpaceWidth, usedSpaceHeight, lineIsVertical)
    local alignMain = lineIsVertical and alignVertical or alignHorizontal
    local alignCross = lineIsVertical and alignHorizontal or alignVertical
    local usableSpaceMain = lineIsVertical and usableSpaceHeight or usableSpaceWidth
    local usableSpaceCross = lineIsVertical and usableSpaceWidth or usableSpaceHeight
    local usedSpaceMain = lineIsVertical and usedSpaceHeight or usedSpaceWidth
    local usedSpaceCross = lineIsVertical and usedSpaceWidth or usedSpaceHeight

    local mainNudge = getNudgeValue(usableSpaceMain, usedSpaceMain, alignMain)
    local crossNudge = getNudgeValue(usableSpaceCross, usedSpaceCross, alignCross)
    local sizeCross = lineIsVertical and "width" or "height"
    for memberIndex = 1, #lineMembers do
        local member = lineMembers[memberIndex]

        -- Alignment inside line
        local insideNudge = getNudgeValue(usedSpaceCross, member[sizeCross], alignInside)
        local crossNudgeFull = crossNudge + insideNudge

        local xNudge = lineIsVertical and crossNudgeFull or mainNudge
        local yNudge = lineIsVertical and mainNudge or crossNudgeFull

        member.x = member.x + xNudge
        member.y = member.y + yNudge
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

    local outMembers, lineSizeMain, lineSizeCross = layElementsInLine(originX, originY, children, gap, flipAxis)
    local usedSpaceWidth = flipAxis and lineSizeCross or lineSizeMain
    local usedSpaceHeight = flipAxis and lineSizeMain or lineSizeCross
    alignLine(outMembers, alignHorizontal, alignVertical, alignInside, usableSpaceWidth, usableSpaceHeight, usedSpaceWidth, usedSpaceHeight, flipAxis)

    return outMembers
end

function papayui.layouts.singlecolumn(parentMember)
    return papayui.layouts.singlerow(parentMember, true)
    
end

return papayui