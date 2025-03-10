------------------------------------------------------------
-- A (somewhat) generic parsing library for readable formats
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

--- Implemented formats ready to be used :-)
parsimmon.formats = {}

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
---@field name string Name of the module, used in error messages.
---@field decodingStates table<string, Parsimmon.DecoderStateFn> The states this module can be in when decoding and a function for what to do in that state. All modules have a 'start' state.
---@field encodingStates table<string, Parsimmon.EncoderStateFn> The states this module cam be in when encoding and a function for what to do in that state. All modules have a 'start' state.
local Module = {}
local ModuleMT = {__index = Module}

--- The function that decides what to do in a given decoder state in a module.
--- 
--- Receives:
--- * the character it's currently acting on (can be an empty string if the end of the input string is reached),
--- * the module's `ModuleStatus`,
--- * and any potential value passed from another (or the same) module.
--- 
--- Returns a keyword (`NextModuleDecoderKeyword`) specifying how to do the next module change after this function is done executing.
--- The second return value depends on the `NextModuleDecoderKeyword` used, and can either specify the type of module change, or be used as the passedValue passed into the function in the next executed module.
--- If this is the Entry module and it executes ":BACK", the second argument is the final decoded value.
---@alias Parsimmon.DecoderStateFn fun(currentChar: string, status: Parsimmon.ModuleStatus, passedValue: any): Parsimmon.NextModuleDecoderKeyword, any

---@alias Parsimmon.NextModuleDecoderKeyword
---|'":BACK"' # Goes back to the previous module in the stack (second return value is passed to the module)
---|'":CONSUME+BACK"' # Consumes the current character and goes back to the previous module in the stack (second return value is passed to the module)
---|'":CONSUME"' # Consumes the current character and stays in the same module (second return value is passed to the module)
---|'":CURRENT"' # Does not consume the current character and stays in the same module (second return value is passed to the module)
---|'":FORWARD"' # Appends the module with the name specified by second return value to the stack of modules and moves execution to it
---|'":CONSUME+FORWARD"' # Consumes the current character, appends the module with the name specified by second return value to the stack of modules and moves execution to it
---|'":ERROR"' # Throws an error. The second return value will be used as the error message.

--- The function that decides what to do in a given encoder state in a module.
--- 
--- Receives:
--- * the value it's currently acting on (this is sent in from the previous module),
--- * and the module's `ModuleStatus`.
--- 
--- Returns a keyword (`NextModuleEncoderKeyword`) specifying how to do the next module change and potentially what string to yield to the output.
--- The second and third return values are used for some specific returned keywords.
---@alias Parsimmon.EncoderStateFn fun(value: any, status: Parsimmon.ModuleStatus): Parsimmon.NextModuleEncoderKeyword, string?, any

---@alias Parsimmon.NextModuleEncoderKeyword
---|'":YIELD"' # Yields the second return value (a string) to the final output. All yields from all modules will be concatenated by parsimmon to produce the final encoded value.
---|'":CURRENT"' # Keeps execution in the same module.
---|'":FORWARD"' # Forwards execution to the module with the name specified in the second return value. The third return value will be used as the `value` passed into that module to encode.
---|'":BACK"' # Returns execution back to the previous module in the stack.
---|'":YIELD+BACK"' # Yields the second return value to the final output and goes back to the previous module in the stack.
---|'":ERROR"' # Throws an error. The second return value will be used as the error message.

--- Info about the status of an active module.
---@class Parsimmon.ModuleStatus
---@field module Parsimmon.ConvertorModule The module the status belongs to. This shouldn't ever be manually set, and is considered read-only.
---@field nextState string The next state the module will switch into when the module is called again
---@field intermediate any A field for the module to save an intermediate output value as it's in the process of being created when encoding/decoding
---@field memory any A field for the module to save small values it needs to keep track of when encoding/decoding
---@field inheritedMemory any Similar to `ModuleStatus.memory`, but this field gets set in each new `ModuleStatus` in the stack from the previous one. Since only the reference gets copied, if a table is put into this field early on, it will essentially serve as a global memory for all the modules.
---@field valueToEncode any Only used in encoding. This is the value that gets passed as the `value` parameter for each call of the module.
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

local function throwEncodeError(errMessage)
    error("Error trying to encode value: " .. errMessage, 4)
end

