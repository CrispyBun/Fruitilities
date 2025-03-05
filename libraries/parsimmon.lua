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

--- A specification and methods for encoding and decoding some string format.
---@class Parsimmon.Format
---@field modules table<string, Parsimmon.ConvertorModule>
---@field entryModuleName string The module that will first be called when encoding/decoding (default is "start")
local Format = {}
local FormatMT = {__index = Format}

--- A module for decoding a part of a Format.
---@class Parsimmon.ConvertorModule
---@field decodingStates table<string, Parsimmon.DecoderStateFn> The states this module can be in when decoding and a function for what to do in that state. All modules have a 'start' state.
local Module = {}
local ModuleMT = {__index = Module}

--- The function that decides what to do in a given decoder state in a module.
--- 
--- Receives the character it's currently acting on (could be an empty string if the end of the input string is reached),
--- the module's `StateInfo`,
--- and any potential value passed from the previous called function.
--- 
--- Returns the next module it wants to go to, or a special module changing keyword.
--- Also can return a value to pass to the next called function. If this is the entry module returning, it will be used as the final decoded value.
---@alias Parsimmon.DecoderStateFn fun(currentChar: string, stateInfo: Parsimmon.StateInfo, passedValue: any): Parsimmon.NextModuleString, any

---@alias Parsimmon.NextModuleString
---|'":BACK"' # Goes back to the previous module in the stack
---|'":CONSUME+BACK"' # Consumes the current character and goes back to the previous module in the stack
---|'":CONSUME"' # Consumes the current character and stays in the same module
---|'":CURRENT"' # Does not consume the current character and stays in the same module
---|'":ERROR"' # Throws an error. The passedValue will be used as the error message.
---| string # Goes to the module with this name

--- Info about the state of an active module.
---@class Parsimmon.StateInfo
---@field module Parsimmon.ConvertorModule The module the state belongs to. This shouldn't ever be manually set, and is considered read-only.
---@field nextState string The next state the module will switch into when the module is called again
---@field memory any A field for the module to save small values it needs to keep track of when encoding/decoding
---@field intermediate any A field for the module to save an intermediate output value as it's in the process of being created when encoding/decoding
local StateInfo = {}
local StateInfoMT = {__index = StateInfo}

-- Utility -----------------------------------------------------------------------------------------

---@param inputStr string
---@param i integer
---@param errMessage string
local function throwParseError(inputStr, i, errMessage)
    local line = 1
    local column = 1
    for charIndex = 1, i do
        if inputStr:sub(charIndex, charIndex) == "\n" then
            line = line + 1
            column = 1
        else
            column = column + 1
        end
    end
    error("Parse error near '" .. inputStr:sub(i,i) .. "' at line " .. line .. " column " .. column .. ": " .. errMessage)
end

-- Format creation ---------------------------------------------------------------------------------

--- Creates a new format encoder/decoder for defining how to parse a new format unknown by the library.
---@return Parsimmon.Format
function parsimmon.newFormat()
    -- new Parsimmon.Format
    local format = {
        modules = {},
        entryModuleName = "start"
    }
    return setmetatable(format, FormatMT)
end

--- Decodes the given string as specified by the format.
---@param str string
---@return any
function Format:decode(str)
    local startModule = self.modules[self.entryModuleName]
    if not startModule then error("Entry module '" .. tostring(self.entryModuleName) .. "' is not present in the Format") end

    ---@type Parsimmon.StateInfo[]
    local states = {parsimmon.newStateInfo(startModule)}

    local charIndex = 1
    local passedValue
    while #states > 0 do
        local incrementChar
        incrementChar, passedValue = self:feedNextDecodeChar(states, str, charIndex, passedValue)
        charIndex = incrementChar and (charIndex + 1) or (charIndex)
    end

    -- todo: string may not be empty after this,
    -- add optional format string finalizer thing which makes sure the rest of the string is just whitespace/comments/empty.
    -- (it should still be able to consume characters one by one, so it can be a special kind of set of states)
    -- though the entry decoder state can technically deal with this too so maybe it can simply be a boolean saying if trailing characters are allowed

    return passedValue
end
Format.parse = Format.decode

--- Feeds the next character into an in-progress decoding stack of StateInfos.
---@param states Parsimmon.StateInfo[]
---@param inputStr string
---@param charIndex integer
---@param passedValue any
---@return boolean incrementChar
---@return any passedValue
function Format:feedNextDecodeChar(states, inputStr, charIndex, passedValue)
    if #states == 0 then
        error("States stack is empty", 2)
    end

    local currentChar = inputStr:sub(charIndex, charIndex)

    local currentStateInfo = states[#states]
    local module = currentStateInfo.module
    local moduleState = currentStateInfo.nextState

    local decoderStateFn = module.decodingStates[moduleState]
    if not decoderStateFn then error("A module is attempting to switch to undefined decoder state: " .. tostring(moduleState)) end

    local nextModuleString
    nextModuleString, passedValue = decoderStateFn(currentChar, currentStateInfo, passedValue)

    if nextModuleString == ":BACK" then
        states[#states] = nil
        return false, passedValue
    end

    if nextModuleString == ":CONSUME+BACK" then
        states[#states] = nil
        return true, passedValue
    end

    if nextModuleString == ":CONSUME" then
        return true, passedValue
    end

    if nextModuleString == ":CURRENT" then
        return false, passedValue
    end

    if nextModuleString == ":COLLECT" then
        error("not yet implemented")
    end

    if nextModuleString == ":ERROR" then
        throwParseError(inputStr, charIndex, tostring(passedValue))
    end

    local nextModule = self.modules[nextModuleString]
    if not nextModule then error("Attempting to enter undefined module '" .. tostring(nextModule) .. "' in the format") end

    states[#states+1] = parsimmon.newStateInfo(nextModule)
    return false, passedValue
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

-- ConvertorModule creation (for Formats) ---------------------------------------------------------

---@type Parsimmon.DecoderStateFn
local function defaultModuleDecoderStartFn(_, _, passedValue)
    error("No 'start' decoding state defined for this module")
end

--- Creates a new module for encoding/decoding parts of a Format.
---@return Parsimmon.ConvertorModule
function parsimmon.newConvertorModule()
    -- new Parsimmon.ConvertorModule
    local module = {
        decodingStates = {
            start = defaultModuleDecoderStartFn
        },
    }
    return setmetatable(module, ModuleMT)
end

--- Defines a new decoding state for the module and the function that processes it.
--- 
--- If the state already exists, it overwrites it.
--- 
--- The stateName `"start"` is the entry point of the module.
---@param stateName string
---@param stateFn Parsimmon.DecoderStateFn
---@return self
function Module:defineDecodingState(stateName, stateFn)
    self.decodingStates[stateName] = stateFn
    return self
end

-- StateInfo creation (for ConvertorModules) -------------------------------------------------------

--- Creates a new StateInfo for an active module. This is used internally by Formats to initialize the StateInfos.
---@param module Parsimmon.ConvertorModule The module this StateInfo belongs to
---@return Parsimmon.StateInfo
function parsimmon.newStateInfo(module)
    -- new Parsimmon.StateInfo
    local stateInfo = {
        module = module,
        nextState = "start",
        memory = nil,
        intermediate = nil
    }
    return setmetatable(stateInfo, StateInfoMT)
end

--- Sets the state the state info will change into the next time this module is visited.
---@param nextState string
---@return self
function StateInfo:setNextState(nextState)
    self.nextState = nextState
    return self
end

return parsimmon