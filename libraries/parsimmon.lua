------------------------------------------------------------
-- A (somewhat) generic parsing library
-- written by yours truly, CrispyBun.
-- crispybun@pm.me
-- https://github.com/CrispyBun/Fruitilities
------------------------------------------------------------
--[[
MIT License

Copyright (c) 2025 Ava "CrispyBun" Špráchalů

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
------------------------------------------------------------

local parsimmon = {}

-- Types -------------------------------------------------------------------------------------------

---@class Parsimmon.Format
---@field modules table<string, Parsimmon.ConvertorModule>
local Format = {}
local FormatMT = {__index = Format}

---@class Parsimmon.ConvertorModule
---@field decodingStates table<string, Parsimmon.DecoderStateFn>
---@field collectString boolean

---@alias Parsimmon.DecoderStateFn fun(nextChar: string, stateInfo: Parsimmon.StateInfo): Parsimmon.NextModuleString, any

---@alias Parsimmon.NextModuleString
---|'":BACK"' # Goes back to the previous module in the stack
---|'":CURRENT"' # Stays in the same module
---|'":COLLECT"' # Collects the string and stays in the same module (ignores the curent character in the collection)
---|'":COLLECTFULL"' # Like `":COLLECT"`, but also collects the current character
---| string # Goes to the module with this name

---@class Parsimmon.StateInfo
---@field private module Parsimmon.ConvertorModule The module the state belongs to
---@field nextState string The next state the module will switch into when it's returned to in the stack (this should only be set by the module itself!)
---@field collectedString string The collected string gets stored here if a module is collecting a string and calls collect

-- Format creation ---------------------------------------------------------------------------------

function parsimmon.newFormat()
    -- new Parsimmon.Format
    local format = {
        modules = {}
    }
    return setmetatable(format, FormatMT)
end

--- Defines a new encoding/decoding module for the format.
---@param name string
---@param module Parsimmon.ConvertorModule
---@return self
function Format:defineModule(name, module)
    if self.modules[name] then error("Module with name '" .. tostring(name) .. "' is already defined in this format", 2) end
    self.modules[name] = module
    return self
end

return parsimmon