local typeOrder = {
    ["number"] = 1,
    ["string"] = 2,
    ["boolean"] = 3,
    ["table"] = 4,
    ["function"] = 5,
    ["thread"] = 6,
    ["userdata"] = 7,
    ["nil"] = 8
}
--- Compares values of any 2 types for sorting
---@param a any
---@param b any
---@return boolean
function parsimmon.compareAnything(a, b)
    local keyTypeA = type(a)
    local keyTypeB = type(b)
    if keyTypeA ~= keyTypeB then
        return typeOrder[keyTypeA] < typeOrder[keyTypeB]
    end

    if keyTypeA == "number" or keyTypeA == "string" then
        return a < b
    end

    if keyTypeA == "table" then
        return #a < #b
    end

    return false
end

---@param a any
---@param b any
---@return boolean
function parsimmon.compareAnythingReversed(a, b)
    local keyTypeA = type(a)
    local keyTypeB = type(b)
    if keyTypeA ~= keyTypeB then
        return typeOrder[keyTypeA] > typeOrder[keyTypeB]
    end

    if keyTypeA == "number" or keyTypeA == "string" then
        return a > b
    end

    if keyTypeA == "table" then
        return #a > #b
    end

    return false
end

--- `string.rep` implemented for lua versions where it isn't natively.
--- if it is natively available, the native version will replace this.
---@param s string|number
---@param n integer
---@param sep? string|number
---@return string
function parsimmon.stringrep(s, n, sep)
    sep = sep and tostring(sep)
    local t = {}
    for i = 1, n do
        t[i] = s
    end
    return table.concat(t, sep)
end

if string.rep then parsimmon.stringrep = string.rep end

---@param t table
---@param chars string
---@param value any
function parsimmon.addCharsToTable(t, chars, value)
    for charIndex = 1, #chars do
        local char = chars:sub(charIndex, charIndex)
        t[char] = value
    end
end

-- Useful maps of certain sets of characters
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

-- Control characters.
-- Each is either mapped to an empty string or a character that is usually used after a backslash to represent it.
parsimmon.charMaps.controlCharacters = {
    ["\00"] = "",
    ["\01"] = "",
    ["\02"] = "",
    ["\03"] = "",
    ["\04"] = "",
    ["\05"] = "",
    ["\06"] = "",
    ["\07"] = "a",
    ["\08"] = "b",
    ["\09"] = "t",
    ["\10"] = "n",
    ["\11"] = "v",
    ["\12"] = "f",
    ["\13"] = "r",
    ["\14"] = "",
    ["\15"] = "",
    ["\16"] = "",
    ["\17"] = "",
    ["\18"] = "",
    ["\19"] = "",
    ["\20"] = "",
    ["\21"] = "",
    ["\22"] = "",
    ["\23"] = "",
    ["\24"] = "",
    ["\25"] = "",
    ["\26"] = "",
    ["\27"] = "",
    ["\28"] = "",
    ["\29"] = "",
    ["\30"] = "",
    ["\31"] = "",
}

