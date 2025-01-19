----------------------------------------------------------------------------------------------------
-- A put in its place input library
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
-- p.s. a toad fruit is a thing, so it belongs in fruitilities

local inputoad = {}

--- A table mapping real inputs to the named actions
---@type table<string, string[]>
inputoad.mappings = {}

--- A table mapping each action into a table of callbacks
---@type table<string, table<Inputoad.CallbackType, Inputoad.InputCallbackFn[]>>
inputoad.callbacks = {}

--- A list of inputs that are also considered modifiers for other inputs (such as "ctrl")
---@type string[]
inputoad.modifiers = {}

--- A table containing info about each action's state
---@type table<string, Inputoad.ActionState?>
inputoad.actionStates = {}

--- A table containing info about each raw input's state
---@type table<string, Inputoad.InputState?>
inputoad.rawInputStates = {}

--- String that separates modifiers from the raw inputs or other modifiers (creating inputs such as "ctrl%c" or "ctrl%shift%c").  
--- Must be set once before using the library (unless the default is used),
--- and must not be a string that may appear as part of a raw input.
---@type string
inputoad.modifierSeparationString = "%"

-- Types -------------------------------------------------------------------------------------------

---@alias Inputoad.CallbackType
---| '"pressed"' # Input was just pressed
---| '"released"' # Input was just released

--- The callback function to respond to input events
---@alias Inputoad.InputCallbackFn fun(action: string): Inputoad.InputCallbackReturn?

--- If the input callback function returns one of these strings, the corresponding event will be triggered
---@alias Inputoad.InputCallbackReturn
---| '"consume"' # Consumes the input, preventing any other callbacks from being triggered for this input (even for other actions)
---| '"ignore"' # Tells the library that this callback had no meaning in the current context (e.g. trying to "select all" when not editing anything), or simply that it should be ignored in the context of blocking other inputs. This can be useful if the input could otherwise block another input from triggering, if this input has a modifier.

---@class Inputoad.ActionState
---@field numPresses integer How many distinct inputs are currently pressing this action
---@field lastInput string? The last raw input that triggered this action
---@field isEnabled boolean Whether or not this action can trigger

---@class Inputoad.InputState
---@field numPresses integer How many distinct buttons are currently pressing this input
---@field isConsumed boolean Whether or not this input is currently consumed and shouldn't be triggering actions anymore
---@field modifiersPressed table<string, boolean> The modifiers that were held down when this input was pressed

-- Sending inputs ----------------------------------------------------------------------------------

--------------------------------------------------
--- ### inputoad.triggerPressed(input)
--- Triggers the press action on the given input (this should be called right when the user presses the input).
---@param input string
function inputoad.triggerPressed(input)
    inputoad.handleTriggeredInput(input, "pressed")
end

--------------------------------------------------
--- ### inputoad.triggerReleased(input)
--- Triggers the release action on the given input (this should be called right when the user releases the input).
---@param input string
function inputoad.triggerReleased(input)
    inputoad.handleTriggeredInput(input, "released")
end

--------------------------------------------------
--- ### inputoad.triggerPulse(input)
--- Triggers both the press and release action on the given input.
--- This should be used for inputs where you don't have access to the info
--- whether the user is releasing the input, only when it was pressed.
---@param input string
function inputoad.triggerPulse(input)
    inputoad.triggerPressed(input)
    inputoad.triggerReleased(input)
end

--------------------------------------------------
--- ### inputoad.resetState()
--- Resets the state of all inputs and actions, making them forget if they're currently pressed or not.  
--- 
--- This is useful to call after the inputs have been re-mapped to different actions,
--- since if that happens while some buttons are held down, it can mess up the state.
function inputoad.resetState()
    inputoad.actionStates = {}
    inputoad.rawInputStates = {}
end

-- Managing actions --------------------------------------------------------------------------------

