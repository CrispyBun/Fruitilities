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
--- ### inputoad.mapInput(input, action)
--- Maps an input to the given action.  
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