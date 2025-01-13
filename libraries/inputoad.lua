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
inputoad.actions = {}

--- A table mapping each action into a table of callbacks
---@type table<string, table<Inputoad.CallbackType, Inputoad.InputCallbackFn[]>>
inputoad.callbacks = {}

-- Types -------------------------------------------------------------------------------------------

---@alias Inputoad.CallbackType
---| '"pressed"' # Input was just pressed
---| '"released"' # Input was just released

---@alias Inputoad.InputCallbackFn fun()

-- Sending inputs ----------------------------------------------------------------------------------

--------------------------------------------------
--- ### inputoad.triggerPressed(input)
--- Triggers the press action on the given input (this should be called right when the user presses the input).
---@param input string
function inputoad.triggerPressed(input)
    inputoad.triggerCallbacksForInput(input, "pressed")
end

--------------------------------------------------
--- ### inputoad.triggerReleased(input)
--- Triggers the release action on the given input (this should be called right when the user releases the input).
---@param input string
function inputoad.triggerReleased(input)
    inputoad.triggerCallbacksForInput(input, "released")
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

-- Input callbacks ---------------------------------------------------------------------------------

--------------------------------------------------
--- ### inputoad.addCallback(action, callbackType, callbackFn, addToFront?)
--- Adds a callback to the given action and callback type.  
--- Can also be added to the front of the chain instead of back by setting `addToFront` to true.  
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
--- ### inputoad.triggerCallbacksForInput(input, callbackType)
--- Triggers the given callbacks. Used internally.
---@param input string
---@param callbackType Inputoad.CallbackType
function inputoad.triggerCallbacksForInput(input, callbackType)
    local actions = inputoad.actions[input]
    if not actions then return end

    for actionIndex = 1, #actions do
        local action = actions[actionIndex]
        inputoad.triggerCallbacksForAction(action, callbackType)
    end
end

--------------------------------------------------
--- ### inputoad.triggerCallbacksForAction(action, callbackType)
--- Triggers the given callbacks. Used internally.
---@param action string
---@param callbackType Inputoad.CallbackType
function inputoad.triggerCallbacksForAction(action, callbackType)
    local callbackTable = inputoad.callbacks[action]
    if not callbackTable then return end

    local callbacks = callbackTable[callbackType]
    if not callbacks then return end

    for callbackIndex = 1, #callbacks do
        local callback = callbacks[callbackIndex]
        callback() -- TODO: parameters, input consuming
    end
end

-- Mapping inputs ----------------------------------------------------------------------------------

--------------------------------------------------
--- ### inputoad.getActions(input)
--- Gets all the bound actions for a given input.
---@param input string
---@return string[]
function inputoad.getActions(input)
    local actions = inputoad.actions[input] or {}
    inputoad.actions[input] = actions
    return actions
end

--------------------------------------------------
--- ### inputoad.getInputs(action)
--- Gets all the bound inputs to the given action.
---@param action string
---@return string[]
function inputoad.getInputs(action)
    local foundInputs = {}
    for input, actions in pairs(inputoad.actions) do
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
--- ### inputoad.mapInput(input, action)
--- Maps an input to the given action. Will not map the same input to the same action twice.   
--- ```lua
--- inputoad.mapInput("W", "jump")
--- ```
---@param input string
---@param action string
function inputoad.mapInput(input, action)
    if inputoad.inputIsMappedToAction(input, action) then return end

    local actions = inputoad.getActions(input)
    actions[#actions+1] = action
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
--- ### inputoad.clearAction(action)
--- Clears all mapped inputs from the given action.
---@param action string
function inputoad.clearAction(action)
    for input in pairs(inputoad.actions) do
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
--- ### inputoad.clearAll()
--- Clears all inputs and actions to nil.
function inputoad.clearAll()
    for input in pairs(inputoad.actions) do
        inputoad.clearInput(input)
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