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
local Format = {}
local FormatMT = {__index = Format}

--- A module for decoding a part of a Format.
---@class Parsimmon.ConvertorModule
---@field decodingStates table<string, Parsimmon.DecoderStateFn> The states this module can be in when decoding and a function for what to do in that state. All modules have a 'start' state.
---@field collectString boolean Boolean specifying whether or not this module wants to collect the string it passes over to use later. Default is `false`.
local Module = {}
local ModuleMT = {__index = Module}

--- The function that decides what to do in a given decoder state in a module.
--- 
--- Receives the character it's currently acting on, the module's `StateInfo`, and any potential value passed from the previous called function.
--- 
--- Returns the next module it wants to go to, or a special module changing keyword.
--- Also can return a value to pass to the next called function.
---@alias Parsimmon.DecoderStateFn fun(currentChar: string, stateInfo: Parsimmon.StateInfo, passedValue: any): Parsimmon.NextModuleString, any

---@alias Parsimmon.NextModuleString
---|'":BACK"' # Goes back to the previous module in the stack
---|'":CONSUME"' # Consumes the current character and stays in the same module (this is the only time a character is consumed)
---|'":CURRENT"' # Does not consume the current character and stays in the same module
---|'":COLLECT"' # Collects the accumulating string and stays in the same module (ignores the curent character in the collection)
---| string # Goes to the module with this name

--- Info about the state of an active module.
---@class Parsimmon.StateInfo
---@field module Parsimmon.ConvertorModule The module the state belongs to. This shouldn't ever be manually set, and is considered read-only.
---@field nextState string The next state the module will switch into when the module is called again
---@field collectedString? string The collected string gets stored here if a module is collecting a string and calls collect
---@field memory any A field for the module to save small values it needs to keep track of when encoding/decoding
---@field intermediate any A field for the module to save an intermediate output value as it's in the process of being created when encoding/decoding
local StateInfo = {}
local StateInfoMT = {__index = StateInfo}

-- Format creation ---------------------------------------------------------------------------------

--- Creates a new format encoder/decoder for defining how to parse a new format unknown by the library.
---@return Parsimmon.Format
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
        collectString = false
    }
    return setmetatable(module, ModuleMT)
end

--- Enables or disables the module collecting a cumulative string from the input when decoding.
--- This should only be set once.
---@param collectString boolean
---@return self
function Module:setEnableStringCollection(collectString)
    self.collectString = collectString
    return self
end

--- Defines a new decoding state for the module and the function that processes it.
--- 
--- If the state already exists, it overwrites it.
--- 
--- Two special `stateName`s are `"start"` (this is the entry point of the module) and `"end"` (this is the next queued up state if no other state is queued up instead)
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
        nextState = "end",
        collectedString = nil,
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