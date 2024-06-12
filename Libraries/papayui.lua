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

papayui.scrollSpeed = 100             -- The maximum scrolling speed
papayui.scrollSpeedStep = 5           -- How much scroll speed is added on each scroll input
papayui.scrollFriction = 0.2          -- How fast the scrolling slows down
papayui.buttonScrollOvershoot = 10    -- How many pixels to try to (roughly) overshoot when scrolling using button input
papayui.touchScrollingEnabled = true  -- Whether or not holding down the action key and dragging the cursor can scroll

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
---@field importance number When finding a default element to select, the element with the highest importance gets picked
local Element = {}
local ElementMT = {__index = Element}

---@class PapayuiUI
---@field members PapayuiLiveMember[] All the elements in the UI, in the drawn order
---@field selectedMember? PapayuiLiveMember The member that is currently selected
---@field lastSelection? PapayuiLiveMember The last element that was selected
---@field actionDown boolean If the action key is currently down (set automatically by the appropriate methods)
---@field cursorX number The cursor X coordinate
---@field cursorY number The cursor Y coordinate
---@field touchDraggedMember? PapayuiLiveMember The member that is currently being being scrolled using touch input
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
---@field scrollVelocityX number The scroll velocity in the X direction
---@field scrollVelocityY number The scroll velocity in the Y direction
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
        children = {},
        importance = 0
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
        lastSelection = nil,
        actionDown = false,
        cursorX = math.huge,
        cursorY = math.huge,
        touchDraggedMember = nil
    }
    setmetatable(ui, UIMT)

    local rootMember = papayui.newLiveMember(rootElement, x, y)
    ui.members[1] = rootMember
    ui:refresh()

    return ui
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

local defaultDeltaTime = 1/60
--------------------------------------------------
--- ### UI:update(dt)
--- Updates the dynamically changing elements of the UI, such as scrolling.  
--- If the UI doesn't contain any such elements, calling update is not necessary.  
---
--- If deltatime isn't supplied, assumes a constant 60 updates per second.
---@param dt? number
function UI:update(dt)
    dt = dt or defaultDeltaTime
    local dtNormalised = dt / defaultDeltaTime

    local members = self.members
    for memberIndex = 1, #members do
        local member = members[memberIndex]
        local style = member.element.style

        if style.scrollHorizontal or style.scrollVertical then

            -- Cap velocity to max speed
            if math.abs(member.scrollVelocityX) > papayui.scrollSpeed then
                member.scrollVelocityX = member.scrollVelocityX > 0 and papayui.scrollSpeed or -papayui.scrollSpeed
            end
            if math.abs(member.scrollVelocityY) > papayui.scrollSpeed then
                member.scrollVelocityY = member.scrollVelocityY > 0 and papayui.scrollSpeed or -papayui.scrollSpeed
            end

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
            local minScrollX, minScrollY, maxScrollX, maxScrollY = member:getScrollLimits()
            if member.scrollY > maxScrollY then
                member.scrollVelocityY = 0
                member.scrollY = maxScrollY
            end
            if member.scrollY < minScrollY then
                member.scrollVelocityY = 0
                member.scrollY = minScrollY
            end
            if member.scrollX > maxScrollX then
                member.scrollVelocityX = 0
                member.scrollX = maxScrollX
            end
            if member.scrollX < minScrollX then
                member.scrollVelocityX = 0
                member.scrollX = minScrollX
            end
        end
    end
end