-- Characters which can generally be present after a backslash to represent some different special character
parsimmon.charMaps.escapedMeanings = {
    ["n"] = "\n",
    ["r"] = "\r",
    ["t"] = "\t",
    ["v"] = "\v",
    ["f"] = "\f",
    ["a"] = "\a",
    ["b"] = "\b",
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
    local stack = self:prepareModuleStack()

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

--- Encodes the given value as specified by the format.
---@param value any
---@return string
function Format:encode(value)
    local stack = self:prepareModuleStack(value)

    ---@type string[]
    local output = {}
    while #stack > 0 do
        local yieldedString = self:feedNextEncodePulse(stack)
        if yieldedString then output[#output+1] = yieldedString end
    end

    return table.concat(output)
end

--- Prepares the initial stack of ModuleStatuses for encoding or decoding. Used internally.
---@private
---@param valueToEncode? any The initial value to encode if encoding
---@return Parsimmon.ModuleStatus[]
function Format:prepareModuleStack(valueToEncode)
    local startModule = self.modules[self.entryModuleName]
    if not startModule then error("Entry module '" .. tostring(self.entryModuleName) .. "' is not present in the Format", 2) end

    ---@type Parsimmon.ModuleStatus[]
    local stack = {parsimmon.newModuleStatus(startModule, nil, valueToEncode)}

    return stack
end

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
    if not decoderStateFn then error(string.format("Module '%s' is attempting to switch to undefined decoding state '%s'", module.name, tostring(moduleState))) end

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
        if not nextModule then error(string.format("Module '%s' in state '%s' is attempting to forward to undefined module '%s' in the format", module.name, moduleState, passedValue)) end

        stack[#stack+1] = parsimmon.newModuleStatus(nextModule, currentModuleStatus.inheritedMemory)
        return consumed
    end

    error(string.format("Module '%s' in state '%s' is attempting to execute undefined keyword: '%s'", module.name, tostring(moduleState), tostring(nextModuleKeyword)))
end

--- Pulses an in-progress encoding stack of ModuleStatuses. Used internally.
---@private
---@param stack Parsimmon.ModuleStatus[]
---@return string? yieldedString
function Format:feedNextEncodePulse(stack)
    if #stack == 0 then
        error("Stack of statuses is empty", 2)
    end

    local currentModuleStatus = stack[#stack]
    local module = currentModuleStatus.module
    local moduleState = currentModuleStatus.nextState

    local encoderStateFn = module.encodingStates[moduleState]
    if not encoderStateFn then error(string.format("Module '%s' is attempting to switch to undefined encoding state '%s'", module.name, tostring(moduleState))) end

    local nextModuleKeyword, secondReturn, thirdReturn = encoderStateFn(currentModuleStatus.valueToEncode, currentModuleStatus)

    if nextModuleKeyword == ":YIELD" then
        return tostring(secondReturn)
    end

    if nextModuleKeyword == ":YIELD+BACK" then
        stack[#stack] = nil
        return tostring(secondReturn)
    end

    if nextModuleKeyword == ":BACK" then
        stack[#stack] = nil
        return
    end

    if nextModuleKeyword == ":CURRENT" then
        return
    end

    if nextModuleKeyword == ":ERROR" then
        throwEncodeError(tostring(secondReturn))
    end

    if nextModuleKeyword == ":FORWARD" then
        secondReturn = tostring(secondReturn)
        local nextModule = self.modules[secondReturn]
        if not nextModule then error(string.format("Module '%s' in state '%s' is attempting to forward to undefined module '%s' in the format", module.name, moduleState, secondReturn)) end

        stack[#stack+1] = parsimmon.newModuleStatus(nextModule, currentModuleStatus.inheritedMemory, thirdReturn)
        return
    end

    error(string.format("Module '%s' in state '%s' is attempting to execute undefined keyword: '%s'", module.name, tostring(moduleState), tostring(nextModuleKeyword)))
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
local function defaultModuleDecoderStartFn(_, status)
    error(string.format("No 'start' decoding state defined for module '%s'", status.module.name))
end

---@type Parsimmon.EncoderStateFn
local function defaultModuleEncoderStartFn(_, status)
    error(string.format("No 'start' encoding state defined for module '%s'", status.module.name))
end

--- Creates a new module for encoding/decoding parts of a Format.
---@param name? string Name of the module
---@return Parsimmon.ConvertorModule
function parsimmon.newConvertorModule(name)
    -- new Parsimmon.ConvertorModule
    local module = {
        name = name or "Unnamed module",
        decodingStates = {
            start = defaultModuleDecoderStartFn
        },
        encodingStates = {
            start = defaultModuleEncoderStartFn
        }
    }
    return setmetatable(module, ModuleMT)
end

--- Defines a new decoding state for the module and adds the function that processes it.
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

--- Defines a new encoding state for the module and adds the function that processes it.
--- 
--- If the state already exists, it overwrites it.
--- 
--- The stateName `"start"` is the entry point of the module.
---@param stateName string
---@param stateFn Parsimmon.EncoderStateFn
---@return self self
function Module:defineEncodingState(stateName, stateFn)
    self.encodingStates[stateName] = stateFn
    return self
end

-- ModuleStatus creation (for ConvertorModules) ----------------------------------------------------

--- Creates a new ModuleStatus for an active module. This is used internally by Formats to initialize the ModuleStatuses.
---@param module Parsimmon.ConvertorModule The module this ModuleStatus belongs to
---@param inheritedMemory? any The value to set in the `inheritedMemory` field
---@param valueToEncode? any The value to set in the `valueToEncode` field
---@return Parsimmon.ModuleStatus
function parsimmon.newModuleStatus(module, inheritedMemory, valueToEncode)
    -- new Parsimmon.ModuleStatus
    local status = {
        module = module,
        nextState = "start",
        intermediate = nil,
        memory = nil,
        inheritedMemory = inheritedMemory,
        valueToEncode = valueToEncode,
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

--- ### WrappedFormat:decode(str)
--- Decodes the given string as specified by the format.
---@param str string
---@return any
function WrappedFormat:decode(str)
    return self.format:decode(str)
end

--- ### WrappedFormat:encode(value)
--- Encodes the given value as specified by the format.
---@param value any
---@return string
function WrappedFormat:encode(value)
    return self.format:encode(value)
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
    :defineEncodingState("start", function ()
        return ":ERROR", "The consumeWhitespace module can't be used for encoding"
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
    :defineEncodingState("start", function ()
        return ":ERROR", "The concatUntilTerminating module can't be used for encoding"
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

----- JSON -----
do
    -- The JSON is littered with a few comments
    -- to hopefully give an example on how to write these.

    local JSONEntry = parsimmon.newConvertorModule("JSONEntry")
    local JSONAny = parsimmon.newConvertorModule("JSONAny")
    local JSONNumber = parsimmon.newConvertorModule("JSONNumber")
    local JSONString = parsimmon.newConvertorModule("JSONString")
    local JSONLiteral = parsimmon.newConvertorModule("JSONLiteral")
    local JSONArray = parsimmon.newConvertorModule("JSONArray")
    local JSONObject = parsimmon.newConvertorModule("JSONObject")

    --- decoding:

    local jsonSymbols = {}
    parsimmon.addCharsToTable(jsonSymbols, "-0123456789", "Number")
    parsimmon.addCharsToTable(jsonSymbols, '"', "String")
    parsimmon.addCharsToTable(jsonSymbols, "[", "Array")
    parsimmon.addCharsToTable(jsonSymbols, "{", "Object")
    parsimmon.addCharsToTable(jsonSymbols, "AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz", "Literal")

    -- eats surrounding whitespaces, forwards the contents it finds to "Any"
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

    -- assumes the first char it gets is the first char of the value.
    -- determines the type based on the first symbol and forwards it to the appropriate module.
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

    -- assumes the first char it gets is the first char of the number.
    -- supports decoding some notations that JSON specs don't, like hexadecimal.
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

    -- assumes the first char is the opening quote of the string.
    JSONString
        :defineDecodingState("start", function (currentChar, status, passedValue)
            if currentChar ~= '"' then return ":ERROR", "Strings must start with '\"'" end
            status:setNextState("read")
            return ":CONSUME" -- consume the opening quote, move on to reading the string itself
        end)
        :defineDecodingState("read", function (currentChar, status, passedValue)
            status.intermediate = status.intermediate or {} -- collected chars to be concatenated at the end

            if currentChar == "\\" then
                status:setNextState("escape")
                return ":CONSUME"
            end

            if currentChar == "" then return ":ERROR", "Unterminated string" end
            if currentChar == "\n" then return ":ERROR", "Raw line breaks are not allowed in string" end
            if parsimmon.charMaps.controlCharacters[currentChar] then return ":ERROR", "Illegal control character" end
            if currentChar == '"' then return ":CONSUME+BACK", table.concat(status.intermediate) end -- consume the closing quote and return the string

            status.intermediate[#status.intermediate+1] = currentChar
            return ":CONSUME"
        end)
        :defineDecodingState("escape", function (currentChar, status, passedValue)
            if currentChar == "" then return ":ERROR", "Unterminated string" end
            if currentChar == "u" then return ":ERROR", "Unicode escapes are currently unsupported" end

            local escapedChar = parsimmon.charMaps.escapedMeanings[currentChar]
            if not escapedChar then
                if currentChar == '"' or currentChar == "/" or currentChar == "\\" then
                    escapedChar = currentChar
                else
                    if not escapedChar then return ":ERROR", "Invalid escape character" end
                end
            end

            status.intermediate[#status.intermediate+1] = escapedChar
            status:setNextState("read")
            return ":CONSUME"
        end)

    -- assumes the first char it gets is the first char of the literal.
    -- nulls are parsed as nils, which may cause things like holes in arrays or the values simply not being in the final object. this is unfortunately just a lua limitation.
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

    -- assumes the first char is the opening bracket of the array.
    -- supports decoding arrays with trailing commas, which JSON specification doesn't.
    JSONArray
        :defineDecodingState("start", function (currentChar, status, passedValue)
            status.intermediate = {} -- array
            status.memory = 1 -- next index

            if currentChar ~= "[" then return ":ERROR", "Arrays must start with '['" end
            status:setNextState("value")
            return ":CONSUME+FORWARD", "ConsumeWhitespace" -- consume the '[', forward to eating whitespace, then next char will be the value
        end)
        :defineDecodingState("value", function (currentChar, status, passedValue)
            if currentChar == "]" then -- no value, array closed instead
                status:setNextState("return")
                return ":CONSUME"
            end
            status:setNextState("store-value")
            return ":FORWARD", "Any" -- forward to parsing the value (Any)
        end)
        :defineDecodingState("store-value", function (currentChar, status, passedValue)
            status.intermediate[status.memory] = passedValue
            status.memory = status.memory + 1

            status:setNextState("comma")
            return ":FORWARD", "ConsumeWhitespace"
        end)
        :defineDecodingState("comma", function (currentChar, status, passedValue)
            if currentChar == "]" then -- no comma, array closed instead
                status:setNextState("return")
                return ":CONSUME"
            end
            if currentChar == "," then
                status:setNextState("value")
                return ":CONSUME+FORWARD", "ConsumeWhitespace" -- consume comma, consume whitespace, go back to looking for a value
            end
            return ":ERROR", "Expected ',' or ']' in array"
        end)
        :defineDecodingState("return", function (currentChar, status, passedValue)
            return ":BACK", status.intermediate
        end)

    -- assumes the first char is the opening brace of the object.
    -- supports decoding objects with trailing commas, which JSON specification doesn't.
    JSONObject
        :defineDecodingState("start", function (currentChar, status, passedValue)
            status.intermediate = {} -- object
            status.memory = nil -- next key

            if currentChar ~= "{" then return ":ERROR", "Objects must start with '{'" end
            status:setNextState("key")
            return ":CONSUME+FORWARD", "ConsumeWhitespace"
        end)
        :defineDecodingState("key", function (currentChar, status, passedValue)
            if currentChar == "}" then -- no key, object closed
                status:setNextState("return")
                return ":CONSUME"
            end
            if currentChar == '"' then
                status:setNextState("store-key")
                return ":FORWARD", "String" -- forward to parsing key (always a String)
            end
            return ":ERROR", "Expected '\"' or '}' in object"
        end)
        :defineDecodingState("store-key", function (currentChar, status, passedValue)
            status.memory = passedValue -- store next key
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
            return ":FORWARD", "Any" -- forward to parsing value (Any)
        end)
        :defineDecodingState("store-value", function (currentChar, status, passedValue)
            status.intermediate[status.memory] = passedValue
            status.memory = nil -- clear next key just for clarity

            status:setNextState("comma")
            return ":FORWARD", "ConsumeWhitespace"
        end)
        :defineDecodingState("comma", function (currentChar, status, passedValue)
            if currentChar == "}" then -- no comma, object closed
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

        --- encoding:

        local jsonStringCharConvertor = {
            ["\\"] = "\\\\",
            ['"'] = '\\"',
            ["\n"] = "\\n",
            ["\r"] = "\\r",
            ["\b"] = "\\b",
            ["\f"] = "\\f",
            ["\t"] = "\\t",
        }

        JSONEntry
            :defineEncodingState("start", function (value, status)
                status:setNextState("finish")
                return ":FORWARD", "Any", value -- just forward to Any and then return, no other processing needed
            end)
            :defineEncodingState("finish", function (value, status)
                return ":BACK"
            end)

        JSONAny
            :defineEncodingState("start", function (value, status)
                local valueType = type(value)
                status:setNextState("finish")

                if valueType == "nil" or valueType == "boolean" then
                    return ":FORWARD", "Literal", value
                end

                if valueType == "number" then
                    return ":FORWARD", "Number", value
                end

                if valueType == "string" then
                    return ":FORWARD", "String", value
                end

                if valueType == "table" then
                    local isArray = value[1] ~= nil -- this is probably the best way to guess this
                    if isArray then return ":FORWARD", "Array", value end
                    return ":FORWARD", "Object", value
                end

                return ":ERROR", string.format("Can't encode value of type '%s'", valueType)
            end)
            :defineEncodingState("finish", function ()
                return ":BACK"
            end)

        JSONNumber
            :defineEncodingState("start", function (value, status)
                if type(value) ~= "number" then return ":ERROR", "Attempting to encode non-number into a number" end
                if value == math.huge or value == -math.huge then return ":ERROR", "Can't encode infinity into a JSON number" end
                if value ~= value then return ":ERROR", "Can't encode NaN into a JSON number" end
                return ":YIELD+BACK", tostring(value)
            end)

        JSONString
            :defineEncodingState("start", function (value, status)
                if type(value) ~= "string" then return ":ERROR", "Attempting to encode non-string into a string" end

                local newString = {'"'}
                for charIndex = 1, #value do
                    local char = string.sub(value, charIndex, charIndex)

                    char = jsonStringCharConvertor[char] or char
                    if parsimmon.charMaps.controlCharacters[char] then
                        return ":ERROR", "Encoding certain control characters is currently unsupported"
                    end

                    newString[#newString+1] = char
                end
                newString[#newString+1] = '"'

                return ":YIELD+BACK", table.concat(newString)
            end)

        JSONLiteral
            :defineEncodingState("start", function (value, status)
                if value == nil then return ":YIELD+BACK", "null" end
                if value == true then return ":YIELD+BACK", "true" end
                if value == false then return ":YIELD+BACK", "false" end
                return ":ERROR", string.format("Can't encode '%s' as a literal", tostring(value))
            end)

        JSONArray
            :defineEncodingState("start", function (array, status)
                status.memory = 0 -- Current index being encoded (0 at first because we will increment it later)
                status:setNextState("value")
                return ":YIELD", "[" -- Start the array, move on to encoding the values
            end)
            :defineEncodingState("value", function (array, status)
                if status.memory >= #array then
                    return ":YIELD+BACK", "]" -- no more values
                end

                status.memory = status.memory + 1
                local nextElement = array[status.memory]

                status:setNextState("comma")
                return ":FORWARD", "Any", nextElement
            end)
            :defineEncodingState("comma", function (array, status)
                status:setNextState("value")

                if status.memory >= #array then
                    return ":CURRENT" -- Make sure we don't add a trailing comma for the last element
                end

                return ":YIELD", ", "
            end)

        JSONObject
            :defineEncodingState("start", function (object, status)
                -- Inherited memory will only be used by objects to keep track of the indentation depth
                status.inheritedMemory = (status.inheritedMemory or 0) + 1

                local keys = {}

                for key in pairs(object) do
                    if type(key) ~= "string" then
                        return ":ERROR", "Can't encode object with non-string key types or mixed key types"
                    end
                    keys[#keys+1] = key
                end

                table.sort(keys, parsimmon.compareAnythingReversed)
                status.memory = keys -- All keys we need to encode, in reversed desired order so we can pop them one by one

                if #keys == 0 then
                    return ":YIELD+BACK", "{}" -- Immediately return if the object is empty
                end

                status:setNextState("indent-key")
                return ":YIELD", "{\n"
            end)
            :defineEncodingState("indent-key", function (object, status)
                status:setNextState("key")
                return ":YIELD", parsimmon.stringrep("    ", status.inheritedMemory)
            end)
            :defineEncodingState("key", function (object, status)
                local nextKey = status.memory[#status.memory]
                status:setNextState("colon")
                return ":FORWARD", "String", nextKey
            end)
            :defineEncodingState("colon", function (object, status)
                status:setNextState("value")
                return ":YIELD", ": "
            end)
            :defineEncodingState("value", function (object, status)
                local nextKeyIndex = #status.memory -- list of table keys still to be encoded
                local nextKey = status.memory[nextKeyIndex] -- last key - the one we just encoded the key for and now need the value
                local nextValue = object[nextKey]
                status.memory[nextKeyIndex] = nil -- pop

                status:setNextState("comma")
                return ":FORWARD", "Any", nextValue
            end)
            :defineEncodingState("comma", function (object, status)
                if #status.memory == 0 then -- No more keys left to encode, finish instead of adding comma
                    status:setNextState("finish")
                    return ":YIELD", "\n"
                end
                status:setNextState("indent-key")
                return ":YIELD", ",\n"
            end)
            :defineEncodingState("finish", function (object, status)
                return ":YIELD+BACK", parsimmon.stringrep("    ", status.inheritedMemory-1) .. "}" -- final indent + closing brace
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
end

return parsimmon