--------------------------------------------------
--- ### inputoad.addCallback(action, callbackType, callbackFn, addToFront?)
--- Adds a callback to the given action and callback type.  
--- Can also be added to the front of the chain instead of back by setting `addToFront` to true.  
--- 
--- Note that under some conditions (consuming inputs, modified inputs triggering, disabling actions),
--- it is possible that a `"pressed"` callback is called but not the subsequent `"released"`, or vice versa.
--- If you need to know whether or not a specific action is held down, you should use `inputoad.isActionDown()` instead of callbacks.
--- ```lua
--- inputoad.addCallback("jump", "pressed", function()
---     player.yVelocity = -10
--- end)
--- 
--- ```
---@param action string
---@param callbackType Inputoad.CallbackType
---@param callbackFn Inputoad.InputCallbackFn
---@param addToFront? boolean
function inputoad.addCallback(action, callbackType, callbackFn, addToFront)
    local callbacks = inputoad.getCallbacks(action, callbackType)

    local index = addToFront and 1 or (#callbacks+1)
    return table.insert(callbacks, index, callbackFn)
end

--------------------------------------------------
--- ### inputoad.isActionDown(action)
--- Returns a boolean stating if the specified action is currently held.
---@param action string
---@return boolean
function inputoad.isActionDown(action)
    local state = inputoad.getActionState(action)

    if not state.isEnabled then
        return false
    end

    if state.lastInput and inputoad.isInputConsumed(state.lastInput) then
        return false
    end

    return state.numPresses > 0
end
inputoad.isActionHeld = inputoad.isActionDown

--------------------------------------------------
--- ### inputoad.getCallbacks(action, callbackType)
--- Gets the array of callback functions for the given action and callback type.
---@param action string
---@param callbackType Inputoad.CallbackType
---@return Inputoad.InputCallbackFn[]
function inputoad.getCallbacks(action, callbackType)
    local callbackTable = inputoad.callbacks[action] or {}
    inputoad.callbacks[action] = callbackTable

    local callbacks = callbackTable[callbackType] or {}
    callbackTable[callbackType] = callbacks

    return callbacks
end

--------------------------------------------------
--- ### inputoad.setActionEnabled(action, enabled)
--- Sets if the action is enabled or disabled (disabled actions won't trigger).
---@param action string
---@param enabled boolean
function inputoad.setActionEnabled(action, enabled)
    inputoad.getActionState(action).isEnabled = enabled
end

--------------------------------------------------
--- ### inputoad.enableAction(action)
--- Enables the given action if it was previously disabled.
---@param action string
function inputoad.enableAction(action)
    return inputoad.setActionEnabled(action, true)
end

--------------------------------------------------
--- ### inputoad.disableAction(action)
--- Disables the action, making it not trigger until it's enabled again.
---@param action string
function inputoad.disableAction(action)
    return inputoad.setActionEnabled(action, false)
end

--------------------------------------------------
--- ### inputoad.handleTriggeredInput(input, callbackType)
--- Handles the input being pressed/released (based on callbackType). Used internally.
---@param input string
---@param callbackType Inputoad.CallbackType
---@param ignoreModifiers? boolean
---@return boolean actionCalled
function inputoad.handleTriggeredInput(input, callbackType, ignoreModifiers)
    inputoad.handleInputStateForCallbackType(input, callbackType)
    local inputState = inputoad.getRawInputState(input)

    if not ignoreModifiers and inputoad.wasRawInputPressedWithModifiers(input) then
        local modifiedInput = inputoad.getModifiedInputString(input, inputState.modifiersPressed, true)
        local success = inputoad.handleTriggeredInput(modifiedInput, callbackType, true)
        if success then
            -- Successful modified input consumes the unmodified input
            -- since they are two distinct inputs that shouldn't clash
            -- (`ctrl+c` means `c` isn't triggered anymore)
            inputoad.consumeInput(input)
        end
    end

    local actions = inputoad.mappings[input]
    if not actions then return false end
    if #actions == 0 then return false end

    local allEventsWereIgnored = true

    for actionIndex = 1, #actions do
        local action = actions[actionIndex]
        inputoad.handleActionStateForCallbackType(action, input, callbackType)
        local actionState = inputoad.getActionState(action)

        if actionState.isEnabled and not inputoad.isInputConsumed(input) then
            local _, trigger = inputoad.triggerCallbacksForAction(action, callbackType)

            if trigger ~= "ignore" then
                allEventsWereIgnored = false
            end
            if trigger == "consume" then
                inputoad.consumeInput(input)
            end
        end
    end

    return not allEventsWereIgnored
end

--------------------------------------------------
--- ### inputoad.triggerCallbacksForAction(action, callbackType)
--- Triggers the given callbacks. Used internally.
---@param action string
---@param callbackType Inputoad.CallbackType
---@return boolean callbackFound
---@return Inputoad.InputCallbackReturn? callbackReturn
function inputoad.triggerCallbacksForAction(action, callbackType)
    local callbackTable = inputoad.callbacks[action]
    if not callbackTable then return false end

    local callbacks = callbackTable[callbackType]
    if not callbacks then return false end
    if #callbacks == 0 then return false end

    local allTriggersAreIgnore = true

    for callbackIndex = 1, #callbacks do
        local callback = callbacks[callbackIndex]
        local trigger = callback(action)
        if trigger == "consume" then return true, trigger end
        if trigger ~= "ignore" then allTriggersAreIgnore = false end
    end

    if allTriggersAreIgnore then return true, "ignore" end
    return true
end

--------------------------------------------------
--- ### inputoad.getActionState(action)
--- Returns the table describing the current state of the action.
---@param action string
---@return Inputoad.ActionState
function inputoad.getActionState(action)
    local state = inputoad.actionStates[action]
    if state then return state end

    state = {
        numPresses = 0,
        isEnabled = true
    }
    inputoad.actionStates[action] = state

    return state
end

--------------------------------------------------
--- ### inputoad.getRawInputState(input)
--- Returns the table describing the current state of the raw input.
function inputoad.getRawInputState(input)
    local state = inputoad.rawInputStates[input]
    if state then return state end

    state = {
        numPresses = 0,
        isConsumed = false,
        modifiersPressed = {}
    }
    inputoad.rawInputStates[input] = state

    return state
end

--- Returns a boolean of whether the raw input is currently held.  
--- This is used internally, and shouldn't really be used for getting info about user input. Instead,
--- `inputoad.isActionDown()` should be used.
---@param input string
---@return boolean
function inputoad.isRawInputDown(input)
    return inputoad.getRawInputState(input).numPresses > 0
end

--- Returns a boolean of whether any registered modifier was held down when the input was last pressed.
---@param input string
---@return boolean
function inputoad.wasRawInputPressedWithModifiers(input)
    local state = inputoad.getRawInputState(input)
    local modifiersPressed = state.modifiersPressed

    local modifiers = inputoad.modifiers
    for modifierIndex = 1, #modifiers do
        local modifier = modifiers[modifierIndex]
        if modifiersPressed[modifier] then return true end
    end
    return false
end

--- Returns a boolean of whether the given input is currently consumed (won't trigger any more actions until the next time it's pressed)
---@param input string
---@return boolean
function inputoad.isInputConsumed(input)
    return inputoad.getRawInputState(input).isConsumed
end

--- Used internally. Marks the given input as consumed for its current press.
---@param input string
function inputoad.consumeInput(input)
    inputoad.getRawInputState(input).isConsumed = true
end

---Used internally.
---@param action string
---@param input string
---@param callbackType Inputoad.CallbackType
function inputoad.handleActionStateForCallbackType(action, input, callbackType)
    local state = inputoad.getActionState(action)

    if callbackType == "pressed" then
        state.numPresses = state.numPresses + 1
        state.lastInput = input
    elseif callbackType == "released" then
        state.numPresses = state.numPresses - 1
        state.numPresses = math.max(state.numPresses, 0)
    end
end

---Used internally.
---@param input string
---@param callbackType Inputoad.CallbackType
function inputoad.handleInputStateForCallbackType(input, callbackType)
    local state = inputoad.getRawInputState(input)

    if callbackType == "pressed" then
        state.numPresses = state.numPresses + 1
        state.isConsumed = false

        local modifiersPressed = state.modifiersPressed
        local modifiers = inputoad.modifiers

        for modifierIndex = 1, #modifiers do
            local modifier = modifiers[modifierIndex]

            if inputoad.isRawInputDown(modifier) then
                modifiersPressed[modifier] = true
            else
                modifiersPressed[modifier] = false
            end
        end

    elseif callbackType == "released" then
        state.numPresses = state.numPresses - 1
        state.numPresses = math.max(state.numPresses, 0)
    end
end

-- Mapping inputs ----------------------------------------------------------------------------------

--------------------------------------------------
--- ### inputoad.getActions(input)
--- Gets all the bound actions for a given input.
---@param input string
---@return string[]
function inputoad.getActions(input)
    local actions = inputoad.mappings[input] or {}
    inputoad.mappings[input] = actions
    return actions
end

--------------------------------------------------
--- ### inputoad.getInputs(action)
--- Gets all the bound inputs to the given action.
---@param action string
---@return string[]
function inputoad.getInputs(action)
    local foundInputs = {}
    for input, actions in pairs(inputoad.mappings) do
        for _, mappedAction in ipairs(actions) do
            if mappedAction == action then
                foundInputs[#foundInputs+1] = input
                break
            end
        end
    end
    return foundInputs
end

--------------------------------------------------
--- ### inputoad.mapInput(input, action, addToFront?)
--- Maps an input to the given action. Will not map the same input to the same action twice.  
--- The action can be added to the front of the chain instead of back by setting `addToFront` to true.
--- ```lua
--- inputoad.mapInput("W", "jump")
--- ```
---@param input string
---@param action string
---@param addToFront? boolean
function inputoad.mapInput(input, action, addToFront)
    if inputoad.inputIsMappedToAction(input, action) then
        inputoad.unmapInput(input, action)
    end

    local actions = inputoad.getActions(input)
    local index = addToFront and 1 or (#actions+1)
    return table.insert(actions, index, action)
end

--------------------------------------------------
--- ### inputoad.unmapInput(input, action)
--- Unmaps an input from the specific action. 
---@param input string
---@param action string
function inputoad.unmapInput(input, action)
    local actions = inputoad.getActions(input)

    for actionIndex = #actions, 1, -1 do
        if actions[actionIndex] == action then
            table.remove(actions, actionIndex)
        end
    end
end

--------------------------------------------------
--- ### inputoad.pushActionToFront(action)
--- Pushes the action to the front of the list of actions
--- for any input where this action is found.
--- 
--- Can be useful for making sure actions that can consume the input,
--- such as UI interaction, always get called first.
---@param action string
function inputoad.pushActionToFront(action)
    for input in pairs(inputoad.mappings) do
        if inputoad.inputIsMappedToAction(input, action) then
            inputoad.mapInput(input, action, true)
        end
    end
end

--------------------------------------------------
--- ### inputoad.registerModifier(input)
--- Registers an input as a potential modifier (e.g. "ctrl").  
--- All modifiers must be registered at the start of the program.
---@param input string
function inputoad.registerModifier(input)
    local modifiers = inputoad.modifiers
    for modifierIndex = 1, #modifiers do
        if modifiers[modifierIndex] == input then
            error("Modifier '" .. tostring(input) .. "' is already registered", 2)
        end
    end
    modifiers[#modifiers+1] = input
end

local function arrayHasItem(array, item) for _, value in ipairs(array) do if item == value then return true end end return false end
--------------------------------------------------
--- ### inputoad.getModifiedInputString(input, modifiers)
--- Returns a new input string for an input that has modifiers applied (uses `inputoad.modifierSeparationString`).  
--- When mapping an input with a modifier, this function should be used to generate the input string.  
--- The order of the modifiers in the string depends on the order in which they were registered in.
--- ```lua
--- local input = inputoad.getModifiedInputString("c", { ctrl = true }) --> "ctrl%c" (or similar)
--- inputoad.mapInput(input, "copy")
--- ```
---@param input string
---@param modifiers table<string, boolean>
function inputoad.getModifiedInputString(input, modifiers, _ignoreModifierExistsCheck)
    local registeredModifiers = inputoad.modifiers

    if not _ignoreModifierExistsCheck then
        for key, value in pairs(modifiers) do
            if value and not arrayHasItem(registeredModifiers, key) then
                error("Unknown modifier (must be registered first): " .. tostring(key), 2)
            end
        end
    end

    for modifierIndex = 1, #registeredModifiers do
        local modifier = registeredModifiers[modifierIndex]
        if modifiers[modifier] then
            input = modifier .. inputoad.modifierSeparationString .. input
        end
    end
    return input
end

--------------------------------------------------
--- ### inputoad.splitModifiedInputString(input)
--- Splits a string previously generated with `inputoad.getModifiedInputString()`
--- and returns the raw input key along with a table of modifiers that were applied to it.
---@param modifiedInput string
---@return string rawInputKey
---@return string[] modifiers
function inputoad.splitModifiedInputString(modifiedInput)
    local separator = inputoad.modifierSeparationString
    local parts = {}

    local searchIndex = 1
    while true do
        local startIndex, endIndex = string.find(modifiedInput, separator, searchIndex, true)
        if not (startIndex and endIndex) then break end

        parts[#parts+1] = string.sub(modifiedInput, searchIndex, startIndex-1)
        searchIndex = endIndex + 1
    end
    local rawInput = string.sub(modifiedInput, searchIndex)

    return rawInput, parts
end

--------------------------------------------------
--- ### inputoad.clearAction(action)
--- Clears all mapped inputs from the given action.
---@param action string
function inputoad.clearAction(action)
    for input in pairs(inputoad.mappings) do
        inputoad.unmapInput(input, action)
    end
end

--------------------------------------------------
--- ### inputoad.clearInput(input)
--- Clears all actions bound to the given input.
---@param input string
function inputoad.clearInput(input)
    local actions = inputoad.getActions(input)
    for actionIndex = 1, #actions do
        actions[actionIndex] = nil
    end
end

--------------------------------------------------
--- ### inputoad.clearMappings()
--- Clears all inputs and actions to nil.
function inputoad.clearMappings()
    for input in pairs(inputoad.mappings) do
        inputoad.clearInput(input)
    end
end

--------------------------------------------------
--- ### inputoad.copyMappings()
--- Returns a copy of the mappings table.
---@return table<string, string[]>
function inputoad.copyMappings()
    local copy = {}
    for input, actions in pairs(inputoad.mappings) do
        copy[input] = {}

        for actionIndex = 1, #actions do
            copy[input][actionIndex] = actions[actionIndex]
        end
    end
    return copy
end

--------------------------------------------------
--- ### inputoad.pasteMappings(mappings)
--- Assigns all the mappings to the ones in the provided table.  
--- Can paste back mappings previously copied using `inputoad.copyMappings()`.
---@param mappings table<string, string[]>
function inputoad.pasteMappings(mappings)
    inputoad.clearMappings()
    for input, actions in pairs(mappings) do
        for actionIndex = 1, #actions do
            inputoad.mapInput(input, actions[actionIndex])
        end
    end
end

--------------------------------------------------
--- ### inputoad.inputIsMappedToAction(input, action)
--- Checks if a specific input is mapped to the given action.
---@param input string
---@param action string
---@return boolean
function inputoad.inputIsMappedToAction(input, action)
    local actions = inputoad.getActions(input)
    for actionIndex = 1, #actions do
        if actions[actionIndex] == action then return true end
    end
    return false
end

return inputoad