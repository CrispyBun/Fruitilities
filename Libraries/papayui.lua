----------------------------------------------------------------------------------------------------
-- A multipurpose UI library
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

local papayui = {}

---@diagnostic disable-next-line: deprecated
local unpack = unpack or table.unpack

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

-- Color used if the selected color doesn't exist
papayui.fallbackColor = {1, 0, 0}

-- Change and then refresh any UIs
papayui.scale = 1

-- Whether or not elements draw a basic rectangle on their position by default
papayui.drawElementRectangles = true

papayui.scrollSpeed = 100             -- The maximum scrolling speed
papayui.scrollSpeedStep = 5           -- How much scroll speed is added on each scroll input
papayui.scrollFriction = 0.2          -- How fast the scrolling slows down
papayui.buttonScrollOvershoot = 10    -- How many pixels to try to (roughly) overshoot when scrolling using button input
papayui.touchScrollingEnabled = true  -- Whether or not holding down the action key and dragging the cursor can scroll

-- Definitions -------------------------------------------------------------------------------------

---@diagnostic disable-next-line: duplicate-doc-alias
---@alias Papayui.Color [number, number, number]

---@diagnostic disable-next-line: duplicate-doc-alias
---@alias Papayui.ElementLayout
---| '"none"' # The elements are not displayed
---| '"singlerow"' # A single horizontal row of elements
---| '"singlecolumn"' # A single vertical column of elements
---| '"rows"' # Horizontal rows of elements
---| '"columns"' # Vertical columns of elements
---| '"stack"' # All children are put on top of each other into the parent's inner area
---| '"positionlist"' # The children are put on the X and Y positions described in the style.positionList table (positions are just relative to each other, parent and alignment will then determine actual position)

---@alias Papayui.Alignment
---| '"start"' # Aligns to the left or top
---| '"center"' # Aligns to the center
---| '"end"' # Aligns to the right or bottom
---| '"left"' # Same as 'start'
---| '"top"' # Same as 'start'
---| '"right"' # Same as 'end'
---| '"bottom"' # Same as 'end'
---| '"middle"' # Same as 'center'
---| '"spread"' # Evenly spreads out the elements (if not possible, is the same as 'center')
---| '"spacebetween"' # Same as 'spread'

---@diagnostic disable-next-line: duplicate-doc-alias
---@alias Papayui.EventType
---| '"action"' # The action key has been pressed on an element
---| '"hover"' # The element has been hovered over
---| '"unhover"' # The element stopped being hovered over
---| '"update"' # The element has been updated
---| '"hoveredUpdate"' # The element is hovered over and has been updated
---| '"refresh"' # The element has been refreshed (its UI has either just been created or refreshed)
---| '"scrollerHitEnd"' # The element's scroller has reached its limit
---| '"scrollerVelocity"' # The element's scrolling velocity in either axis is not zero and has been updated
---| '"draw"' # The element has been drawn (also used in the actual draw functions)
---| '"navigate"' # Button navigation was triggered on the element (also used in the Element.nav selecting function)

---@alias Papayui.UIEnabledState
---| '"enabled"' # The UI is enabled
---| '"noinput"' # The UI will be drawn, but input is disabled
---| '"disabled"' # The UI will not be drawn and input is disabled
---| '"asleep"' # The UI is not drawn, input is disabled and the UI will not be updated

---@class Papayui.ElementStyle
---@field width number The width of the element
---@field height number The height of the element
---@field growHorizontal boolean Whether the element should grow horizontally to take up full parent space
---@field growVertical boolean Whether the element should grow vertically to take up full parent space
---@field padding number[] The padding of the element, in the format {left, top, right, bottom}
---@field margin number[] The margin of the element, in the format {left, top, right, bottom}
---@field color? string The background color of this element, from the ui.colors table
---@field colorHover? string The background color of this element when it's hovered over
---@field drawRectangle? boolean Whether or not the element should draw a rectangle of its color at its position. If nil, defaults to papayui.drawElementRectangles.
---@field draw? fun(event: Papayui.DrawEvent) Function that draws the element
---@field drawInner? fun(event: Papayui.DrawEvent) Similar to the draw function, but is drawn after it and receives the element's inner padded area as the size
---@field layout Papayui.ElementLayout The way this element's children will be laid out
---@field alignHorizontal Papayui.Alignment The horizontal alignment of the element's children
---@field alignVertical Papayui.Alignment The vertical alignment of the element's children
---@field alignInside Papayui.Alignment The alignment of all the individual child elements relative to their assigned positions (e.g. cross axis alignment within a line)
---@field alignInsideSecondary Papayui.Alignment The other axis of alignInside for the few layouts where alignInside exists for both axes
---@field scrollHorizontal boolean Whether or not any horizontal overflow in the element's children should scroll
---@field scrollVertical boolean Whether or not any vertical overflow in the element's children should scroll
---@field scrollSpeedMultiplier number Speed multiplier applied to scroll input on this element
---@field offsetX number The element's horizontal offset from its assigned position
---@field offsetY number The element's vertical offset from its assigned position
---@field gap number[] The gap between its child elements in the layout, in the format {horizontal, vertical}
---@field cropContent boolean Whether or not overflow in the element's content should be cropped
---@field maxLineElements (number|nil)|(number|nil)[] Sets a limit to the amount of elements that can be present in a given row/column. If set to a number, all lines get this limit. If set to an array of numbers, each array index corresponds to a given line index. Nil for unlimited.
---@field ignoreScale boolean Determines if papayui.scale has an effect on the size of this element (useful to enable for root elements which fill screen space)
---@field positionList? {[1]: number, [2]: number}[] The list of child positions for the positionlist layout
---@field preLayout? fun(member: Papayui.LiveMember) Function that can modify some properties of the instanced element (member) when it's about to be laid out in a UI. Useful for resizing the element based on some variable (such as text boxes).
---@field preChildren? fun(member: Papayui.LiveMember): Papayui.ElementLayout? Function that can modify some properties of the instanced element (member) right before its children are laid out. Can optionally return an ElementLayout to override the one set in the style. Useful for responsive layouts.
---@field postChildren? fun(member: Papayui.LiveMember) Function that can modify some properties of the instanced element (member) right after its children are laid out. Can be useful for repositioning some of the children after the layout is finished.
local ElementStyle = {}
local ElementStyleMT = {__index = ElementStyle}

---@class Papayui.ElementBehavior
---@field isSelectable? boolean Optional override for the default logic determining if the element is selectable (does not override buttonSelectable or cursorSelectable being false though)
---@field buttonSelectable boolean Whether or not it is possible to navigate to this element using button input (it is not recommended to disable this, it might make certain selection situations odd)
---@field cursorSelectable boolean Whether or not it is possible to navigate to this element using cursor input
---@field action? fun(event: Papayui.Event) Callback for when this element is selected (action key is pressed on it)
---@field callbacks table<Papayui.EventType, fun(event: Papayui.Event)> Listeners for events on this element
local ElementBehavior = {}
local ElementBehaviorMT = {__index = ElementBehavior}

---@class Papayui.Element
---@field style Papayui.ElementStyle The style this element uses
---@field behavior Papayui.ElementBehavior The behavior this element uses
---@field children Papayui.Element[] The children of this element (can be empty)
---@field nav Papayui.Navigation Optionally specified navigation for the element. Each direction (left, up, right, down) can be set. If a direction is left as nil, auto navigation is used.
---@field importance number When finding a default element to select, the element with the highest importance gets picked
---@field data table Any arbitrary data you want to add to this element, mostly to be used in callbacks
local Element = {}
local ElementMT = {__index = Element}

--- A template to generate elements from. Instancing an empty template is the same thing as creating a new blank element.
---@class Papayui.Template
---@field style? Papayui.ElementStyle The style for elements made from this template
---@field behavior? Papayui.ElementBehavior The behavior for elements made from this template
---@field data? table The arbitrary data to be put into elements made from this template
---@field init? fun(element: Papayui.Element, ...: unknown) Constructor for when the template is instanced (receives the new element and constructor params)
local Template = {}
local TemplateMT = {__index = Template}

---@class Papayui.UI
---@field members Papayui.LiveMember[] All the elements in the UI, in the drawn order
---@field selectedMember? Papayui.LiveMember The member that is currently selected
---@field lastSelection? Papayui.LiveMember The last element that was selected
---@field actionDown boolean If the action key is currently down (set automatically by the appropriate methods)
---@field cursorX number The cursor X coordinate
---@field cursorY number The cursor Y coordinate
---@field touchDraggedMember? Papayui.LiveMember The member that is currently being being scrolled using touch input
---@field enabledState Papayui.UIEnabledState Whether the UI responds to input or is even drawn
---@field data table Any arbitrary data you want to add to this ui
local UI = {}
local UIMT = {__index = UI}

---@class Papayui.Event
---@field type Papayui.EventType The type of event triggered
---@field targetMember Papayui.LiveMember The member that the event was triggered for
---@field targetElement Papayui.Element The element that the event was triggered for
---@field data table The arbitrary data that was put into the element
---@field ui Papayui.UI The UI the event was triggered in

---@class Papayui.DrawEvent : Papayui.Event
---@field x number The X position of the element
---@field y number The Y position of the element
---@field width number The width of the element
---@field height number The height of the element
---@field color? Papayui.Color The color of the element
---@field isSelected boolean Whether or not the element is hovered over

--- Can navigate to either a specific Papayui.Element,
--- or a function which is checked against all elements, receiving events for both the checked element and the element the navigation originates from.
--- The element for which the function returns true is selected.
---@class Papayui.Navigation
---@field left? Papayui.Element|fun(checkedElementEvent: Papayui.Event, originEvent: Papayui.Event): boolean
---@field up? Papayui.Element|fun(checkedElementEvent: Papayui.Event, originEvent: Papayui.Event): boolean
---@field right? Papayui.Element|fun(checkedElementEvent: Papayui.Event, originEvent: Papayui.Event): boolean
---@field down? Papayui.Element|fun(checkedElementEvent: Papayui.Event, originEvent: Papayui.Event): boolean