--------------------------------------------------
--- ### UI:refresh()
--- Redraws the entire UI.  
---
--- If any changes were made that affect positioning (such as papayui.scale or changing the elements' sizes or layouts), this method needs to be called to apply those changes to the UI.  
--- Scrolling does not need to have refresh called.
---
--- The function only regenerates members when it needs to. If all of the UI's children stay the exact same, the actual member instances won't be overwritten by new ones, therefore remembering things like scrolling.
function UI:refresh()
    local rootMember = self.members[1]
    if not rootMember then return end

    self.members = {}

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
end

local dirEnum = { left = 1, up = 2, right = 3, down = 4 }
--------------------------------------------------
--- ### UI:navigate(direction)
--- Instructs the UI to change the currently selected element
---@param direction "left"|"up"|"right"|"down"
function UI:navigate(direction)
    local selectedMember = self.selectedMember
    if not selectedMember then
        self:select(self:findDefaultSelectable(), true)
        return
    end

    local dir = dirEnum[direction]
    if not dir then error("Invalid direction: " .. tostring(direction), 2) end

    -- todo: user defined navigation

    local nextSelected = selectedMember:forwardNavigation(selectedMember, dir)
    self:select(nextSelected or selectedMember, true)
end

--------------------------------------------------
--- ### UI:updateCursor(x, y)
--- Updates the input cursor location
---@param x number
---@param y number
function UI:updateCursor(x, y)
    if x == self.cursorX and y == self.cursorY then return end
    local xPrevious = self.cursorX
    local yPrevious = self.cursorY
    self.cursorX = x
    self.cursorY = y

    if self.actionDown then
        self:select()

        if papayui.touchScrollingEnabled then
            local hoveredMember = self.touchDraggedMember or self:findMemberAtCoordinate(x, y)
            if hoveredMember then hoveredMember:scrollRecursively(x - xPrevious, y - yPrevious, false, 1) end
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
            if member:isSelectable() then
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
    self.actionDown = true
end

--------------------------------------------------
--- ### UI:actionRelease()
--- Tells the UI that the action key has been released
function UI:actionRelease()
    self.actionDown = false
    self.touchDraggedMember = nil
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
    return self:scrollAt(self.cursorX, self.cursorY, scrollX, scrollY, ignoreVelocity)
end

--------------------------------------------------
--- ### UI:scrollAt(x, y, scrollX, scrollY, ignoreVelocity)
--- Tells the UI to scroll at a specific location.  
--- For most purposes, UI:scroll() will suffice, as it scrolls at the current cursor position.
---@param x number The X position to scroll at
---@param y number The Y position to scroll at
---@param scrollX? number The amount to scroll in the X axis
---@param scrollY? number The amount to scroll in the Y axis
---@param ignoreVelocity? boolean If true, no velocity is applied, and the scroller is moved instantly.
---@param speed? number Optionally override the scrolling speed
function UI:scrollAt(x, y, scrollX, scrollY, ignoreVelocity, speed)
    scrollX = scrollX or 0
    scrollY = scrollY or 0

    local cursorX, cursorY = x, y

    for memberIndex = #self.members, 1, -1 do
        if scrollX == 0 and scrollY == 0 then break end

        local member = self.members[memberIndex]
        local memberX, memberY, memberWidth, memberHeight = member:getCroppedBounds()

        local cursorInBounds = cursorX > memberX and cursorY > memberY and cursorX < memberX + memberWidth and cursorY < memberY + memberHeight

        if cursorInBounds then
            local scrolledX, scrolledY = member:scroll(scrollX, scrollY, ignoreVelocity, speed)
            if scrolledX then scrollX = 0 end
            if scrolledY then scrollY = 0 end
        end
    end
end

--------------------------------------------------
--- ### UI:select(member)
--- Used internally but can also be used externally, however note that the function takes the instanced PapayuiLiveMember as the input, not a PapayuiElement.
---
--- Makes the member considered selected by the UI. If no member is supplied, the currently selected member gets deselected.  
--- Can optionally scroll elements to put the newly selected element into view.
---@param member? PapayuiLiveMember The member to select
---@param scrollToView? boolean Whether or not to scroll the selected element into view
function UI:select(member, scrollToView)
    self.selectedMember = member
    self.lastSelection = member or self.lastSelection

    if scrollToView and member then member:scrollToView() end
end

--------------------------------------------------
--- ### UI:findMember(elementOrFunction)
--- Finds and returns a PapayuiLiveMember.  
---
--- * When supplied with a PapayuiElement, returns the member instanced from that element.  
--- * When supplied with a function, the function gets called on each member, passing the member into the function, and returns the element the function returns true for.
---@param elementOrFunction PapayuiElement|fun(member: PapayuiLiveMember): boolean
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
--- Returns the first selectable member it finds. Used internally.
---@return PapayuiLiveMember?
function UI:findDefaultSelectable()
    if self.lastSelection then
        local _, _, croppedWidth, croppedHeight = self.lastSelection:getCroppedBounds()
        if croppedWidth > 0 and croppedHeight > 0 then return self.lastSelection end
    end

    local bestCandidate = nil
    local bestCandidateImportance = -math.huge

    local members = self.members
    for memberIndex = 1, #members do
        local member = members[memberIndex]
        local _, _, croppedWidth, croppedHeight = member:getCroppedBounds()

        if member:isSelectable() and croppedWidth > 0 and croppedHeight > 0 then
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
---@return PapayuiLiveMember?
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
---@param member PapayuiLiveMember
---@return boolean
function UI:memberIsPresent(member)
    local members = self.members
    for memberIndex = 1, #members do
        if members[memberIndex] == member then return true end
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
-- Some are exported by the module since they could be useful

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

--- Used internally by the library.  
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

--- Used internally by the library.  
---
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

---@param parentMember PapayuiLiveMember
---@return PapayuiLiveMember[]
local function generateChildMembers(parentMember)
    local elements = parentMember.element.children
    local previousChildren = parentMember.children
    local elementsAreIdentical = parentMember:childElementsAreIdentical(elements)

    parentMember.children = {}

    ---@type PapayuiLiveMember[]
    local members = {}
    for elementIndex = 1, #elements do
        local element = elements[elementIndex]

        local member
        if elementsAreIdentical then
            member = previousChildren[elementIndex]
            member:resetBounds(0, 0)
            member.nav = {}
        else
            member = papayui.newLiveMember(element, 0, 0, parentMember)
        end

        members[elementIndex] = member
        parentMember.children[elementIndex] = member
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
    local originX = parentMember.x + style.padding[1]
    local originY = parentMember.y + style.padding[2]
    local gap = flipAxis and style.gap[2] or style.gap[1]

    local alignHorizontal = alignEnum[style.alignHorizontal]
    local alignVertical = alignEnum[style.alignVertical]
    local alignInside = alignEnum[style.alignInside]
    local usableSpaceWidth = parentMember.width - style.padding[1] - style.padding[3]
    local usableSpaceHeight = parentMember.height - style.padding[2] - style.padding[4]

    local outMembers = generateChildMembers(parentMember)
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
    local generatedMembers = generateChildMembers(parentMember)
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
        scrollVelocityX = 0,
        scrollVelocityY = 0,
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

--- Gets the area this member takes up (before any cropping by other members)
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
---@param highestParent? PapayuiLiveMember If supplied, this member will be considered the root member, and its parents' crop values won't be considered
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
---@param highestParent? PapayuiLiveMember If supplied, this member will be considered the root member, and its parents' crop values won't be considered
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
end

--- Checks if the member's children are of the same instances and in the same order as the input elements
---@param elements PapayuiElement[]
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
    if self.element.style.colorHover then return true end
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
---@param ignoreVelocity? boolean If true, no velocity is applied, and the scroller is moved instantly.
---@param speed? number Optionally override the scrolling speed
---@return boolean scrolledX
---@return boolean scrolledY
function LiveMember:scroll(scrollX, scrollY, ignoreVelocity, speed)
    scrollX = scrollX or 0
    scrollY = scrollY or 0
    speed = speed or papayui.scrollSpeedStep * papayui.scale

    local style = self.element.style

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
        if ignoreVelocity then self.scrollX = currentScrollX + cappedScrollX
        else self.scrollVelocityX = self.scrollVelocityX + strength end
        scrolledX = true
    end

    if canScrollY then
        local strength = speed * scrollY
        if ignoreVelocity then self.scrollY = currentScrollY + cappedScrollY
        else self.scrollVelocityY = self.scrollVelocityY + strength end
        scrolledY = true
    end

    return scrolledX, scrolledY
end

--- Attempts to scroll the member, or recursively tries the same on its parent elements if it can't.
---@param scrollX? number The amount to scroll in the X axis
---@param scrollY? number The amount to scroll in the Y axis
---@param ignoreVelocity? boolean If true, no velocity is applied, and the scroller is moved instantly.
---@param speed? number Optionally override the scrolling speed
function LiveMember:scrollRecursively(scrollX, scrollY, ignoreVelocity, speed)
    scrollX = scrollX or 0
    scrollY = scrollY or 0

    local member = self
    while member and (scrollX ~= 0 or scrollY ~= 0) do
        local scrolledX, scrolledY = member:scroll(scrollX, scrollY, ignoreVelocity, speed)
        if scrolledX then scrollX = 0 end
        if scrolledY then scrollY = 0 end
        member = member.parent
    end
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

        -- Only crop the elements up to the initial element's inner area, higher parents can't be taken into account
        local croppedX, croppedY, croppedWidth, croppedHeight = member:getCroppedBounds(self)

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