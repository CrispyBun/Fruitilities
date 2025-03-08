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

--- The Format wrapped into an interface only intended for encoding/decoding, not implementing
---@class Parsimmon.WrappedFormat
---@field format Parsimmon.Format
local WrappedFormat = {}
local WrappedFormatMT = {__index = WrappedFormat}

--- A specification and methods for encoding and decoding some string format.
---@class Parsimmon.Format
---@field modules table<string, Parsimmon.ConvertorModule>
---@field entryModuleName string The module that will first be called when encoding/decoding (default is "Entry")
local Format = {}
local FormatMT = {__index = Format}

--- A state machine module for decoding a part of a Format.
---@class Parsimmon.ConvertorModule
---@field decodingStates table<string, Parsimmon.DecoderStateFn> The states this module can be in when decoding and a function for what to do in that state. All modules have a 'start' state.
local Module = {}
local ModuleMT = {__index = Module}

--- The function that decides what to do in a given decoder state in a module.
--- 
--- Receives:
--- * the character it's currently acting on (can be an empty string if the end of the input string is reached),
--- * the module's `ModuleStatus`,
--- * and any potential value passed from another (or the same) module.
--- 
--- Returns a keyword (`NextModuleKeyword`) specifying how to do the next module change after this function is done executing.
--- The second return value depends on the `NextModuleKeyword` used, and can either specify the type of module change, or be used as the passedValue passed into the function in the next executed module.
--- If this is the Entry module and it executes ":BACK", the second argument is the final decoded value.
---@alias Parsimmon.DecoderStateFn fun(currentChar: string, status: Parsimmon.ModuleStatus, passedValue: any): Parsimmon.NextModuleKeyword, any

---@alias Parsimmon.NextModuleKeyword
---|'":BACK"' # Goes back to the previous module in the stack (second argument is passed to the module)
---|'":CONSUME+BACK"' # Consumes the current character and goes back to the previous module in the stack (second argument is passed to the module)
---|'":CONSUME"' # Consumes the current character and stays in the same module (second argument is passed to the module)
---|'":CURRENT"' # Does not consume the current character and stays in the same module (second argument is passed to the module)
---|'":FORWARD"' # Appends the module with the name specified by second argument to the stack of modules and moves execution to it
---|'":CONSUME+FORWARD"' # Consumes the current character, appends the module with the name specified by second argument to the stack of modules and moves execution to it
---|'":ERROR"' # Throws an error. The second argument will be used as the error message.

--- Info about the status of an active module.
---@class Parsimmon.ModuleStatus
---@field module Parsimmon.ConvertorModule The module the status belongs to. This shouldn't ever be manually set, and is considered read-only.
---@field nextState string The next state the module will switch into when the module is called again
---@field memory any A field for the module to save small values it needs to keep track of when encoding/decoding
---@field intermediate any A field for the module to save an intermediate output value as it's in the process of being created when encoding/decoding
local ModuleStatus = {}
local ModuleStatusMT = {__index = ModuleStatus}

-- Utility -----------------------------------------------------------------------------------------

---@param inputStr string
---@param i integer
---@param errMessage string
local function throwParseError(inputStr, i, errMessage)
    local line = 1
    local column = 0
    local doLineBreak = false
    for charIndex = 1, i do
        column = column + 1

        if doLineBreak then
            doLineBreak = false
            line = line + 1
            column = 1
        end

        if inputStr:sub(charIndex, charIndex) == "\n" then
            doLineBreak = true
        end
    end
    local char = inputStr:sub(i,i)
    if char == "\n" then
        char = "\\n"
    end
    error("Parse error near '" .. char .. "' at line " .. line .. " column " .. column .. ": " .. errMessage, 4)
end

---@param t table
---@param chars string
---@param value any
function parsimmon.addCharsToTable(t, chars, value)
    for charIndex = 1, #chars do
        local char = chars:sub(charIndex, charIndex)
        t[char] = value
    end
end

parsimmon.charMaps = {}

-- Whitespace characters
parsimmon.charMaps.whitespace = {
    [" "] = true,
    ["\n"] = true,
    ["\r"] = true,
    ["\t"] = true,
    ["\v"] = true,
    ["\f"] = true,
}