--- The instanced element in an actual UI, with a state.
---@class Papayui.LiveMember
---@field element Papayui.Element The element this is an instance of
---@field parent? Papayui.LiveMember The parent of this member
---@field children Papayui.LiveMember[] The children of this member
---@field x number The x position of the element
---@field y number The y position of the element
---@field width number The actual width of the element
---@field height number The actual height of the element
---@field scrollX number The amount of scroll in the X direction
---@field scrollY number The amount of scroll in the Y direction
---@field scrollVelocityX number The scroll velocity in the X direction
---@field scrollVelocityY number The scroll velocity in the Y direction
---@field offsetX number The offset in the X direction
---@field offsetY number The offset in the Y direction
---@field nav (Papayui.LiveMember?)[] {navLeft, navUp, navRight, navDown}
local LiveMember = {}
local LiveMemberMT = {__index = LiveMember}

-- Global callbacks --------------------------------------------------------------------------------

--- Global callbacks triggered for events from any active UI  
--- Set these to any callback functions. There are no global callbacks by default.
---@type table<Papayui.EventType, fun(event: Papayui.Event)>
papayui.callbacks = {}

-- -- Example callback
-- function papayui.callbacks.action(event)
--     print("An element was selected: ", event.targetElement)
-- end

--- Optional global draw element function, just like ElementStyle.draw but for all elements
---@type fun(event: Papayui.DrawEvent)?
papayui.drawElement = nil

-- Utility -----------------------------------------------------------------------------------------

--------------------------------------------------
--- ### papayui.newFunctionStack(...)
--- Returns a function that calls all the given functions in order.  
---
--- Useful for some callbacks and drawing functions where you need to combine the functionality of multiple functions,
--- but the callback can only be set to one function.
---@param ... function
---@return function
function papayui.newFunctionStack(...)
    local functions = {...}
    return function(...)
        for functionIndex = 1, #functions do
            functions[functionIndex](...)
        end
    end
end
papayui.newFuncstack = papayui.newFunctionStack

-- Element creation --------------------------------------------------------------------------------

--------------------------------------------------
--- ### papayui.newElementStyle()
--- Creates a new papayui element style.
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
---@return Papayui.ElementStyle
function papayui.newElementStyle(mixins)
    ---@type Papayui.ElementStyle
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
        alignInsideSecondary = "center",
        scrollHorizontal = false,
        scrollVertical = false,
        scrollSpeedMultiplier = 1,
        offsetX = 0,
        offsetY = 0,
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
--- Creates a new papayui element behavior.
---
--- Optionally, you can supply mixins, which work the same way as in newElementStyle.  
---
--- Example usage:
--- ```
--- local behavior = papayui.newElementBehavior()
--- behavior.cursorSelectable = false
--- function behavior.action(event)
---     print("The element was pressed")
--- end
--- ```
---@return Papayui.ElementBehavior
function papayui.newElementBehavior(mixins)
    ---@type Papayui.ElementBehavior
    local behavior = {
        isSelectable = nil,
        buttonSelectable = true,
        cursorSelectable = true,
        callbacks = {}
    }

    if mixins then
        papayui.applyMixins(behavior, mixins)
    end

    return setmetatable(behavior, ElementBehaviorMT)
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
---@param style? Papayui.ElementStyle
---@param behavior? Papayui.ElementBehavior
---@return Papayui.Element
function papayui.newElement(style, behavior)
    style = style or papayui.newElementStyle()
    behavior = behavior or papayui.newElementBehavior()

    ---@type Papayui.Element
    local element = {
        style = style,
        behavior = behavior,
        children = {},
        nav = {left = nil, up = nil, right = nil, down = nil},
        importance = 0,
        data = {}
    }

    return setmetatable(element, ElementMT)
end

--------------------------------------------------
--- ### papayui.newTemplate(style, behavior)
--- Creates a new element template.
---@param style? Papayui.ElementStyle
---@param behavior? Papayui.ElementBehavior
---@param data? table
---@param init? fun(element: Papayui.Element, ...: unknown)
---@return Papayui.Template
function papayui.newTemplate(style, behavior, data, init)
    ---@type Papayui.Template
    local template = {
        style = style,
        behavior = behavior,
        data = data,
        init = init
    }
    return setmetatable(template, TemplateMT)
end

--------------------------------------------------
--- ### papayui.newUI(rootElement)
--- Creates a new usable UI, using the given element as the topmost parent element. Can specify an X and Y location for the UI.
---@param rootElement Papayui.Element The root element of the whole UI
---@param x? number The X coordinate of the UI (Default is 0)
---@param y? number The Y coordinate of the UI (Default is 0)
---@return Papayui.UI
function papayui.newUI(rootElement, x, y)
    ---@type Papayui.UI
    local ui = {
        members = {},
        selectedMember = nil,
        lastSelection = nil,
        actionDown = false,
        cursorX = math.huge,
        cursorY = math.huge,
        touchDraggedMember = nil,
        enabledState = "enabled",
        data = {}
    }
    setmetatable(ui, UIMT)

    local rootMember = papayui.newLiveMember(rootElement, x, y)
    ui.members[1] = rootMember
    ui:refresh()

    return ui
end

-- UI methods --------------------------------------------------------------------------------------

--------------------------------------------------
--- ### UI:setDataField(key, value)
--- Sets a field in the UI's data table
---@param key string
---@param value any
---@return Papayui.UI self
function UI:setDataField(key, value)
    self.data[key] = value
    return self
end

--------------------------------------------------
--- ### UI:draw()
--- Draws the UI.
function UI:draw()
    if self.enabledState == "disabled" or self.enabledState == "asleep" then return end

    local members = self.members
    local selectedMember = self.selectedMember
    for memberIndex = 1, #members do
        local member = members[memberIndex]

        ---@type Papayui.Event
        local event = {
            type = "draw",
            targetMember = member,
            targetElement = member.element,
            data = member.element.data,
            ui = self,
        }

        member:draw(member == selectedMember, event)
    end
end

local defaultDeltaTime = 1/60
--------------------------------------------------
--- ### UI:update(dt)
--- Updates the dynamically changing elements of the UI, such as scrolling.  
--- If the UI doesn't contain any such elements, calling update is not necessary.  
---
--- If deltatime isn't supplied, assumes a constant 60 updates per second.
---@param dt? number
function UI:update(dt)
    if self.enabledState == "asleep" then return end

    dt = dt or defaultDeltaTime
    local dtNormalised = dt / defaultDeltaTime

    local members = self.members
    for memberIndex = 1, #members do
        local member = members[memberIndex]
        local style = member.element.style

        if style.scrollHorizontal or style.scrollVertical then

            local scrollX = member.scrollX
            local scrollY = member.scrollY
            local scrollVelocityX = member.scrollVelocityX
            local scrollVelocityY = member.scrollVelocityY

            -- While touch dragging, velocity is ignored
            if self.touchDraggedMember then
                member.scrollX = scrollX + scrollVelocityX
                member.scrollY = scrollY + scrollVelocityY
                member.scrollVelocityX = 0
                member.scrollVelocityY = 0

                scrollX, scrollY = member.scrollX, member.scrollY
                scrollVelocityX, scrollVelocityY = 0, 0
            end

            member.scrollX = scrollX + scrollVelocityX * dtNormalised
            member.scrollY = scrollY + scrollVelocityY * dtNormalised
            member.scrollVelocityX = scrollVelocityX - (scrollVelocityX * papayui.scrollFriction) * dtNormalised
            member.scrollVelocityY = scrollVelocityY - (scrollVelocityY * papayui.scrollFriction) * dtNormalised

            -- Make slow portions of scrolling look less jittery
            if math.abs(member.scrollX - scrollX) < 0.25 * dtNormalised then member.scrollVelocityX = 0 end
            if math.abs(member.scrollY - scrollY) < 0.25 * dtNormalised then member.scrollVelocityY = 0 end

            -- Cap scroll to limits
            local hitLimit = false
            local minScrollX, minScrollY, maxScrollX, maxScrollY = member:getScrollLimits()
            if member.scrollY > maxScrollY then
                member.scrollVelocityY = 0
                member.scrollY = maxScrollY
                hitLimit = true
            end
            if member.scrollY < minScrollY then
                member.scrollVelocityY = 0
                member.scrollY = minScrollY
                hitLimit = true
            end
            if member.scrollX > maxScrollX then
                member.scrollVelocityX = 0
                member.scrollX = maxScrollX
                hitLimit = true
            end
            if member.scrollX < minScrollX then
                member.scrollVelocityX = 0
                member.scrollX = minScrollX
                hitLimit = true
            end
            if hitLimit then
                self:triggerEvent("scrollerHitEnd", member)
            end

            if member.scrollVelocityX ~= 0 or member.scrollVelocityY ~= 0 then
                self:triggerEvent("scrollerVelocity", member)
            end
        end

        self:triggerEvent("update", member)
    end

    if self.selectedMember then self:triggerEvent("hoveredUpdate", self.selectedMember) end
end

--------------------------------------------------
--- ### UI:refresh()
--- Redraws the entire UI.  
---
--- If any changes were made that affect positioning (such as papayui.scale or changing the elements' sizes or layouts), this method needs to be called to apply those changes to the UI.  
--- Scrolling and offsets do not need to have refresh called.
---
--- The function only regenerates members when it needs to. If all of the UI's children stay the exact same, the actual member instances won't be overwritten by new ones, therefore remembering things like scrolling.
function UI:refresh()
    local rootMember = self.members[1]
    if not rootMember then return end

    rootMember:resetBounds(rootMember.x, rootMember.y)
    self.members = {}

    local memberQueueFirst = {value = rootMember, next = nil}
    local memberQueueLast = memberQueueFirst
    while memberQueueFirst do
        local member = memberQueueFirst.value
        local style = member.element.style

        local layoutOverride = style.preChildren and style.preChildren(member)
        local layout = layoutOverride or style.layout

        if layout and papayui.layouts[layout] then
            local addedMembers = papayui.layouts[layout](member)

            for addedIndex = 1, #addedMembers do
                local addedMember = addedMembers[addedIndex]
                local nextQueueItem = {value = addedMember, next = nil}
                memberQueueLast.next = nextQueueItem
                memberQueueLast = nextQueueItem
            end
        else
            -- Clear children that may be left over from a different state of the UI
            -- (if the user restructured the UI and then called refresh)
            if #member.children > 0 then member.children = {} end
        end

        if style.postChildren then style.postChildren(member) end

        self.members[#self.members+1] = member
        memberQueueFirst = memberQueueFirst.next
    end

    local selectedFound = false
    local lastSelectionFound = false
    local touchDraggedFound = false
    for memberIndex = 1, #self.members do
        if selectedFound and lastSelectionFound and touchDraggedFound then break end

        local member = self.members[memberIndex]
        selectedFound = selectedFound or member == self.selectedMember
        lastSelectionFound = lastSelectionFound or member == self.lastSelection
        touchDraggedFound = touchDraggedFound or member == self.touchDraggedMember
    end
    if not selectedFound then self.selectedMember = nil end
    if not lastSelectionFound then self.lastSelection = nil end
    if not touchDraggedFound then self.touchDraggedMember = nil end

    local members = self.members
    for memberIndex = 1, #members do
        local member = members[memberIndex]
        self:triggerEvent("refresh", member)
    end
end

local dirEnum = { left = 1, up = 2, right = 3, down = 4 }
--------------------------------------------------
--- ### UI:navigate(direction)
--- Instructs the UI to change the currently selected element
---@param direction "left"|"up"|"right"|"down"
function UI:navigate(direction)
    if self.enabledState ~= "enabled" then return end

    local selectedMember = self.selectedMember
    if not selectedMember then
        self:select(self:findDefaultSelectable(true), true)
        return
    end

    local dir = dirEnum[direction]
    if not dir then error("Invalid direction: " .. tostring(direction), 2) end

    local definedNav = selectedMember.element.nav[direction]

    ---@type Papayui.LiveMember?
    local nextSelected
    if definedNav then
        nextSelected = self:findMemberAsNavigation(definedNav, selectedMember)
    else
        nextSelected = selectedMember:forwardNavigation(selectedMember, dir)
    end

    -- Skip past elements we can't select (even if they were selected using definedNav)
    while nextSelected and (not nextSelected:isSelectable() or not nextSelected.element.behavior.buttonSelectable) do
        nextSelected = nextSelected:forwardNavigation(selectedMember, dir)
    end

    self:triggerEvent("navigate", selectedMember)
    self:select(nextSelected or selectedMember, true)
end

--------------------------------------------------
--- ### UI:updateCursor(x, y)
--- Updates the input cursor location
---@param x number
---@param y number
function UI:updateCursor(x, y)
    if self.enabledState ~= "enabled" then return end

    if x == self.cursorX and y == self.cursorY then return end
    local xPrevious = self.cursorX
    local yPrevious = self.cursorY
    self.cursorX = x
    self.cursorY = y

    if self.actionDown then
        self:select()

        if papayui.touchScrollingEnabled then
            local hoveredMember = self.touchDraggedMember or self:findMemberAtCoordinate(x, y)
            if hoveredMember then hoveredMember:scrollRecursively(x - xPrevious, y - yPrevious, false, true, 1) end
            self.touchDraggedMember = hoveredMember
        end

        return
    end
    -- Turn off touch dragging here just in case ui:actionRelease() isn't used for whatever reason
    self.touchDraggedMember = nil

    local foundSelection = false
    for memberIndex = 1, #self.members do
        local member = self.members[memberIndex]
        local memberX, memberY, memberWidth, memberHeight = member:getCroppedBounds()
        if x > memberX and y > memberY and x < memberX + memberWidth and y < memberY + memberHeight then
            if member:isSelectable() and member.element.behavior.cursorSelectable then
                self:select(member)
                foundSelection = true
            end
        end
    end
    if not foundSelection then self:select() end
end

--------------------------------------------------
--- ### UI:actionPress()
--- Tells the UI that the action key (typically enter, left click, etc.) has been pressed
function UI:actionPress()
    if self.enabledState ~= "enabled" then return end
    self.actionDown = true
end

--------------------------------------------------
--- ### UI:actionRelease()
--- Tells the UI that the action key has been released
function UI:actionRelease()
    if self.enabledState ~= "enabled" then return end

    -- Bail if the action isn't down in the first place to prevent wonky behavior with multiple key presses
    if not self.actionDown then return end

    self.actionDown = false

    if self.touchDraggedMember then
        self:select(self.lastSelection) -- Reselect the last selection (otherwise touch scrolling can feel clunky on mouse)
        self.touchDraggedMember = nil
        return -- Make sure the reselected member dosn't get clicked
    end

    if self.selectedMember then self:triggerEvent("action", self.selectedMember) end
end

--------------------------------------------------
--- ### UI:actionPulse()
--- Calls UI:actionPress() and UI:actionRelease().
---  
--- It's recommended to call actionPress and actionRelease on the respective key events instead of actionPulse,
--- but if you just want a single callback for a generic "key pressed" event, you can use actionPulse.  
--- Note that this doesn't allow for touch scrolling to work.
function UI:actionPulse()
    self:actionPress()
    self:actionRelease()
end

--------------------------------------------------
--- ### UI:scroll(scrollX, scrollY)
--- Tells the UI how much the user is scrolling in each given direction (1 would correspond to one mouse wheel movement).  
--- Each direction is optional - if not supplied, no scroll input is applied in that direction.  
--- If ignoreVelocity is set to true, no velocity is applied, and the scroller is moved instantly.
---@param scrollX? number
---@param scrollY? number
---@param ignoreVelocity? boolean
function UI:scroll(scrollX, scrollY, ignoreVelocity)
    if self.enabledState ~= "enabled" then return end
    return self:scrollAt(self.cursorX, self.cursorY, scrollX, scrollY, ignoreVelocity)
end

--------------------------------------------------
--- ### UI:disable(keepGraphics)
--- Disables the UI, making inputs not register for it.  
--- If `keepGraphics` is set to true, the UI will still be drawn, otherwise drawing will be disabled too.
function UI:disable(keepGraphics)
    self.actionDown = false
    self.touchDraggedMember = nil

    if keepGraphics then self.enabledState = "noinput"
    else self.enabledState = "disabled" end
end

--------------------------------------------------
--- ### UI:sleep()
--- Puts the UI to sleep, disabling input, drawing, and updates. Awake it again with UI:enable().
function UI:sleep()
    self.actionDown = false
    self.touchDraggedMember = nil

    self.enabledState = "asleep"
end

--------------------------------------------------
--- ### UI:enable(graphicsOnly)
--- Enables the UI if it has been previously disabled by UI:disable() or UI:sleep().  
--- If `graphicsOnly` is set to true, only drawing will be re-enabled.
function UI:enable(graphicsOnly)
    if not graphicsOnly then self.enabledState = "enabled"
    elseif self.enabledState == "disabled" or self.enabledState == "asleep" then self.enabledState = "noinput" end
end

--------------------------------------------------
--- ### UI:scrollAt(x, y, scrollX, scrollY, ignoreMaxSpeed, ignoreVelocity)
--- Tells the UI to scroll at a specific location.  
--- For most purposes, UI:scroll() will suffice, as it scrolls at the current cursor position.
---@param x number The X position to scroll at
---@param y number The Y position to scroll at
---@param scrollX? number The amount to scroll in the X axis
---@param scrollY? number The amount to scroll in the Y axis
---@param ignoreVelocity? boolean If true, no velocity is applied, and the scroller is moved instantly
---@param ignoreMaxSpeed? boolean If true, the applied speed won't be limited by max scrolling speed
---@param speed? number Optionally override the scrolling speed
function UI:scrollAt(x, y, scrollX, scrollY, ignoreVelocity, ignoreMaxSpeed, speed)
    scrollX = scrollX or 0
    scrollY = scrollY or 0

    local cursorX, cursorY = x, y

    for memberIndex = #self.members, 1, -1 do
        if scrollX == 0 and scrollY == 0 then break end

        local member = self.members[memberIndex]
        local memberX, memberY, memberWidth, memberHeight = member:getCroppedBounds()

        local cursorInBounds = cursorX > memberX and cursorY > memberY and cursorX < memberX + memberWidth and cursorY < memberY + memberHeight

        if cursorInBounds then
            local scrolledX, scrolledY = member:scroll(scrollX, scrollY, ignoreVelocity, ignoreMaxSpeed, speed)
            if scrolledX then scrollX = 0 end
            if scrolledY then scrollY = 0 end
        end
    end
end

--------------------------------------------------
--- ### UI:select(member)
--- Used internally but can also be used externally, however note that the function takes the instanced LiveMember as the input, not an Element.
---
--- Makes the member considered selected by the UI. If no member is supplied, the currently selected member gets deselected.  
--- Can optionally scroll elements to put the newly selected element into view.
---@param member? Papayui.LiveMember The member to select
---@param scrollToView? boolean Whether or not to scroll the selected element into view
function UI:select(member, scrollToView)
    local currentSelected = self.selectedMember

    self.selectedMember = member
    self.lastSelection = member or self.lastSelection

    if scrollToView and member then member:scrollToView() end

    if member ~= currentSelected then
        if currentSelected then self:triggerEvent("unhover", currentSelected) end
        if member then self:triggerEvent("hover", member) end
    end
end

--------------------------------------------------
--- ### UI:findMember(elementOrFunction)
--- Finds and returns a LiveMember.  
---
--- * When supplied with an Element, returns the member instanced from that element.  
--- * When supplied with a function, the function gets called on each member, passing the member into the function, and returns the element the function returns true for.
---@param elementOrFunction Papayui.Element|fun(member: Papayui.LiveMember): boolean
function UI:findMember(elementOrFunction)
    local isFunction = type(elementOrFunction) == "function"
    local members = self.members
    for memberIndex = 1, #members do
        local member = members[memberIndex]
        local found = isFunction and elementOrFunction(member) or member.element == elementOrFunction
        if found then return member end
    end
end

--------------------------------------------------
--- Finds a member according to the value in an element.nav
---@param nav Papayui.Element|fun(checkedElementEvent: Papayui.Event, originEvent: Papayui.Event): boolean
---@param originMember Papayui.LiveMember
---@return Papayui.LiveMember?
function UI:findMemberAsNavigation(nav, originMember)
    local isFunction = type(nav) == "function"

    ---@type Papayui.Event
    local originEvent

    if isFunction then
        originEvent = {
            type = "navigate",
            targetMember = originMember,
            targetElement = originMember.element,
            data = originMember.element.data,
            ui = self
        }
    end

    local members = self.members
    for memberIndex = 1, #members do
        local member = members[memberIndex]
        if isFunction then
            ---@type Papayui.Event
            local memberEvent = {
                type = "navigate",
                targetMember = member,
                targetElement = member.element,
                data = member.element.data,
                ui = self
            }

            if nav(memberEvent, originEvent) then return member end
        else
            if member.element == nav then return member end
        end
    end

    return nil
end

--------------------------------------------------
--- Returns the first selectable member it finds. Used internally.
---@return Papayui.LiveMember?
---@param buttonSelectionOnly? boolean
function UI:findDefaultSelectable(buttonSelectionOnly)
    if self.lastSelection and (not buttonSelectionOnly or self.lastSelection.element.behavior.buttonSelectable) then
        local _, _, croppedWidth, croppedHeight = self.lastSelection:getCroppedBounds()
        if croppedWidth > 0 and croppedHeight > 0 then return self.lastSelection end
    end

    local bestCandidate = nil
    local bestCandidateImportance = -math.huge

    local members = self.members
    for memberIndex = 1, #members do
        local member = members[memberIndex]
        local _, _, croppedWidth, croppedHeight = member:getCroppedBounds()

        if member:isSelectable() and croppedWidth > 0 and croppedHeight > 0 and (not buttonSelectionOnly or member.element.behavior.buttonSelectable) then
            if member.element.importance > bestCandidateImportance then
                bestCandidate = member
                bestCandidateImportance = member.element.importance
            end
        end
    end

    return bestCandidate
end

--------------------------------------------------
--- Returns the (topmost) member at the given coordinate. Used internally.
---@param x number
---@param y number
---@return Papayui.LiveMember?
function UI:findMemberAtCoordinate(x, y)
    local members = self.members
    for memberIndex = #members, 1, -1 do
        local member = members[memberIndex]

        local memberX, memberY, memberWidth, memberHeight = member:getCroppedBounds()

        local inBounds = x > memberX and y > memberY and x < memberX + memberWidth and y < memberY + memberHeight
        if inBounds then return member end
    end
end

--------------------------------------------------
--- ### UI:memberIsPresent(member)
--- Checks if the given member is present in the UI
---@param member Papayui.LiveMember
---@return boolean
function UI:memberIsPresent(member)
    local members = self.members
    for memberIndex = 1, #members do
        if members[memberIndex] == member then return true end
    end
    return false
end

--------------------------------------------------
--- ### UI:triggerEvent(eventType, member)
--- Triggers the specified event on the given member
---@param eventType Papayui.EventType
---@param member Papayui.LiveMember
function UI:triggerEvent(eventType, member)
    ---@type Papayui.Event
    local event = {
        type = eventType,
        targetMember = member,
        targetElement = member.element,
        data = member.element.data,
        ui = self
    }

    self:callEvent(event)
end

--------------------------------------------------
--- ### UI:callEvent(event)
--- Calls the callbacks of an already created event.  
--- For most purposes, it's better to use UI:triggerEvent() instead.
---@param event Papayui.Event
function UI:callEvent(event)
    local eventType = event.type
    local behavior = event.targetMember.element.behavior

    if eventType == "action" and behavior.action then behavior.action(event) end -- A second place to define actions in behaviors for ease of use
    if behavior.callbacks[eventType] then behavior.callbacks[eventType](event) end
    if papayui.callbacks[eventType] then papayui.callbacks[eventType](event) end
end

--------------------------------------------------
--- ### UI:appendElement(element)
--- Instances a new member from an element and adds it to the UI, optionally also assigning it a position.  
--- Note that, upon a refresh, the element will be removed.
---@param element Papayui.Element
---@param x? number
---@param y? number
---@return Papayui.LiveMember
function UI:appendElement(element, x, y)
    local member = papayui.newLiveMember(element, x, y)
    self.members[#self.members+1] = member
    return member
end

--------------------------------------------------
--- ### UI:removeMember(member)
--- Removes a specific member from the UI.  
--- Note that, upon a refresh, the UI is put back into its initial state, so the member will be put back if it was originally there.
---@param member Papayui.LiveMember
---@return boolean success
function UI:removeMember(member)
    for memberIndex = 1, #self.members do
        if self.members[memberIndex] == member then
            table.remove(self.members, memberIndex)
            return true
        end
    end
    return false
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

local function shallowCopy(t)
    if type(t) ~= "table" then return t end
    local copiedTable = {}
    for key, value in pairs(t) do
        copiedTable[key] = value
    end
    return copiedTable
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
---@return Papayui.ElementStyle
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
---@return Papayui.ElementStyle
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
---@return Papayui.ElementStyle
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
---@return Papayui.ElementStyle
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
--- For most alignment purposes, setting just the horizontal and vertical align will serve all needs.
--- If you want to set the alignment in more detail, then:
--- * alignHorizontal and alignVertical align all the child elements together relative to the parent element
--- * alignInside aligns the elements individually relatively to their assigned position where it makes sense for the given layout, such as the cross axis alignment within a line
--- * alignInsideSecondary aligns the other axis of alignInside, for the few layouts where alignInside exists on both axes
--- 
--- If verticalAlign isn't supplied, it is set to the same align as horizontalAlign.  
--- If alignInside isn't supplied, it will set itself to be same as the align on the cross axis, based on the selected layout.  
--- If alignInsideSecondary isn't supplied, it won't be changed
---@param layout Papayui.ElementLayout The layout used
---@param alignHorizontal Papayui.Alignment The horizontal alignment used
---@param alignVertical? Papayui.Alignment The vertical alignment used (Default is alignHorizontal)
---@param alignInside? Papayui.Alignment The alignInside used (Default is same as cross axis alignment)
---@param alignInsideSecondary? Papayui.Alignment The alignInsideSecondary used
---@return Papayui.ElementStyle
function ElementStyle:setLayout(layout, alignHorizontal, alignVertical, alignInside, alignInsideSecondary)
    alignVertical = alignVertical or alignHorizontal
    alignInsideSecondary = alignInsideSecondary or self.alignInsideSecondary

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
    self.alignInsideSecondary = alignInsideSecondary

    return self
end

--------------------------------------------------
--- ### ElementStyle:setScroll(horizontalScroll, verticalScroll)
--- Sets the style's enabled horizontal and vertical scrolling.
---
--- If only the first value is supplied, it is applied to both horizontal and vertical scroll.
---@param horizontalScroll boolean
---@param verticalScroll? boolean
---@return Papayui.ElementStyle
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
---@return Papayui.ElementStyle
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
---@return Papayui.ElementStyle
function ElementStyle:setColor(color, colorHover)
    self.color = color
    self.colorHover = colorHover
    return self
end

--------------------------------------------------
--- ### ElementStyle:clone()
--- Returns a copy of the style
---@return Papayui.ElementStyle
function ElementStyle:clone()
    local copiedTable = deepCopy(self)
    return setmetatable(copiedTable, ElementStyleMT)
end

-- Behavior methods --------------------------------------------------------------------------------

--------------------------------------------------
--- ### ElementBehavior:clone()
--- Returns a copy of the behavior
---@return Papayui.ElementBehavior
function ElementBehavior:clone()
    local copiedTable = deepCopy(self)
    return setmetatable(copiedTable, ElementBehaviorMT)
end

-- Template methods --------------------------------------------------------------------------------

--------------------------------------------------
--- ### Template:instance(...)
--- ### Template:newElement(...)
--- Creates a new papayui element from the template. (Behavior and style will not be cloned, modifying them will modify the template!)  
--- 
--- If the template has a constructor, the vararg passed into this method will be passed into it.
---@param ... unknown Constructor params
---@return Papayui.Element element The new papayui element
function Template:instance(...)
    local element = papayui.newElement(self.style, self.behavior)
    if self.data then element.data = shallowCopy(self.data) end
    if self.init then self.init(element, ...) end
    return element
end
Template.newElement = Template.instance

--------------------------------------------------
--- ### Template:clone()
--- Returns a copy of the template.
---@return Papayui.Template
function Template:clone()
    ---@type Papayui.Template
    local clonedTemplate = {
        style = self.style and self.style:clone(),
        behavior = self.behavior and self.behavior:clone(),
        data = self.data and shallowCopy(self.data),
        init = self.init
    }
    return setmetatable(clonedTemplate, TemplateMT)
end

---@param style Papayui.ElementStyle
---@return Papayui.Template self
function Template:setStyle(style)
    self.style = style
    return self
end

---@param behavior Papayui.ElementBehavior
---@return Papayui.Template self
function Template:setBehavior(behavior)
    self.behavior = behavior
    return self
end

---@param key string
---@param value any
---@return Papayui.Template self
function Template:setDataField(key, value)
    self.data = self.data or {}
    self.data[key] = value
    return self
end

---@param func fun(element: Papayui.Element, ...: unknown)
---@return Papayui.Template self
function Template:setConstructor(func)
    self.init = func
    return self
end

-- Element methods ---------------------------------------------------------------------------------

--------------------------------------------------
--- ### Element:clone()
--- Returns a copy of the element.
---@return Papayui.Element
function Element:clone()
    ---@type Papayui.Element
    local clonedElement = {
        style = self.style:clone(),
        behavior = self.behavior:clone(),
        children = {unpack(self.children)},
        nav = shallowCopy(self.nav),
        importance = self.importance,
        data = shallowCopy(self.data)
    }

    return setmetatable(clonedElement, ElementMT)
end

--------------------------------------------------
--- ### Element:setDataField(key, value)
--- Sets a field in the element's data table
---@param key string
---@param value any
---@return Papayui.Element self
function Element:setDataField(key, value)
    self.data[key] = value
    return self
end

--------------------------------------------------
--- ### Element:appendChildren(...)
---@param ... Papayui.Element
---@return Papayui.Element self
function Element:appendChildren(...)
    local addedChildren = {...}
    for i = 1, #addedChildren do
        local child = addedChildren[i]
        self.children[#self.children+1] = child
    end
    return self
end

--------------------------------------------------
--- ### Element:setStyle(style)
--- Sets the style used by the element.
---@param style Papayui.ElementStyle
---@return Papayui.Element self
function Element:setStyle(style)
    self.style = style
    return self
end

--------------------------------------------------
--- ### Element:setBehavior(behavior)
--- Sets the behavior used by the element.
---@param behavior Papayui.ElementBehavior
---@return Papayui.Element self
function Element:setBehavior(behavior)
    self.behavior = behavior
    return self
end

--------------------------------------------------
--- ### Element:setNavigation(direction, newSelection)
--- Sets the navigation rule of the element in the given direction
---@param direction "left"|"up"|"right"|"down"
---@param newSelection Papayui.Element|fun(checkedElementEvent: Papayui.Event, originEvent: Papayui.Event): boolean
---@return Papayui.Element self
function Element:setNavigation(direction, newSelection)
    self.nav[direction] = newSelection
    return self
end

---@param x? number The X coordinate to draw at (Default is 0)
---@param y? number The Y coordinate to draw at (Default is 0)
---@param width? number The width to draw the element as (Default is element's width)
---@param height? number The height to draw the element as (Default is the element's height)
---@param isSelected? boolean If the element should be drawn as if it was selected (hovered over) (Default is false)
---@param event? Papayui.Event Event to be triggered by the drawing (Default is none)
function Element:draw(x, y, width, height, isSelected, event)
    local style = self.style
    x = x or 0
    y = y or 0
    width = width or style.width
    height = height or style.height
    isSelected = isSelected or false

    local color = papayui.colors[style.color]
    local colorHover = papayui.colors[style.colorHover]
    if isSelected and colorHover then color = colorHover end

    if style.color and not color then
        color = papayui.fallbackColor
    end

    local drawRectangle = style.drawRectangle == nil and papayui.drawElementRectangles or style.drawRectangle
    if color and drawRectangle then
        papayui.graphics.drawRectangle(x, y, width, height, color)
    end

    local nilUI = papayui.getNilUI()

    ---@type Papayui.DrawEvent?
    ---@diagnostic disable-next-line: assign-type-mismatch
    local drawEvent = event
    if drawEvent then
        drawEvent.x = x
        drawEvent.y = y
        drawEvent.width = width
        drawEvent.height = height
        drawEvent.color = color
        drawEvent.isSelected = isSelected
    else
        drawEvent = {
            type = "draw",
            targetMember = nilUI.members[1],
            targetElement = self,
            data = self.data,
            ui = nilUI,
            x = x,
            y = y,
            width = width,
            height = height,
            color = color,
            isSelected = isSelected
        }
    end

    if papayui.drawElement then
        papayui.drawElement(drawEvent)
    end

    if style.draw then
        style.draw(drawEvent)
    end

    if style.drawInner then
        drawEvent.x = drawEvent.x + style.padding[1]
        drawEvent.y = drawEvent.y + style.padding[2]
        drawEvent.width = drawEvent.width - style.padding[1] - style.padding[3]
        drawEvent.height = drawEvent.height - style.padding[2] - style.padding[4]
        style.drawInner(drawEvent)
        drawEvent.x = x
        drawEvent.y = y
        drawEvent.width = width
        drawEvent.height = height
    end

    if drawEvent.ui ~= nilUI then
        drawEvent.ui:callEvent(drawEvent)
    end
end

-- Misc stuff --------------------------------------------------------------------------------------
-- Some are exported by the module since they could be useful

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

--- Returns the area where the two input areas overlap.
---@param aX number
---@param aY number
---@param aWidth number
---@param aHeight number
---@param bX number
---@param bY number
---@param bWidth number
---@param bHeight number
---@return number x
---@return number y
---@return number width
---@return number height
function papayui.overlapAreas(aX, aY, aWidth, aHeight, bX, bY, bWidth, bHeight)
    local ax1, ay1 = aX, aY
    local ax2, ay2 = ax1 + aWidth, ay1 + aHeight

    local bx1, by1 = bX, bY
    local bx2, by2 = bx1 + bWidth, by1 + bHeight

    local x1 = math.max(ax1, bx1)
    local y1 = math.max(ay1, by1)
    local x2 = math.min(ax2, bx2)
    local y2 = math.min(ay2, by2)

    return x1, y1, x2 - x1, y2 - y1
end

--- Changes the currentValue by the moveAmount, but only within the specified range - the moveAmount gets shortened if needed.  
---
--- Returns the adjusted moveAmount.
---@param rangeMin number
---@param rangeMax number
---@param currentValue number
---@param moveAmount number
---@return number moveAmount
function papayui.moveWithinRange(rangeMin, rangeMax, currentValue, moveAmount)
    if rangeMax < rangeMin then return 0 end
    if moveAmount == 0 then return 0 end
    if moveAmount < 0 and currentValue < rangeMin then return 0 end
    if moveAmount > 0 and currentValue > rangeMax then return 0 end

    if moveAmount > 0 then return math.min(currentValue + moveAmount, rangeMax) - currentValue end
    if moveAmount < 0 then return math.max(currentValue + moveAmount, rangeMin) - currentValue end

    return 0
end

--- Gets the distance between 2 rectangles
---@param aX number
---@param aY number
---@param aWidth number
---@param aHeight number
---@param bX number
---@param bY number
---@param bWidth number
---@param bHeight number
---@return number distance
function papayui.rectangleDistance(aX, aY, aWidth, aHeight, bX, bY, bWidth, bHeight)
    local ax1, ay1 = aX, aY
    local ax2, ay2 = ax1 + aWidth, ay1 + aHeight

    local bx1, by1 = bX, bY
    local bx2, by2 = bx1 + bWidth, by1 + bHeight

    -- Relationship of rectangle B to rectangle A
    local left   = bx2 < ax1
    local top    = by2 < ay1
    local right  = bx1 > ax2
    local bottom = by1 > ay2

    -- This approach is very wordy but at least it has 5 scenarios with no sqrt

    if top and left then
        local xDiff = bx2 - ax1
        local yDiff = by2 - ay1
        return math.sqrt(xDiff * xDiff + yDiff * yDiff)
    end
    if top and right then
        local xDiff = bx1 - ax2
        local yDiff = by2 - ay1
        return math.sqrt(xDiff * xDiff + yDiff * yDiff)
    end
    if bottom and left then
        local xDiff = bx2 - ax1
        local yDiff = by1 - ay2
        return math.sqrt(xDiff * xDiff + yDiff * yDiff)
    end
    if bottom and right then
        local xDiff = bx1 - ax2
        local yDiff = by1 - ay2
        return math.sqrt(xDiff * xDiff + yDiff * yDiff)
    end
    if left then
        return ax1 - bx2
    end
    if top then
        return ay1 - by2
    end
    if right then
        return bx1 - ax2
    end
    if bottom then
        return by1 - ay2
    end
    return 0
end

---@param targetDistanceTravelled number
---@param friction number
---@param highestAttempt? integer
---@param simulationTime? integer
---@return number
local function predictNeededScrollVelocity(targetDistanceTravelled, friction, highestAttempt, simulationTime)
    highestAttempt = highestAttempt or 1000
    simulationTime = simulationTime or 300

    if targetDistanceTravelled == 0 then return 0 end

    for attempt = 1, highestAttempt do
        local initialVelocity = attempt * (targetDistanceTravelled > 0 and 1 or -1)

        local velocity = initialVelocity
        local result = 0
        for velocityIteration = 1, simulationTime do
            result = result + velocity
            velocity = velocity - (velocity * friction)
        end

        if math.abs(result) >= math.abs(targetDistanceTravelled) then return initialVelocity end
    end

    return highestAttempt
end

-- Abstraction for possible usage outside LÖVE -----------------------------------------------------

-- Can be replaced with functions to perform these actions in non-love2d environments
papayui.graphics = {}

---@diagnostic disable-next-line: undefined-global
local love = love

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

papayui.graphics.getCrop = love and love.graphics.getScissor

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
    bottom = 1,
    spread = 0,
    spacebetween = 0
}

local spreadAlignKeywords = {
    spread = true,
    spacebetween = true
}

local function getNudgeValue(usableSpace, usedSpace, align)
    local unusedSpace = usableSpace - usedSpace
    return (align * unusedSpace + unusedSpace) / 2
end

--- Layouts should use this function to generate the members of the parent member.  
--- Not a very useful function outside layouts.
---@param parentMember Papayui.LiveMember
---@return Papayui.LiveMember[]
function papayui.generateChildMembers(parentMember)
    local elements = parentMember.element.children
    local previousChildren = parentMember.children
    local elementsAreIdentical = parentMember:childElementsAreIdentical(elements)

    parentMember.children = {}

    ---@type Papayui.LiveMember[]
    local members = {}
    for elementIndex = 1, #elements do
        local element = elements[elementIndex]

        local member
        if elementsAreIdentical then
            member = previousChildren[elementIndex]
            member.nav = {}
            member.parent = parentMember
            member:resetBounds(0, 0)
        else
            member = papayui.newLiveMember(element, 0, 0, parentMember)
        end

        members[elementIndex] = member
        parentMember.children[elementIndex] = member
    end
    return members
end
local generateChildMembers = papayui.generateChildMembers

---@param memberCount integer
---@param usableSpace number
---@param usedSpace number
---@return number
local function getSpreadGapIncrease(memberCount, usableSpace, usedSpace)
    local unusedSpace = usableSpace - usedSpace
    if unusedSpace < 0 then return 0 end
    return unusedSpace / (memberCount - 1)
end

---@param members Papayui.LiveMember[]
---@param gapIncrease number
---@param lineIsVertical boolean
local function spreadOutLine(members, gapIncrease, lineIsVertical)
    local position = lineIsVertical and "y" or "x"

    local posAddition = 0
    for memberIndex = 1, #members do
        local member = members[memberIndex]
        member[position] = member[position] + posAddition
        posAddition = posAddition + gapIncrease
    end
end

---@param members Papayui.LiveMember[]
---@param gap number
---@param isVertical boolean
---@param spreadSize? number
---@return number lineSizeMain
---@return number lineSizeCross
local function layMembersInLine(members, gap, alignInside, isVertical, spreadSize)
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

    -- Line size *does* take first and last member's margin into account
    if members[1] then
        lineSizeMain = lineSizeMain + members[1].element.style.margin[marginStart]
        lineSizeMain = lineSizeMain + members[#members].element.style.margin[marginEnd]
    end

    if spreadSize then
        local gapIncrease = getSpreadGapIncrease(#members, spreadSize, lineSizeMain)
        spreadOutLine(members, gapIncrease, isVertical)
        lineSizeMain = spreadSize
    end

    return lineSizeMain, lineSizeCross
end

local function memberIsLessWide(a, b) return a.width < b.width end
local function memberIsLessTall(a, b) return a.height < b.height end
---@param members Papayui.LiveMember
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

---@param member Papayui.LiveMember
---@param usableSpaceWidth number
---@param usableSpaceHeight number
local function growMember(member, usableSpaceWidth, usableSpaceHeight)
    local memberStyle = member.element.style
    if memberStyle.growHorizontal then
        local growTargetSize = usableSpaceWidth - memberStyle.margin[1] - memberStyle.margin[3]
        member.width = math.max(member.width, growTargetSize)
    end
    if memberStyle.growVertical then
        local growTargetSize = usableSpaceHeight - memberStyle.margin[2] - memberStyle.margin[4]
        member.height = math.max(member.height, growTargetSize)
    end
end

---@param members Papayui.LiveMember[]
---@param usableSpaceWidth number
---@param usableSpaceHeight number
local function growMembersToSameSpace(members, usableSpaceWidth, usableSpaceHeight)
    for memberIndex = 1, #members do
        growMember(members[memberIndex], usableSpaceWidth, usableSpaceHeight)
    end
end

---@param members Papayui.LiveMember[]
---@param usableSpaceMain number
---@param gap number
---@param mainAxisIsVertical boolean
---@param maxLineElements? number|table
---@return Papayui.LiveMember[][]
---@return number combinedLineHeights
local function splitMembersToLines(members, usableSpaceMain, gap, mainAxisIsVertical, maxLineElements)
    local sizeMain = mainAxisIsVertical and "height" or "width"
    local marginStart = mainAxisIsVertical and 2 or 1
    local marginEnd = mainAxisIsVertical and 4 or 3

    local sizeCross = mainAxisIsVertical and "width" or "height"
    local marginCrossStart = mainAxisIsVertical and 1 or 2
    local marginCrossEnd = mainAxisIsVertical and 3 or 4

    maxLineElements = maxLineElements or math.huge

    local lines = {}
    local currentLineIndex = 1
    local currentLineSize = 0
    local currentMemberIndex = 1
    local currentLineTallestElement = 0
    local combinedLineHeights = 0
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
            -- (could cause an infinite loop of a member always being too big)
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

                combinedLineHeights = combinedLineHeights + currentLineTallestElement
                currentLineTallestElement = 0
            end
        end

        local memberSizeCross = member[sizeCross] + memberMargin[marginCrossStart] + memberMargin[marginCrossEnd]
        currentLineTallestElement = math.max(currentLineTallestElement, memberSizeCross)

        currentLineSize = currentLineSize + memberSize + gap
    end

    combinedLineHeights = combinedLineHeights + currentLineTallestElement

    return lines, combinedLineHeights
end

---@param members Papayui.LiveMember[]
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

---@param member Papayui.LiveMember
---@param x number
---@param y number
---@param width number
---@param height number
---@param alignHorizontal number
---@param alignVertical number
local function alignMember(member, x, y, width, height, alignHorizontal, alignVertical)
    local memberMargin = member.element.style.margin
    local memberX = member.x
    local memberY = member.y
    local memberWidth = member.width
    local memberHeight = member.height

    local leftmostPoint = memberX - memberMargin[1]
    local topmostPoint = memberY - memberMargin[2]
    local rightmostPoint = memberX + memberWidth + memberMargin[3]
    local bottommostPoint = memberY + memberHeight + memberMargin[4]

    local usedWidth = rightmostPoint - leftmostPoint
    local usedHeight = bottommostPoint - topmostPoint

    local xNudge = x + getNudgeValue(width, usedWidth, alignHorizontal) - leftmostPoint -- Top left point subtraction
    local yNudge = y + getNudgeValue(height, usedHeight, alignVertical) - topmostPoint  -- to put top left corner at 0, 0
    member.x = member.x + xNudge
    member.y = member.y + yNudge
end

---@param members Papayui.LiveMember[]
---@param x number
---@param y number
---@param width number
---@param height number
---@param alignHorizontal number
---@param alignVertical number
local function alignMembersIndividually(members, x, y, width, height, alignHorizontal, alignVertical)
    for memberIndex = 1, #members do
       alignMember(members[memberIndex], x, y, width, height, alignHorizontal, alignVertical)
    end
end

---@param member1 Papayui.LiveMember
---@param member2 Papayui.LiveMember
---@param axisIsVertical boolean
---@return number
local function getAxisOverlap(member1, member2, axisIsVertical)
    local position = axisIsVertical and "y" or "x"
    local size = axisIsVertical and "height" or "width"

    local position1 = member1[position]
    local size1 = member1[size]

    local position2 = member2[position]
    local size2 = member2[size]

    local a1, a2 = position1, position1 + size1
    local b1, b2 = position2, position2 + size2

    local overlapStart = math.max(a1, b1)
    local overlapEnd   = math.min(a2, b2)

    local overlap = overlapEnd - overlapStart
    return overlap
end

---@param member Papayui.LiveMember
---@param otherMembers Papayui.LiveMember[]
---@param axisIsVertical boolean
---@return Papayui.LiveMember?
local function findLargestAxisOverlap(member, otherMembers, axisIsVertical)
    local maxOverlap = 0
    local maxOverlapMember

    for otherMemberIndex = 1, #otherMembers do
        local otherMember = otherMembers[otherMemberIndex]

        local overlap = getAxisOverlap(member, otherMember, axisIsVertical)
        if overlap > maxOverlap then
            maxOverlap = overlap
            maxOverlapMember = otherMember
        end
    end

    return maxOverlapMember
end

---@param lines Papayui.LiveMember[][]
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

---@type table<Papayui.ElementLayout, fun(member: Papayui.LiveMember, ...?): Papayui.LiveMember[]>
papayui.layouts = {}

function papayui.layouts.none()
    return {}
end

function papayui.layouts.singlerow(parentMember, flipAxis)
    local style = parentMember.element.style
    local originX = parentMember.x + style.padding[1]
    local originY = parentMember.y + style.padding[2]
    local gap = flipAxis and style.gap[2] or style.gap[1]

    local alignHorizontal = alignEnum[style.alignHorizontal]
    local alignVertical = alignEnum[style.alignVertical]
    local alignInside = alignEnum[style.alignInside]
    local usableSpaceWidth = parentMember.width - style.padding[1] - style.padding[3]
    local usableSpaceHeight = parentMember.height - style.padding[2] - style.padding[4]

    local usableSpaceMain = flipAxis and usableSpaceHeight or usableSpaceWidth
    local alignMainKeyword = flipAxis and style.alignVertical or style.alignHorizontal
    local doLineSpread = spreadAlignKeywords[alignMainKeyword]

    local outMembers = generateChildMembers(parentMember)
    growLineMembers(outMembers, usableSpaceWidth, usableSpaceHeight, gap, flipAxis)
    layMembersInLine(outMembers, gap, alignInside, flipAxis, doLineSpread and usableSpaceMain)
    alignMembers(outMembers, originX, originY, usableSpaceWidth, usableSpaceHeight, alignHorizontal, alignVertical)

    return outMembers
end

function papayui.layouts.singlecolumn(parentMember)
    return papayui.layouts.singlerow(parentMember, true)
end

function papayui.layouts.rows(parentMember, flipAxis)
    local style = parentMember.element.style
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
    local usableSpaceCross = flipAxis and usableSpaceWidth or usableSpaceHeight

    local alignMainKeyword = flipAxis and style.alignVertical or style.alignHorizontal
    local alignCrossKeyword = flipAxis and style.alignHorizontal or style.alignVertical
    local doLineSpreadMain = spreadAlignKeywords[alignMainKeyword]
    local doLineSpreadCross = spreadAlignKeywords[alignCrossKeyword]

    local lineSpreadSizeMain = doLineSpreadMain and usableSpaceMain

    local outMembers = {}
    local generatedMembers = generateChildMembers(parentMember)
    local lines, combinedLineHeights = splitMembersToLines(generatedMembers, usableSpaceMain, gapMain, flipAxis, maxLineMembers)
    local usedSpaceCross = combinedLineHeights + (#lines - 1) * gapCross

    if doLineSpreadCross then
        local gapIncrease = getSpreadGapIncrease(#lines, usableSpaceCross, usedSpaceCross)
        gapCross = gapCross + gapIncrease
    end

    local lineOffset = 0
    for lineIndex = 1, #lines do
        local line = lines[lineIndex]
        growLineMembers(line, usableSpaceWidth, usableSpaceHeight, gapMain, flipAxis, true)
        layMembersInLine(line, gapMain, alignInside, flipAxis, lineSpreadSizeMain)

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

function papayui.layouts.stack(parentMember)
    local style = parentMember.element.style
    local originX = parentMember.x + style.padding[1]
    local originY = parentMember.y + style.padding[2]

    local alignHorizontal = alignEnum[style.alignHorizontal]
    local alignVertical = alignEnum[style.alignVertical]
    local usableSpaceWidth = parentMember.width - style.padding[1] - style.padding[3]
    local usableSpaceHeight = parentMember.height - style.padding[2] - style.padding[4]

    local outMembers = generateChildMembers(parentMember)
    growMembersToSameSpace(outMembers, usableSpaceWidth, usableSpaceHeight)
    alignMembersIndividually(outMembers, originX, originY, usableSpaceWidth, usableSpaceHeight, alignHorizontal, alignVertical)

    return outMembers
end

function papayui.layouts.positionlist(parentMember)
    local style = parentMember.element.style
    local originX = parentMember.x + style.padding[1]
    local originY = parentMember.y + style.padding[2]

    local alignInside = alignEnum[style.alignInside]
    local alignInsideSecondary = alignEnum[style.alignInsideSecondary]
    local alignHorizontal = alignEnum[style.alignHorizontal]
    local alignVertical = alignEnum[style.alignVertical]
    local usableSpaceWidth = parentMember.width - style.padding[1] - style.padding[3]
    local usableSpaceHeight = parentMember.height - style.padding[2] - style.padding[4]

    local positionList = style.positionList
    if not positionList then return {} end

    local generatedMembers = generateChildMembers(parentMember)
    local outMembers = {}

    local maxPosition = math.min(#positionList, #generatedMembers)
    for positionIndex = 1, maxPosition do
        local position = positionList[positionIndex]
        local member = generatedMembers[positionIndex]

        local xNudge = getNudgeValue(-member.width, 0, alignInside)
        local yNudge = getNudgeValue(-member.height, 0, alignInsideSecondary)

        member.x = position[1] + xNudge
        member.y = position[2] + yNudge

        outMembers[positionIndex] = member
    end

    alignMembers(outMembers, originX, originY, usableSpaceWidth, usableSpaceHeight, alignHorizontal, alignVertical)
    return outMembers
end

-- Members -----------------------------------------------------------------------------------------

--- Used internally by the library
---@param element Papayui.Element
---@param x? number
---@param y? number
---@param parent? Papayui.LiveMember
---@return Papayui.LiveMember
function papayui.newLiveMember(element, x, y, parent)
    local style = element.style

    ---@type Papayui.LiveMember
    local member = {
        element = element,
        children = {},
        x = 0,
        y = 0,
        width = 0,
        height = 0,
        scrollX = 0,
        scrollY = 0,
        scrollVelocityX = 0,
        scrollVelocityY = 0,
        offsetX = style.offsetX,
        offsetY = style.offsetY,
        parent = parent,
        nav = {}
    }
    setmetatable(member, LiveMemberMT)

    member:resetBounds(x, y)

    return member
end

---@param isSelected? boolean If the element should render as hovered over
---@param event? Papayui.Event Event to be triggered by the drawing
function LiveMember:draw(isSelected, event)
    local cropX, cropY, cropWidth, cropHeight = papayui.graphics.getCrop()
    if self.parent then papayui.graphics.setCrop(self.parent:getCropArea()) end

    local x, y, width, height = self:getBounds()
    self.element:draw(x, y, width, height, isSelected, event)

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

---@param addX? number Addition to the X offset
---@param addY? number Addition to the Y offset
---@return number offsetX
---@return number offsetY
function LiveMember:getOffset(addX, addY)
    addX = addX or 0
    addY = addY or 0
    local parent = self.parent
    local x, y = self.offsetX + addX, self.offsetY + addY

    if parent then return parent:getOffset(x, y) end
    return x, y
end

--- Gets the area this member takes up (before any cropping by other members)
---@return number x
---@return number y
---@return number width
---@return number height
function LiveMember:getBounds()
    local xScroll, yScroll = 0, 0
    if self.parent then xScroll, yScroll = self.parent:getScroll() end

    local xOffset, yOffset = self:getOffset()
    xOffset = xOffset + xScroll
    yOffset = yOffset + yScroll

    local x, y = self.x + xOffset, self.y + yOffset
    local width, height = self.width, self.height
    return x, y, width, height
end

--- Gets the same area as in getBounds(), but shrinks it by the member's padding
---@return number x
---@return number y
---@return number width
---@return number height
function LiveMember:getInnerBounds()
    local padding = self.element.style.padding
    local x, y, width, height = self:getBounds()
    return
        x + padding[1],
        y + padding[2],
        width - padding[1] - padding[3],
        height - padding[2] - padding[4]
end

--- Gets the same area as in getBounds(), but grows it by the member's margin
---@return number x
---@return number y
---@return number width
---@return number height
function LiveMember:getOuterBounds()
    local margin = self.element.style.margin
    local x, y, width, height = self:getBounds()
    return
        x - margin[1],
        y - margin[2],
        width + margin[1] + margin[3],
        height + margin[2] + margin[4]
end

--- Gets the area this member crops its contents to, optionally also overlapping it with the input area
---@param overlapX1? number Left side of area to overlap with
---@param overlapY1? number Top side of area to overlap with
---@param overlapX2? number Right side of area to overlap with
---@param overlapY2? number Bottom side of area to overlap with
---@param highestParent? Papayui.LiveMember If supplied, this member will be considered the root member, and its parents' crop values won't be considered
---@return number? cropX
---@return number? cropY
---@return number? cropWidth
---@return number? cropHeight
function LiveMember:getCropArea(overlapX1, overlapY1, overlapX2, overlapY2, highestParent)
    local parent = self.parent
    local style = self.element.style

    if self == highestParent then parent = nil end

    if not style.cropContent then
        if parent then
            return parent:getCropArea(overlapX1, overlapY1, overlapX2, overlapY2)
        end
        if not (overlapX1 and overlapY1 and overlapX2 and overlapY2) then return end
        return overlapX1, overlapY1, overlapX2 - overlapX1, overlapY2 - overlapY1
    end

    local x, y, width, height = self:getInnerBounds()
    local contentX1 = x
    local contentY1 = y
    local contentX2 = contentX1 + width
    local contentY2 = contentY1 + height

    overlapX1 = overlapX1 or contentX1
    overlapY1 = overlapY1 or contentY1
    overlapX2 = overlapX2 or contentX2
    overlapY2 = overlapY2 or contentY2

    contentX1 = math.max(contentX1, overlapX1)
    contentY1 = math.max(contentY1, overlapY1)
    contentX2 = math.min(contentX2, overlapX2)
    contentY2 = math.min(contentY2, overlapY2)

    if parent then return parent:getCropArea(contentX1, contentY1, contentX2, contentY2) end
    return contentX1, contentY1, contentX2 - contentX1, contentY2 - contentY1
end

--- Returns the area the member takes up after being cropped by the other members
---@param highestParent? Papayui.LiveMember If supplied, this member will be considered the root member, and its parents' crop values won't be considered
---@return number x
---@return number y
---@return number width
---@return number height
function LiveMember:getCroppedBounds(highestParent)
    local x, y, width, height = self:getBounds()
    local parent = self.parent
    if not parent then return x, y, width, height end

    local cropX, cropY, cropWidth, cropHeight = parent:getCropArea(x, y, x + width, y + height, highestParent)
    if cropX and cropY and cropWidth and cropHeight then
        return cropX, cropY, cropWidth, cropHeight
    end

    -- Technically it can't ever get here but it makes the language server happy to do it this way
    return x, y, width, height
end

--- Resets the member's bounds to default values or sets them to new ones
---@param x? number
---@param y? number
---@param width? number
---@param height? number
function LiveMember:resetBounds(x, y, width, height)
    local style = self.element.style
    local scale = style.ignoreScale and 1 or papayui.scale
    self.x = x or 0
    self.y = y or 0
    self.width = (width or style.width) * scale
    self.height = (height or style.height) * scale
    if style.preLayout then style.preLayout(self) end
end

--- Checks if the member's children are of the same instances and in the same order as the input elements
---@param elements Papayui.Element[]
---@return boolean
function LiveMember:childElementsAreIdentical(elements)
    local children = self.children
    if #children ~= #elements then return false end
    for childIndex = 1, #children do
        local child = children[childIndex]
        if child.element ~= elements[childIndex] then return false end
    end
    return true
end

---@return boolean
function LiveMember:isSelectable()
    local style = self.element.style
    local behavior = self.element.behavior

    if behavior.isSelectable ~= nil then return behavior.isSelectable end
    if behavior.action then return true end
    if behavior.callbacks.action then return true end
    if style.colorHover then return true end

    return false
end

--- Gets the mininmum and maximum values for each axis stating how far in that direction the member can scroll
---@return number minX
---@return number minY
---@return number maxX
---@return number maxY
function LiveMember:getScrollLimits()
    if #self.children == 0 then return 0,0,0,0 end

    local padding = self.element.style.padding
    local x1, y1 = self.x, self.y
    local x2, y2 = x1 + self.width, y1 + self.height
    x1 = x1 + padding[1]
    y1 = y1 + padding[2]
    x2 = x2 - padding[3]
    y2 = y2 - padding[4]

    local contentX1 = math.huge
    local contentY1 = math.huge
    local contentX2 = -math.huge
    local contentY2 = -math.huge
    local children = self.children
    for childIndex = 1, #children do
        local child = children[childIndex]

        local childMargin = child.element.style.margin
        local childX1, childY1 = child.x, child.y
        local childX2, childY2 = childX1 + child.width, childY1 + child.height
        childX1 = childX1 - childMargin[1]
        childY1 = childY1 - childMargin[2]
        childX2 = childX2 + childMargin[3]
        childY2 = childY2 + childMargin[4]

        contentX1 = math.min(contentX1, childX1)
        contentY1 = math.min(contentY1, childY1)
        contentX2 = math.max(contentX2, childX2)
        contentY2 = math.max(contentY2, childY2)
    end

    local minX = math.min(x2 - contentX2, 0)
    local minY = math.min(y2 - contentY2, 0)
    local maxX = math.max(x1 - contentX1, 0)
    local maxY = math.max(y1 - contentY1, 0)

    return minX, minY, maxX, maxY
end

--- Scrolls the parent elements so this element is fully visible
function LiveMember:scrollToView()
    local member = self

    local memberX, memberY, memberWidth, memberHeight = member:getOuterBounds()
    local x1, y1, x2, y2 = memberX, memberY, memberX + memberWidth, memberY + memberHeight

    local parent = member.parent
    while parent do
        local parentStyle = parent.element.style
        local parentX, parentY, parentWidth, parentHeight = parent:getInnerBounds()
        local px1, py1, px2, py2 = parentX, parentY, parentX + parentWidth, parentY + parentHeight

        local offsetX, offsetY = 0, 0
        offsetX = offsetX + math.max(px1 - x1, 0)
        offsetY = offsetY + math.max(py1 - y1, 0)
        offsetX = offsetX + math.min(px2 - x2, 0)
        offsetY = offsetY + math.min(py2 - y2, 0)

        if parentStyle.scrollHorizontal then
            local targetVelocity = offsetX
            if targetVelocity > 0 then targetVelocity = targetVelocity + papayui.buttonScrollOvershoot end
            if targetVelocity < 0 then targetVelocity = targetVelocity - papayui.buttonScrollOvershoot end
            local velocity = 0
            if targetVelocity ~= 0 then velocity = predictNeededScrollVelocity(targetVelocity, papayui.scrollFriction) end

            parent.scrollVelocityX = velocity
            x1 = x1 + offsetX
            x2 = x2 + offsetX
        end
        if parentStyle.scrollVertical then
            local targetVelocity = offsetY
            if targetVelocity > 0 then targetVelocity = targetVelocity + papayui.buttonScrollOvershoot end
            if targetVelocity < 0 then targetVelocity = targetVelocity - papayui.buttonScrollOvershoot end
            local velocity = 0
            if targetVelocity ~= 0 then velocity = predictNeededScrollVelocity(targetVelocity, papayui.scrollFriction) end

            parent.scrollVelocityY = velocity
            y1 = y1 + offsetY
            y2 = y2 + offsetY
        end
        parent = parent.parent
    end
end

--- Attempts to scroll by the given amount, outputting booleans for each axis stating whether or not that axis was scrolled.  
---@param scrollX? number The amount to scroll in the X axis
---@param scrollY? number The amount to scroll in the Y axis
---@param ignoreVelocity? boolean If true, no velocity is applied, and the scroller is moved instantly
---@param ignoreMaxSpeed? boolean If true, the applied speed won't be limited by max scrolling speed
---@param speed? number Optionally override the scrolling speed
---@return boolean scrolledX
---@return boolean scrolledY
function LiveMember:scroll(scrollX, scrollY, ignoreVelocity, ignoreMaxSpeed, speed)
    local style = self.element.style

    scrollX = scrollX or 0
    scrollY = scrollY or 0
    speed = speed or papayui.scrollSpeedStep * style.scrollSpeedMultiplier * papayui.scale

    local scrolledX = false
    local scrolledY = false

    local minScrollX, minScrollY, maxScrollX, maxScrollY = self:getScrollLimits()
    local currentScrollX, currentScrollY = self.scrollX, self.scrollY

    local cappedScrollX = papayui.moveWithinRange(minScrollX, maxScrollX, currentScrollX, scrollX)
    local cappedScrollY = papayui.moveWithinRange(minScrollY, maxScrollY, currentScrollY, scrollY)
    local canScrollX = style.scrollHorizontal and cappedScrollX ~= 0
    local canScrollY = style.scrollVertical and cappedScrollY ~= 0

    if canScrollX then
        local strength = speed * scrollX
        local addedVelocity = ignoreMaxSpeed and strength or papayui.moveWithinRange(-papayui.scrollSpeed, papayui.scrollSpeed, self.scrollVelocityX, strength)
        if ignoreVelocity then self.scrollX = currentScrollX + cappedScrollX
        else self.scrollVelocityX = self.scrollVelocityX + addedVelocity end
        scrolledX = true
    end

    if canScrollY then
        local strength = speed * scrollY
        local addedVelocity = ignoreMaxSpeed and strength or papayui.moveWithinRange(-papayui.scrollSpeed, papayui.scrollSpeed, self.scrollVelocityY, strength)
        if ignoreVelocity then self.scrollY = currentScrollY + cappedScrollY
        else self.scrollVelocityY = self.scrollVelocityY + addedVelocity end
        scrolledY = true
    end

    return scrolledX, scrolledY
end

--- Attempts to scroll the member, or recursively tries the same on its parent elements if it can't.
---@param scrollX? number The amount to scroll in the X axis
---@param scrollY? number The amount to scroll in the Y axis
---@param ignoreVelocity? boolean If true, no velocity is applied, and the scroller is moved instantly
---@param ignoreMaxSpeed? boolean If true, the applied speed won't be limited by max scrolling speed
---@param speed? number Optionally override the scrolling speed
function LiveMember:scrollRecursively(scrollX, scrollY, ignoreVelocity, ignoreMaxSpeed, speed)
    scrollX = scrollX or 0
    scrollY = scrollY or 0

    local member = self
    while member and (scrollX ~= 0 or scrollY ~= 0) do
        local scrolledX, scrolledY = member:scroll(scrollX, scrollY, ignoreVelocity, ignoreMaxSpeed, speed)
        if scrolledX then scrollX = 0 end
        if scrolledY then scrollY = 0 end
        member = member.parent
    end
end

--- Tries to select self or any child. If provided, will find the selection closest to the source member.
---@param source? Papayui.LiveMember
---@param notSelf? boolean
---@return Papayui.LiveMember?
function LiveMember:selectAny(source, notSelf)
    local sourceX, sourceY, sourceWidth, sourceHeight
    local closestMemberDistance = math.huge
    local closestMemberOverlap = 0
    local closestMember
    if source then
        sourceX, sourceY, sourceWidth, sourceHeight = source:getBounds()
    end

    local stack = {self}
    if notSelf then
        stack[1] = nil
        for childIndex = #self.children, 1, -1  do
            local child = self.children[childIndex]
            stack[#stack+1] = child
        end
    end

    while #stack > 0 do
        local member = stack[#stack]
        stack[#stack] = nil

        -- Only crop the elements up to the initial element's inner area, higher parents can't be taken into account
        local croppedX, croppedY, croppedWidth, croppedHeight = member:getCroppedBounds(self)

        local canSelect = member:isSelectable() and croppedWidth > 0 and croppedHeight > 0
        if canSelect and not source then return member end

        if canSelect and source and sourceX and sourceY and sourceWidth and sourceHeight then
            local distance = papayui.rectangleDistance(sourceX, sourceY, sourceWidth, sourceHeight, croppedX, croppedY, croppedWidth, croppedHeight)

            local overlapAxisIsVertical = croppedX + croppedWidth < sourceX or croppedX > sourceX + sourceWidth
            local overlap = getAxisOverlap(source, member, overlapAxisIsVertical)
            overlap = math.max(0, overlap)

            -- Find closest, break ties using amount of overlapping area
            -- Not perfect, but nothing is going to solve 100% of possible layouts
            local overwriteClosest = false
            overwriteClosest = overwriteClosest or distance < closestMemberDistance
            overwriteClosest = overwriteClosest or distance == closestMemberDistance and overlap > closestMemberOverlap
            if overwriteClosest then
                closestMember = member
                closestMemberDistance = distance
                closestMemberOverlap = overlap
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
---@param source Papayui.LiveMember
---@param direction 1|2|3|4
---@return Papayui.LiveMember?
function LiveMember:forwardNavigation(source, direction)
    if self.nav[direction] then return self.nav[direction]:select(source, direction) end
    if self.parent then return self.parent:forwardNavigation(source, direction) end
end

--- Return self or a child if a selectable element is present, or simply forward navigation if not
---@param source Papayui.LiveMember
---@param direction 1|2|3|4
---@return Papayui.LiveMember?
function LiveMember:select(source, direction)
    if self:isSelectable() then return self end

    local selectedChild = self:selectAny(source)
    if selectedChild then return selectedChild end

    return self:forwardNavigation(source, direction)
end

local emptyUI = papayui.newUI(papayui.newElement())
--- Returns the "no UI" UI, where its only member represents any element with no UI. Used internally.
---@return Papayui.UI
function papayui.getNilUI()
    return emptyUI
end

-- Fin ---------------------------------------------------------------------------------------------

return papayui