-- Generic set of characters that can probably act as a terminator when reading a value in most formats
parsimmon.charMaps.terminating = {
    [""] = true,
    [" "] = true,
    ["\n"] = true,
    ["\r"] = true,
    ["\t"] = true,
    ["\v"] = true,
    ["\f"] = true,
    [","] = true,
    [":"] = true,
    [";"] = true,
    ["="] = true,
    ["{"] = true,
    ["}"] = true,
    ["["] = true,
    ["]"] = true,
    ["("] = true,
    [")"] = true,
    ["<"] = true,
    [">"] = true,
}

-- Characters which can generally be present after a backslash in strings containing a specific meaning
parsimmon.charMaps.escapedMeanings = {
    ["n"] = "\n",
    ["r"] = "\r",
    ["t"] = "\t",
    ["v"] = "\v",
    ["f"] = "\f",
    ["a"] = "\a",
    ["\\"] = "\\",
    ['"'] = '"',
}

-- Format creation ---------------------------------------------------------------------------------

--- Creates a new format encoder/decoder for defining how to parse a new format unknown by the library.
---@return Parsimmon.Format
function parsimmon.newFormat()
    -- new Parsimmon.Format
    local format = {
        modules = {},
        entryModuleName = "Entry"
    }
    return setmetatable(format, FormatMT)
end

--- Decodes the given string as specified by the format.
---@param str string
---@return any
function Format:decode(str)
    local startModule = self.modules[self.entryModuleName]
    if not startModule then error("Entry module '" .. tostring(self.entryModuleName) .. "' is not present in the Format") end

    ---@type Parsimmon.ModuleStatus[]
    local stack = {parsimmon.newModuleStatus(startModule)}

    local charIndex = 1
    local passedValue
    while #stack > 0 do
        local incrementChar
        incrementChar, passedValue = self:feedNextDecodeChar(stack, str, charIndex, passedValue)
        charIndex = incrementChar and (charIndex + 1) or (charIndex)
    end

    -- TODO: we just exited, but we might not be at the end of the string.
    -- add configurable boolean (probably true by default) to format,
    -- which says whether or not we should error if we aren't at the end of the string here.

    return passedValue
end
Format.parse = Format.decode

--- Feeds the next character into an in-progress decoding stack of ModuleStatuses. Used internally.
---@private
---@param stack Parsimmon.ModuleStatus[]
---@param inputStr string
---@param charIndex integer
---@param passedValue any
---@return boolean incrementChar
---@return any passedValue
function Format:feedNextDecodeChar(stack, inputStr, charIndex, passedValue)
    if #stack == 0 then
        error("Stack of statuses is empty", 2)
    end

    local currentChar = inputStr:sub(charIndex, charIndex)

    local currentModuleStatus = stack[#stack]
    local module = currentModuleStatus.module
    local moduleState = currentModuleStatus.nextState

    local decoderStateFn = module.decodingStates[moduleState]
    if not decoderStateFn then error("A module is attempting to switch to undefined decoder state: " .. tostring(moduleState)) end

    local nextModuleKeyword
    nextModuleKeyword, passedValue = decoderStateFn(currentChar, currentModuleStatus, passedValue)

    if nextModuleKeyword == ":BACK" then
        stack[#stack] = nil
        return false, passedValue
    end

    if nextModuleKeyword == ":CONSUME+BACK" then
        stack[#stack] = nil
        return true, passedValue
    end

    if nextModuleKeyword == ":CONSUME" then
        return true, passedValue
    end

    if nextModuleKeyword == ":CURRENT" then
        return false, passedValue
    end

    if nextModuleKeyword == ":ERROR" then
        throwParseError(inputStr, charIndex, tostring(passedValue))
    end

    if nextModuleKeyword == ":FORWARD" or nextModuleKeyword == ":CONSUME+FORWARD" then
        local consumed = nextModuleKeyword == ":CONSUME+FORWARD"

        passedValue = tostring(passedValue)
        local nextModule = self.modules[passedValue]
        if not nextModule then error("Some module in state '" .. tostring(moduleState) .. "' is attempting to forward to undefined module '" .. passedValue .. "' in the format") end

        stack[#stack+1] = parsimmon.newModuleStatus(nextModule)
        return consumed
    end

    error("Some module in state '" .. tostring(moduleState) .. "' is attempting to execute undefined keyword: " .. tostring(nextModuleKeyword))
end

--- Defines a new encoding/decoding module for the format.
---@param name string
---@param module Parsimmon.ConvertorModule
---@return self self
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
---@return self self
function Module:defineDecodingState(stateName, stateFn)
    self.decodingStates[stateName] = stateFn
    return self
end

-- ModuleStatus creation (for ConvertorModules) ----------------------------------------------------

--- Creates a new ModuleStatus for an active module. This is used internally by Formats to initialize the ModuleStatuses.
---@param module Parsimmon.ConvertorModule The module this ModuleStatus belongs to
---@return Parsimmon.ModuleStatus
function parsimmon.newModuleStatus(module)
    -- new Parsimmon.ModuleStatus
    local status = {
        module = module,
        nextState = "start",
        memory = nil,
        intermediate = nil
    }
    return setmetatable(status, ModuleStatusMT)
end

--- Sets the state the module will change into the next time this module is visited.
---@param nextState string
---@return self self
function ModuleStatus:setNextState(nextState)
    self.nextState = nextState
    return self
end

-- Wrapped format ----------------------------------------------------------------------------------

--- Wraps a format implementation into an interface only intended for encoding/decoding using the format.
---@param format Parsimmon.Format
function parsimmon.wrapFormat(format)
    -- new Parsimmon.WrappedFormat
    local wrapped = {
        format = format
    }
    return setmetatable(wrapped, WrappedFormatMT)
end

--- Decodes the given string as specified by the format.
---@param str string
---@return any
function WrappedFormat:decode(str)
    return self.format:decode(str)
end

-- Useful convertor module implementations ---------------------------------------------------------

-- Handy utility modules that can be useful in any format
parsimmon.genericModules = {}

-- Module for decoding, consumes whitespace and goes back when it finds a non-whitespace character
parsimmon.genericModules.consumeWhitespace = parsimmon.newConvertorModule()
    :defineDecodingState("start", function (currentChar, status, passedValue)
        if parsimmon.charMaps.whitespace[currentChar] then
            return ":CONSUME"
        end
        return ":BACK"
    end)

-- Module for decoding, concatenates the incoming chars one by one
-- until it reaches a character from `parsimmon.charMaps.terminating`,
-- after which it will go back, returning the concatenated string.
parsimmon.genericModules.concatUntilTerminating = parsimmon.newConvertorModule()
    :defineDecodingState("start", function (currentChar, status, passedValue)
        status.intermediate = status.intermediate or ""
        if parsimmon.charMaps.terminating[currentChar] then
            return ":BACK", status.intermediate
        end
        status.intermediate = status.intermediate .. currentChar
        return ":CONSUME"
    end)

----------------------------------------------------------------------------------------------------
-- Format implementations !!! (this will get a bit messy)
----------------------------------------------------------------------------------------------------

-- You can use these as inspiration for writing your own implementations of other formats.
-- 
-- At a first glance, it may seem the way to write these is incredibly messy and hard to read,
-- which is because it is.
-- 
-- But I feel that once you get into the zone of thinking in terms of a state machine (called a module here)
-- switching states and forwarding execution to other state machines, it can get pretty intuitive to write.
--
-- The basic thing to work with is - status to manage states within the state machine,
-- returned keywords to consume characters and to manage which state machine gets executed next.
-- Execution forwarded to another state machine appends the state machine to the stack, so that when it returns, it'll go back to the current state machine.

--- Implemented formats ready to be used :-)
parsimmon.formats = {}

----- JSON -----

local JSONEntry = parsimmon.newConvertorModule()
local JSONAny = parsimmon.newConvertorModule()
local JSONNumber = parsimmon.newConvertorModule()
local JSONString = parsimmon.newConvertorModule()
local JSONLiteral = parsimmon.newConvertorModule()
local JSONArray = parsimmon.newConvertorModule()
local JSONObject = parsimmon.newConvertorModule()

local jsonSymbols = {}
parsimmon.addCharsToTable(jsonSymbols, "-0123456789", "Number")
parsimmon.addCharsToTable(jsonSymbols, '"', "String")
parsimmon.addCharsToTable(jsonSymbols, "[", "Array")
parsimmon.addCharsToTable(jsonSymbols, "{", "Object")
parsimmon.addCharsToTable(jsonSymbols, "AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz", "Literal")

JSONEntry
    :defineDecodingState("start", function (currentChar, status, passedValue)
        status:setNextState("parse")
        return ":FORWARD", "ConsumeWhitespace"
    end)
    :defineDecodingState("parse", function (currentChar, status, passedValue)
        status:setNextState("finish")
        return ":FORWARD", "Any"
    end)
    :defineDecodingState("finish", function (currentChar, status, passedValue)
        status.intermediate = passedValue
        status:setNextState("return")
        return ":FORWARD", "ConsumeWhitespace"
    end)
    :defineDecodingState("return", function (currentChar, status, passedValue)
        if currentChar ~= "" then
            return ":ERROR", "Unexpected non-whitespace character after data: " .. tostring(currentChar)
        end
        return ":BACK", status.intermediate
    end)

JSONAny
    :defineDecodingState("start", function (currentChar, status, passedValue)
        local nextModule = jsonSymbols[currentChar]
        if currentChar == "" then return ":ERROR", "Expected value but reached end of input string" end
        if not nextModule then return ":ERROR", "Unexpected symbol: " .. tostring(currentChar) end

        status:setNextState("return")
        return ":FORWARD", nextModule
    end)
    :defineDecodingState("return", function (currentChar, status, passedValue)
        return ":BACK", passedValue
    end)

JSONNumber
    :defineDecodingState("start", function (currentChar, status, passedValue)
        status:setNextState("return")
        return ":FORWARD", "ConcatUntilTerminating"
    end)
    :defineDecodingState("return", function (currentChar, status, passedValue)
        local num = tonumber(passedValue)

        if not num then return ":ERROR", "Invalid number" end
        if num == math.huge or num == -math.huge then return ":ERROR", "Invalid number" end
        if num ~= num then return ":ERROR", "Invalid number" end

        return ":BACK", num
    end)

JSONString
    :defineDecodingState("start", function (currentChar, status, passedValue)
        if currentChar ~= '"' then return ":ERROR", "Strings must start with '\"'" end
        status:setNextState("read")
        return ":CONSUME"
    end)
    :defineDecodingState("read", function (currentChar, status, passedValue)
        status.intermediate = status.intermediate or {}

        if currentChar == "\\" then
            status:setNextState("escape")
            return ":CONSUME"
        end

        if currentChar == "" then return ":ERROR", "Unterminated string" end
        if currentChar == "\n" then return ":ERROR", "Raw line breaks are not allowed in string" end
        if currentChar == '"' then return ":CONSUME+BACK", table.concat(status.intermediate) end

        status.intermediate[#status.intermediate+1] = currentChar
        return ":CONSUME"
    end)
    :defineDecodingState("escape", function (currentChar, status, passedValue)
        if currentChar == "" then return ":ERROR", "Unterminated string" end
        if currentChar == "u" then return ":ERROR", "Unicode escapes are currently unsupported" end

        local escapedChar = parsimmon.charMaps.escapedMeanings[currentChar]
        if not escapedChar then return ":ERROR", "Invalid escape character" end

        status.intermediate[#status.intermediate+1] = escapedChar
        status:setNextState("read")
        return ":CONSUME"
    end)

JSONLiteral
    :defineDecodingState("start", function (currentChar, status, passedValue)
        status:setNextState("return")
        return ":FORWARD", "ConcatUntilTerminating"
    end)
    :defineDecodingState("return", function (currentChar, status, passedValue)
        local str = passedValue
        if str == "true" then return ":BACK", true end
        if str == "false" then return ":BACK", false end
        if str == "null" then return ":BACK", nil end
        return ":ERROR", "Unknown literal: '" .. tostring(str) .. "'"
    end)

-- allows trailing commas, which JSON specification doesn't, but no matter
JSONArray
    :defineDecodingState("start", function (currentChar, status, passedValue)
        status.intermediate = {} -- array
        status.memory = 1 -- next index

        if currentChar ~= "[" then return ":ERROR", "Arrays must start with '['" end
        status:setNextState("value")
        return ":CONSUME+FORWARD", "ConsumeWhitespace"
    end)
    :defineDecodingState("value", function (currentChar, status, passedValue)
        if currentChar == "]" then
            status:setNextState("return")
            return ":CONSUME"
        end
        status:setNextState("store-value")
        return ":FORWARD", "Any"
    end)
    :defineDecodingState("store-value", function (currentChar, status, passedValue)
        status.intermediate[status.memory] = passedValue
        status.memory = status.memory + 1

        status:setNextState("comma")
        return ":FORWARD", "ConsumeWhitespace"
    end)
    :defineDecodingState("comma", function (currentChar, status, passedValue)
        if currentChar == "]" then
            status:setNextState("return")
            return ":CONSUME"
        end
        if currentChar == "," then
            status:setNextState("value")
            return ":CONSUME+FORWARD", "ConsumeWhitespace"
        end
        return ":ERROR", "Expected ',' or ']' in array"
    end)
    :defineDecodingState("return", function (currentChar, status, passedValue)
        return ":BACK", status.intermediate
    end)

-- also allows trailing commas even though it technically shouldn't, but it's fine
JSONObject
    :defineDecodingState("start", function (currentChar, status, passedValue)
        status.intermediate = {} -- object
        status.memory = nil -- next key

        if currentChar ~= "{" then return ":ERROR", "Objects must start with '{'" end
        status:setNextState("key")
        return ":CONSUME+FORWARD", "ConsumeWhitespace"
    end)
    :defineDecodingState("key", function (currentChar, status, passedValue)
        if currentChar == "}" then
            status:setNextState("return")
            return ":CONSUME"
        end
        if currentChar == '"' then
            status:setNextState("store-key")
            return ":FORWARD", "String"
        end
        return ":ERROR", "Expected '\"' or '}' in object"
    end)
    :defineDecodingState("store-key", function (currentChar, status, passedValue)
        status.memory = passedValue
        status:setNextState("colon")
        return ":FORWARD", "ConsumeWhitespace"
    end)
    :defineDecodingState("colon", function (currentChar, status, passedValue)
        if currentChar ~= ":" then
            return ":ERROR", "Expected ':' after property name in object"
        end
        status:setNextState("value")
        return ":CONSUME+FORWARD", "ConsumeWhitespace"
    end)
    :defineDecodingState("value", function (currentChar, status, passedValue)
        status:setNextState("store-value")
        return ":FORWARD", "Any"
    end)
    :defineDecodingState("store-value", function (currentChar, status, passedValue)
        status.intermediate[status.memory] = passedValue
        status.memory = nil -- clear next key

        status:setNextState("comma")
        return ":FORWARD", "ConsumeWhitespace"
    end)
    :defineDecodingState("comma", function (currentChar, status, passedValue)
        if currentChar == "}" then
            status:setNextState("return")
            return ":CONSUME"
        end
        if currentChar == "," then
            status:setNextState("key")
            return ":CONSUME+FORWARD", "ConsumeWhitespace"
        end
        return ":ERROR", "Expected ',' or '}' in object"
    end)
    :defineDecodingState("return", function (currentChar, status, passedValue)
        return ":BACK", status.intermediate
    end)

local JSON = parsimmon.newFormat()
JSON:defineModule("ConsumeWhitespace", parsimmon.genericModules.consumeWhitespace)
JSON:defineModule("ConcatUntilTerminating", parsimmon.genericModules.concatUntilTerminating)
JSON:defineModule("Entry", JSONEntry)
JSON:defineModule("Any", JSONAny)
JSON:defineModule("Number", JSONNumber)
JSON:defineModule("String", JSONString)
JSON:defineModule("Literal", JSONLiteral)
JSON:defineModule("Array", JSONArray)
JSON:defineModule("Object", JSONObject)

--- JavaScript Object Notation encoder/decoder
parsimmon.formats.JSON = parsimmon.wrapFormat(JSON)

return parsimmon