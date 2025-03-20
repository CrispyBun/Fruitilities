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

-- While you could technically (with some difficulty) use this library
-- to parse Unicode strings, it's only really designed for ASCII strings.
-- This makes some formats limited at decoding if the format itself uses Unicode characters,
-- however if it doesn't, there's no limitation, as searching for ASCII characters in a Unicode string
-- is still fine and won't break up the Unicode multibyte sequences, as they can't use valid ASCII chars.
--
-- JSON is fine for example, as its valid whitespace and syntax characters only use ASCII symbols,
-- and even if the strings stored inside the JSON are Unicode, they will be parsed properly, as the
-- decoder is only searching for the quote symbol, which is valid ASCII.
-- It doesn't care if the string between those quotes is Unicode.
--
-- JSON5, on the other hand, isn't implemented fully up to its specification,
-- because it allows using some Unicode characters as whitespace, which the decoder simply won't be able to read.

local parsimmon = {}

--- Implemented formats ready to be used :-)
parsimmon.formats = {}

-- Types -------------------------------------------------------------------------------------------

--- The Format wrapped into an interface only intended for encoding/decoding, not implementing
---@class Parsimmon.WrappedFormat
---@field format Parsimmon.Format The format used for encoding/decoding. This is read-only.
---@field config table A table of configuration values which some formats may read for different purposes. This shouldn't be overwritten, only the values inside may be set.
local WrappedFormat = {}
local WrappedFormatMT = {__index = WrappedFormat}

--- A specification and methods for encoding and decoding some string format.
---@class Parsimmon.Format
---@field modules table<string, Parsimmon.ConvertorModule>
---@field entryModuleName string The module that will first be called when encoding/decoding (default is "Entry")
---@field config table Per-format configuration which the encoders and decoders may use (this shouldn't be overwritten, only the values inside may be set)
---@field _decoder? Parsimmon.ChunkDecoder An internal decoder for decoding things in one go
---@field _encoder? Parsimmon.ChunkEncoder An internal encoder for encoding things in one go
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
--- 
--- It is possible for a decoder to ouput the final value before the input string is read fully.
---@alias Parsimmon.DecoderStateFn fun(currentChar: string, status: Parsimmon.ModuleStatus, passedValue: any): Parsimmon.NextModuleDecoderKeyword, any

---@alias Parsimmon.NextModuleDecoderKeyword
---|'":BACK"' # Goes back to the previous module in the stack (second return value is passed to the module). The root (Entry) module calling this is seen as it giving the final returned decoded value and decoding can stop.
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
---|'":YIELD"' # Yields the second return value (a string) to the final output. All yields from all modules will be concatenated by parsimmon to produce the final encoded value and encoding can stop.
---|'":CURRENT"' # Keeps execution in the same module.
---|'":FORWARD"' # Forwards execution to the module with the name specified in the second return value. The third return value will be used as the `value` passed into that module to encode.
---|'":BACK"' # Returns execution back to the previous module in the stack. The root (Entry) module calling this is seen as information that the final string has been yielded.
---|'":YIELD+BACK"' # Yields the second return value to the final output and goes back to the previous module in the stack.
---|'":ERROR"' # Throws an error. The second return value will be used as the error message.

--- Info about the status of an active module.
---@class Parsimmon.ModuleStatus
---@field format Parsimmon.Format The format the module belongs to. This is here for the ability to read the format config.
---@field module Parsimmon.ConvertorModule The module the status belongs to. This shouldn't ever be manually set, and is considered read-only.
---@field nextState string The next state the module will switch into when the module is called again
---@field intermediate any A field for the module to save an intermediate output value as it's in the process of being created when encoding/decoding
---@field memory any A field for the module to save small values it needs to keep track of when encoding/decoding
---@field inheritedMemory any Similar to `ModuleStatus.memory`, but this field gets set in each new `ModuleStatus` in the stack from the previous one. Since only the reference gets copied, if a table is put into this field early on, it will essentially serve as a global memory for all the modules.
---@field valueToEncode any Only used in encoding. This is the value that gets passed as the `value` parameter for each call of the module.
local ModuleStatus = {}
local ModuleStatusMT = {__index = ModuleStatus}

--- Holds a state and allows decoding a string in chunks.
---@class Parsimmon.ChunkDecoder
---@field format Parsimmon.Format The format used for decoding
---@field stack Parsimmon.ModuleStatus[] The state
---@field passedValue any Passed value from previous state to pass to the next state
---@field firstChunkFed boolean
local ChunkDecoder = {}
local ChunkDecoderMT = {__index = ChunkDecoder}

--- Holds a state and allows encoding a value in chunks.
---@class Parsimmon.ChunkEncoder
---@field format Parsimmon.Format The format used for encoding
---@field stack Parsimmon.ModuleStatus[] The state
local ChunkEncoder = {}
local ChunkEncoderMT = {__index = ChunkEncoder}

-- Utility -----------------------------------------------------------------------------------------

---@param inputStr string
---@param i integer
---@param errMessage string
---@param unknownLineAndColumn? boolean
local function throwParseError(inputStr, i, errMessage, unknownLineAndColumn)
    if unknownLineAndColumn then
        if inputStr == "" then
            error("Parse error near end of input string: " .. errMessage, 4)
        end
        error("Parse error near '" .. inputStr:sub(i,i) .. "': " .. errMessage, 4)
    end

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
    ["/"] = true,
    ["\\"] = true,
}

-- Control characters.
-- Each is either mapped to an empty string or to how it is usually represented by escaping it.
parsimmon.charMaps.controlCharacters = {
    ["\00"] = "",
    ["\01"] = "",
    ["\02"] = "",
    ["\03"] = "",
    ["\04"] = "",
    ["\05"] = "",
    ["\06"] = "",
    ["\07"] = "\\a",
    ["\08"] = "\\b",
    ["\09"] = "\\t",
    ["\10"] = "\\n",
    ["\11"] = "\\v",
    ["\12"] = "\\f",
    ["\13"] = "\\r",
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
    ["\127"] = "",
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
        entryModuleName = "Entry",
        config = {},
    }
    return setmetatable(format, FormatMT)
end

--- Sets a single value in the config.
---@param key string
---@param value any
function Format:setConfigValue(key, value)
    self.config[key] = value
end

--- Sets a number of values in the config.
---@param values table<string, any>
function Format:setConfig(values)
    for key, value in pairs(values) do
        self.config[key] = value
    end
end

--- Decodes the given string as specified by the format.
---@param str string
---@return any
function Format:decode(str)
    local decoder = self._decoder or self:newChunkDecoder()
    self._decoder = decoder

    decoder:reset()
    decoder:continue(str)
    return decoder:finish()
end
Format.parse = Format.decode

--- Encodes the given value as specified by the format.
---@param value any
---@return string
function Format:encode(value)
    ---@type string[]
    local output = {}
    local encoder = self._encoder or self:newChunkEncoder()
    self._encoder = encoder

    encoder:reset(value)
    while true do
        local yieldedString = encoder:continue()
        if not yieldedString then return table.concat(output) end
        output[#output+1] = yieldedString
    end
end
Format.stringify = Format.encode

--- Creates a new chunk decoder that can decode a string in chunks.
---@return Parsimmon.ChunkDecoder
function Format:newChunkDecoder()
    local decoder = parsimmon.newChunkDecoder(self)
    return decoder
end

--- Creates a new chunk encoder that can encode a value in chunks.
---@param valueToEncode any
---@return Parsimmon.ChunkEncoder
function Format:newChunkEncoder(valueToEncode)
    local encoder = parsimmon.newChunkEncoder(self, valueToEncode)
    return encoder
end

--- Creates an identical copy of the format. Any config values are only shallow-copied, but modules are deep-copied.
---@return Parsimmon.Format
function Format:duplicate()
    -- new Parsimmon.Format
    local format = {
        modules = {},
        entryModuleName = self.entryModuleName,
        config = {},
    }
    for name, module in pairs(self.modules) do
        format.modules[name] = module:duplicate()
    end
    for key, value in pairs(self.config) do
        format.config[key] = value
    end
    return setmetatable(format, FormatMT)
end

--- Prepares the initial stack of ModuleStatuses for encoding or decoding.  
--- This is usually used internally unless you want to manually feed each step of the decoder/encoder for whatever reason.
---@param valueToEncode? any The initial value to encode if encoding
---@return Parsimmon.ModuleStatus[]
function Format:prepareModuleStack(valueToEncode)
    local startModule = self.modules[self.entryModuleName]
    if not startModule then error("Entry module '" .. tostring(self.entryModuleName) .. "' is not present in the Format", 2) end

    ---@type Parsimmon.ModuleStatus[]
    local stack = {parsimmon.newModuleStatus(self, startModule, nil, valueToEncode)}

    return stack
end

--- Feeds the next character into an in-progress decoding stack of ModuleStatuses.  
--- This is usually just used internally, and you should use methods like `Format:decode()` instead.
--- 
--- The format is done decoding once the stack is empty.
---@param stack Parsimmon.ModuleStatus[]
---@param inputStr string
---@param charIndex integer
---@param passedValue any
---@param unknownLineAndColumn? boolean
---@return boolean incrementChar
---@return any passedValue
function Format:feedNextDecodeChar(stack, inputStr, charIndex, passedValue, unknownLineAndColumn)
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
        throwParseError(inputStr, charIndex, tostring(passedValue), unknownLineAndColumn)
    end

    if nextModuleKeyword == ":FORWARD" or nextModuleKeyword == ":CONSUME+FORWARD" then
        local consumed = nextModuleKeyword == ":CONSUME+FORWARD"

        passedValue = tostring(passedValue)
        local nextModule = self.modules[passedValue]
        if not nextModule then error(string.format("Module '%s' in state '%s' is attempting to forward to undefined module '%s' in the format", module.name, moduleState, passedValue)) end

        stack[#stack+1] = parsimmon.newModuleStatus(self, nextModule, currentModuleStatus.inheritedMemory)
        return consumed
    end

    error(string.format("Module '%s' in state '%s' is attempting to execute undefined keyword: '%s'", module.name, tostring(moduleState), tostring(nextModuleKeyword)))
end

--- Pulses an in-progress encoding stack of ModuleStatuses.  
--- This is usually just used internally, and you should use methods like `Format:encode()` instead.
--- 
--- The format is done encoding once the stack is empty.
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

        stack[#stack+1] = parsimmon.newModuleStatus(self, nextModule, currentModuleStatus.inheritedMemory, thirdReturn)
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

--- Creates an identical copy of the module.
---@return Parsimmon.ConvertorModule
function Module:duplicate()
    -- new Parsimmon.ConvertorModule
    local module = {
        name = self.name,
        decodingStates = {},
        encodingStates = {},
    }
    for state, stateFn in pairs(self.decodingStates) do
        module.decodingStates[state] = stateFn
    end
    for state, stateFn in pairs(self.encodingStates) do
        module.encodingStates[state] = stateFn
    end
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
---@param format Parsimmon.Format The format the modules belong to
---@param module Parsimmon.ConvertorModule The module this ModuleStatus belongs to
---@param inheritedMemory? any The value to set in the `inheritedMemory` field
---@param valueToEncode? any The value to set in the `valueToEncode` field
---@return Parsimmon.ModuleStatus
function parsimmon.newModuleStatus(format, module, inheritedMemory, valueToEncode)
    -- new Parsimmon.ModuleStatus
    local status = {
        format = format,
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

-- Chunk decoders and encoders ---------------------------------------------------------------------

--- Used internally by formats. Creates a ChunkDecoder.
---@param format Parsimmon.Format
---@return Parsimmon.ChunkDecoder
function parsimmon.newChunkDecoder(format)
    -- new Parsimmon.ChunkDecoder
    local decoder = {
        format = format,
        stack = format:prepareModuleStack(),
        passedValue = nil,
        firstChunkFed = false,
    }
    return setmetatable(decoder, ChunkDecoderMT)
end

--- ### ChunkDecoder:continue(str)
--- Feeds the next chunk of the input string to the decoder.  
--- After the last chunk is fed, `ChunkDecoder:finish()` should be called.
---@param str string The next fed chunk of the input string
function ChunkDecoder:continue(str)
    local charIndex = 1
    while #self.stack > 0 and charIndex <= #str do
        local incrementChar, passedValue = self.format:feedNextDecodeChar(self.stack, str, charIndex, self.passedValue, self.firstChunkFed)
        charIndex = incrementChar and (charIndex + 1) or (charIndex)

        self.passedValue = passedValue
    end
    self.firstChunkFed = true
end
ChunkDecoder.feed = ChunkDecoder.continue
ChunkDecoder.write = ChunkDecoder.continue

--- ### ChunkDecoder:finish()
--- Tells the decoder the last chunk of the input string has been fed in and an output value is expected.
---@return any decodedValue
function ChunkDecoder:finish()
    while #self.stack > 0 do
        -- Feed empty strings (end of input) until the format finishes
        local _, passedValue = self.format:feedNextDecodeChar(self.stack, "", 1, self.passedValue, true)
        self.passedValue = passedValue
    end
    return self.passedValue
end

--- ### ChunkDecoder:reset()
--- Resets the chunk decoder so a fresh new input can be fed in.
function ChunkDecoder:reset()
    self.stack = self.format:prepareModuleStack()
    self.passedValue = nil
    self.firstChunkFed = false
end

--- Used internally by formats. Creates a ChunkEncoder.
---@param format Parsimmon.Format
---@param valueToEncode any
---@return Parsimmon.ChunkEncoder
function parsimmon.newChunkEncoder(format, valueToEncode)
    -- new Parsimmon.ChunkEncoder
    local encoder = {
        format = format,
        stack = format:prepareModuleStack(valueToEncode),
    }
    return setmetatable(encoder, ChunkEncoderMT)
end

--- ### ChunkEncoder:continue()
--- Prompts the encoder to return the next part of the string to encode. When this returns `nil`, all strings have been returned.
--- 
--- The strings are returned in the order in which they should be concatenated to construct the final encoded string.
---@return string|nil
function ChunkEncoder:continue()
    while true do
        if #self.stack == 0 then return nil end
        local yieldedString = self.format:feedNextEncodePulse(self.stack)
        if yieldedString then return yieldedString end
    end
end
ChunkEncoder.pulse = ChunkEncoder.continue

--- ### ChunkEncoder:reset(valueToEncode)
--- Resets the encoder with a new value to encode so it can start encoding again.
---@param valueToEncode any
function ChunkEncoder:reset(valueToEncode)
    self.stack = self.format:prepareModuleStack(valueToEncode)
end

-- Wrapped format ----------------------------------------------------------------------------------

--- Wraps a format implementation into an interface only intended for encoding/decoding using the format.
---@param format Parsimmon.Format
function parsimmon.wrapFormat(format)
    -- new Parsimmon.WrappedFormat
    local wrapped = {
        format = format,
        config = {}
    }
    format.config = wrapped.config
    return setmetatable(wrapped, WrappedFormatMT)
end

--- ### WrappedFormat:decode(str)
--- Decodes the given string as specified by the format.
---@param str string The string to decode
---@return any
function WrappedFormat:decode(str)
    return self.format:decode(str)
end
WrappedFormat.parse = WrappedFormat.decode

--- ### WrappedFormat:encode(value)
--- Encodes the given value as specified by the format.
---@param value any The value to encode
---@return string
function WrappedFormat:encode(value)
    return self.format:encode(value)
end
WrappedFormat.stringify = WrappedFormat.encode

--- ### WrappedFormat:newChunkDecoder()
--- Creates a new `ChunkDecoder` from the format, used for decoding a large input string in chunks.
---@return Parsimmon.ChunkDecoder
function WrappedFormat:newChunkDecoder()
    return self.format:newChunkDecoder()
end

--- ### WrappedFormat:newChunkEncoder(valueToEncode)
--- Creates a new `ChunkEncoder` from the format, used for encoding a value which will yield a large encoded string, in chunks.
---@param valueToEncode any
---@return Parsimmon.ChunkEncoder
function WrappedFormat:newChunkEncoder(valueToEncode)
    return self.format:newChunkEncoder(valueToEncode)
end

WrappedFormat.setConfigValue = Format.setConfigValue
WrappedFormat.setConfig = Format.setConfig

-- Useful convertor module implementations ---------------------------------------------------------

-- Handy utility modules that can be useful in any format
parsimmon.genericModules = {}

-- Module for decoding, consumes whitespace and goes back when it finds a non-whitespace character
parsimmon.genericModules.consumeWhitespace = parsimmon.newConvertorModule("ConsumeWhitespace")
    :defineDecodingState("start", function (currentChar, status, passedValue)
        if parsimmon.charMaps.whitespace[currentChar] then
            return ":CONSUME"
        end
        return ":BACK"
    end)
    :defineEncodingState("start", function ()
        return ":ERROR", "The consumeWhitespace module can't be used for encoding"
    end)

-- Consumes either `"\r\n"`, `"\r"`, or `"\n"`, whichever it finds. Consumes nothing if the char it receives isn't one of those characters.
parsimmon.genericModules.consumeNewline = parsimmon.newConvertorModule("ConsumeNewline")
    :defineDecodingState("start", function (currentChar, status, passedValue)
        if currentChar == "\r" then
            status:setNextState("carriage-return-start")
            return ":CONSUME"
        end
        if currentChar == "\n" then
            return ":CONSUME+BACK"
        end
        return ":BACK"
    end)
    :defineDecodingState("carriage-return-start", function (currentChar, status, passedValue)
        if currentChar == "\n" then
            return ":CONSUME+BACK"
        end
        return ":BACK"
    end)

-- Module for decoding, concatenates the incoming chars one by one
-- until it reaches a character from `parsimmon.charMaps.terminating`,
-- after which it will go back, returning the concatenated string.
parsimmon.genericModules.concatUntilTerminating = parsimmon.newConvertorModule("ConcatUntilTerminating")
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
                return ":ERROR", "Unexpected non-whitespace character after data"
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
                    return ":ERROR", "Invalid escape character"
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
            if str == "null" then return ":BACK", status.format.config.nullValue end
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

            if valueType == "nil" or valueType == "boolean" or value == status.format.config.nullValue then
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
            if value == status.format.config.nullValue then return ":YIELD+BACK", "null" end
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
    --- 
    --- The optional config property `nullValue` will replace null values to that property instead of using nils.
    --- This can for example be set to some specific table reference which you can then check as a replacement for null,
    --- to prevent values being lost completely and potential holes in arrays forming.
    --- If this value is detected in encoding (and it isn't a boolean), it will also be encoded as null.
    parsimmon.formats.JSON = parsimmon.wrapFormat(JSON)
end

do
    local JSON5 = parsimmon.formats.JSON.format:duplicate()

    --- decoding:

    local json5Symbols = {}
    parsimmon.addCharsToTable(json5Symbols, "+-.0123456789", "Number")
    parsimmon.addCharsToTable(json5Symbols, "\"\'", "String")
    parsimmon.addCharsToTable(json5Symbols, "[", "Array")
    parsimmon.addCharsToTable(json5Symbols, "{", "Object")
    parsimmon.addCharsToTable(json5Symbols, "AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz", "Literal")

    local JSON5Any = JSON5.modules.Any
    JSON5Any.name = "JSON5Any"

    local JSON5Number = JSON5.modules.Number
    JSON5Number.name = "JSON5Number"

    local JSON5String = JSON5.modules.String
    JSON5String.name = "JSON5String"

    local JSON5Literal = JSON5.modules.Literal
    JSON5Literal.name = "JSON5Literal"

    local JSON5Object = JSON5.modules.Object
    JSON5Object.name = "JSON5Object"

    local ConsumeWhitespaceAndComments = JSON5.modules.ConsumeWhitespace
    ConsumeWhitespaceAndComments.name = "ConsumeWhitespaceAndComments"

    local JSON5IdentifierName = parsimmon.newConvertorModule("JSON5IdentifierName")
    local ConsumeComment = parsimmon.newConvertorModule("ConsumeComment")

    JSON5:defineModule("IdentifierName", JSON5IdentifierName)
    JSON5:defineModule("ConsumeComment", ConsumeComment)
    JSON5:defineModule("ConsumeNewline", parsimmon.genericModules.consumeNewline)

    -- Only rewriting the states of the modules that differ from JSON:

    JSON5Any
        :defineDecodingState("start", function (currentChar, status, passedValue)
            local nextModule = json5Symbols[currentChar]
            if currentChar == "" then return ":ERROR", "Expected value but reached end of input string" end
            if not nextModule then return ":ERROR", "Unexpected symbol: " .. tostring(currentChar) end

            status:setNextState("return")
            return ":FORWARD", nextModule
        end)

    JSON5Number
        :defineDecodingState("return", function (currentChar, status, passedValue)
            local num = tonumber(passedValue)
            if not num then return ":ERROR", "Invalid number" end
            return ":BACK", num
        end)

    JSON5String
        :defineDecodingState("start", function (currentChar, status, passedValue)
            if not (currentChar == '"' or currentChar == "'") then return ":ERROR", "Strings must start with '\"' or '''" end
            status.memory = currentChar -- Remember which char needs to end the string

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
            if currentChar == status.memory then return ":CONSUME+BACK", table.concat(status.intermediate) end

            status.intermediate[#status.intermediate+1] = currentChar
            return ":CONSUME"
        end)
        :defineDecodingState("escape", function (currentChar, status, passedValue)
            if currentChar == "" then return ":ERROR", "Unterminated string" end
            if currentChar == "u" then return ":ERROR", "Unicode escapes are currently unsupported" end

            if currentChar == "\r" or currentChar == "\n" then
                status:setNextState("read")
                return ":FORWARD", "ConsumeNewline"
            end

            local escapedChar = parsimmon.charMaps.escapedMeanings[currentChar]
            escapedChar = escapedChar or currentChar

            status.intermediate[#status.intermediate+1] = escapedChar
            status:setNextState("read")
            return ":CONSUME"
        end)

    JSON5Literal
        :defineDecodingState("return", function (currentChar, status, passedValue)
            local str = passedValue
            if str == "true" then return ":BACK", true end
            if str == "false" then return ":BACK", false end
            if str == "null" then return ":BACK", status.format.config.nullValue end

            local num = tonumber(str) -- numbers can also be literals (namely nan and inf will be parsed here)
            if num then return ":BACK", num end

            return ":ERROR", "Unknown literal: '" .. tostring(str) .. "'"
        end)

    JSON5Object
        :defineDecodingState("key", function (currentChar, status, passedValue)
            if currentChar == "}" then
                status:setNextState("return")
                return ":CONSUME"
            end

            status:setNextState("store-key")
            if currentChar == '"' or currentChar == "'" then
                return ":FORWARD", "String"
            end
            return ":FORWARD", "IdentifierName"
        end)

    JSON5IdentifierName
        :defineDecodingState("start", function (currentChar, status, passedValue)
            status:setNextState("return")
            return ":FORWARD", "ConcatUntilTerminating"
        end)
        :defineDecodingState("return", function (currentChar, status, passedValue)
            if passedValue == "" then return ":ERROR", "Unexpected character" end -- just so a complete lack of identifier isn't valid
            return ":BACK", passedValue -- this allows even more characters than JSON5 allows, but that's not an issue when decoding, we're just less strict
        end)

    ConsumeWhitespaceAndComments
        :defineDecodingState("start", function (currentChar, status, passedValue)
            if parsimmon.charMaps.whitespace[currentChar] then
                return ":CONSUME"
            end
            if currentChar == "/" then
                return ":FORWARD", "ConsumeComment"
            end
            return ":BACK"
        end)

    ConsumeComment
        :defineDecodingState("start", function (currentChar, status, passedValue)
            if currentChar ~= "/" then return ":ERROR", "Comments must start with '/'" end
            status:setNextState("determine-comment-type")
            return ":CONSUME"
        end)
        :defineDecodingState("determine-comment-type", function (currentChar, status, passedValue)
            if currentChar == "/" then
                status:setNextState("single-line")
                return ":CONSUME"
            end
            if currentChar == "*" then
                status:setNextState("multi-line")
                return ":CONSUME"
            end
            return ":ERROR", "Unexpected character: '/'" -- '/' because the real unexpected character is the initial / starting the "comment"
        end)
        :defineDecodingState("single-line", function (currentChar, status, passedValue)
            if currentChar == "\n" then return ":CONSUME+BACK" end
            if currentChar == "" then return ":BACK" end
            return ":CONSUME"
        end)
        :defineDecodingState("multi-line", function (currentChar, status, passedValue)
            if currentChar == "*" then
                status:setNextState("multi-line-potential-end")
                return ":CONSUME"
            end
            if currentChar == "" then
                return ":ERROR", "Unterminated multi-line comment"
            end
            return ":CONSUME"
        end)
        :defineDecodingState("multi-line-potential-end", function (currentChar, status, passedValue)
            if currentChar == "/" then
                return ":CONSUME+BACK"
            end
            status:setNextState("multi-line")
            return ":CONSUME"
        end)

    --- decoding:

    local json5StringCharConvertor = {
        ["\\"] = "\\\\",
        ['"'] = '\\"',
        ["\n"] = "\\n",
        ["\r"] = "\\r",
        ["\b"] = "\\b",
        ["\f"] = "\\f",
        ["\t"] = "\\t",
    }

    JSON5Number
        :defineEncodingState("start", function (value, status)
            if type(value) ~= "number" then return ":ERROR", "Attempting to encode non-number into a number" end
            if value ~= value then return ":YIELD+BACK", "NaN" end
            if value == math.huge then return ":YIELD+BACK", "Infinity" end
            if value == -math.huge then return ":YIELD+BACK", "-Infinity" end
            return ":YIELD+BACK", tostring(value)
        end)

    JSON5String
        :defineEncodingState("start", function (value, status)
            if type(value) ~= "string" then return ":ERROR", "Attempting to encode non-string into a string" end

            local newString = {'"'}
            for charIndex = 1, #value do
                local char = string.sub(value, charIndex, charIndex)
                char = json5StringCharConvertor[char] or char
                newString[#newString+1] = char
            end
            newString[#newString+1] = '"'

            return ":YIELD+BACK", table.concat(newString)
        end)

    JSON5Object
        :defineEncodingState("key", function (object, status)
            local nextKey = status.memory[#status.memory]

            status:setNextState("colon")

            if string.match(nextKey, "^[_%$%a][_%$%w]*$") then
                -- the string is pure enough to look nice as an IdentifierName
                return ":YIELD", nextKey
            end
            return ":FORWARD", "String", nextKey
        end)
        :defineEncodingState("comma", function (object, status)
            if #status.memory == 0 then -- No more keys left to encode
                status:setNextState("finish")
            else
                status:setNextState("indent-key")
            end
            return ":YIELD", ",\n"
        end)

    --- JSON5 encoder/decoder  
    --- A somewhat more readable superset of JSON,
    --- which allows identifiers that aren't wrapped in quotes,
    --- trailing commas, single-quoted strings, inf and nan numbers, and some other tweaks.
    --- 
    --- The `nullValue` config field works the same as in the JSON format implementation.
    parsimmon.formats.JSON5 = parsimmon.wrapFormat(JSON5)
end

do
    local CSV = parsimmon.newFormat()

    local CSVEntry = parsimmon.newConvertorModule("CSVEntry")
    local CSVRow = parsimmon.newConvertorModule("CSVRow")
    local CSVValue = parsimmon.newConvertorModule("CSVValue")
    local CSVString = parsimmon.newConvertorModule("CSVString")
    local CSVRawText = parsimmon.newConvertorModule("CSVRawText")

    CSV:defineModule("Entry", CSVEntry)
    CSV:defineModule("Row", CSVRow)
    CSV:defineModule("Value", CSVValue)
    CSV:defineModule("String", CSVString)
    CSV:defineModule("RawText", CSVRawText)
    CSV:defineModule("ConsumeNewline", parsimmon.genericModules.consumeNewline)

    CSVEntry
        :defineDecodingState("start", function (currentChar, status, passedValue)
            status.intermediate = {} -- table[columnIndex][rowIndex]

            status:setNextState("receive-row")
            return ":FORWARD", "Row"
        end)
        :defineDecodingState("receive-row", function (currentChar, status, passedValue)
            local output = status.intermediate
            local row = passedValue

            if #output ~= 0 and #row ~= #output then -- It's impossible for any row to be completely empty ("" is still considered a single value of "", not nothing), so an output length of 0 means this is the first row
                return ":ERROR", "Mismatch in amount of values in row"
            end

            for columnIndex = 1, #row do
                -- set keys to appropriate integers or strings based on if a header is present
                -- (the header itself will still be encoded under integer keys)
                local columnKey = columnIndex
                if status.format.config.hasHeader then
                    if output[columnIndex] and output[columnIndex][1] then -- if the header is already created
                        columnKey = output[columnIndex][1]
                    end
                end

                local column = output[columnKey] or {}
                output[columnKey] = column

                column[#column+1] = row[columnIndex]
            end

            if currentChar ~= "" then
                return ":FORWARD", "Row"
            end

            status:setNextState("finish")
            return ":CURRENT"
        end)
        :defineDecodingState("finish", function (currentChar, status, passedValue)
            local output = status.intermediate

            if status.format.config.hasIdColumn then
                local idColumnKey = status.format.config.hasHeader and output[1][1] or 1
                local dontTransformNumericKeys = status.format.config.hasHeader -- If there's a header, it will be stored under numeric keys, and shouldn't be touched

                local ids = output[idColumnKey]
                if not ids then return ":BACK", output end -- Has header and only header is present, no non-header values

                -- transform all non-header and non-id fields to use the idColumn for IDs instead of integers
                for columnKey, column in pairs(output) do
                    if  columnKey ~= idColumnKey
                        and (type(columnKey) ~= "number" or not dontTransformNumericKeys)
                    then
                        for rowIndex = 1, #column do
                            local id = ids[rowIndex]
                            column[id] = column[rowIndex]
                            column[rowIndex] = nil
                        end
                    end
                end
            end

            return ":BACK", output
        end)

    CSVRow
        :defineDecodingState("start", function (currentChar, status, passedValue)
            status.intermediate = {} -- the full row
            status:setNextState("receive-value")
            return ":FORWARD", "Value"
        end)
        :defineDecodingState("receive-value", function (currentChar, status, passedValue)
            status.intermediate[#status.intermediate+1] = passedValue

            if currentChar == "," then
                return ":CONSUME+FORWARD", "Value"
            end
            if currentChar == "\r" or currentChar == "\n" then
                status:setNextState("return")
                return ":FORWARD", "ConsumeNewline"
            end
            if currentChar == "" then
                status:setNextState("return")
                return ":CURRENT"
            end

            return ":ERROR", "Unexpected character (expected comma, newline or end of file after value)"
        end)
        :defineDecodingState("return", function (currentChar, status, passedValue)
            return ":BACK", status.intermediate
        end)

    CSVValue
        :defineDecodingState("start", function (currentChar, status, passedValue)
            status:setNextState("return")

            if currentChar == '"' then
                return ":FORWARD", "String"
            end
            return ":FORWARD", "RawText"
        end)
        :defineDecodingState("return", function (currentChar, status, passedValue)
            return ":BACK", passedValue
        end)

    CSVRawText
        :defineDecodingState("start", function (currentChar, status, passedValue)
            status.intermediate = status.intermediate or ""

            if currentChar == "," or currentChar == "" or currentChar == "\r" or currentChar == "\n" then
                return ":BACK", status.intermediate
            end

            if currentChar == '"' then
                return ":ERROR", "Illegal double-quote inside unquoted CSV field"
            end

            status.intermediate = status.intermediate .. currentChar
            return ":CONSUME"
        end)

    CSVString
        :defineDecodingState("start", function (currentChar, status, passedValue)
            if currentChar ~= '"' then
                return ":ERROR", "CSV strings must start with '\"'"
            end

            status.intermediate = {}
            status:setNextState("read")
            return ":CONSUME"
        end)
        :defineDecodingState("read", function (currentChar, status, passedValue)
            if currentChar == '"' then
                status:setNextState("quote-encountered")
                return ":CONSUME"
            end
            if currentChar == "" then
                return ":ERROR", "Unterminated string"
            end
            status.intermediate[#status.intermediate+1] = currentChar
            return ":CONSUME"
        end)
        :defineDecodingState("quote-encountered", function (currentChar, status, passedValue)
            if currentChar == '"' then -- escaped
                status.intermediate[#status.intermediate+1] = currentChar
                status:setNextState("read")
                return ":CONSUME"
            end
            return ":BACK", table.concat(status.intermediate)
        end)

    --- Comma-Separated Values encoder/decoder.
    --- 
    --- Returns a table in the format `t[columnId][rowId]`.  
    --- `columnId` and `rowId` may be integers or strings based on the config (both are integers with the default config).
    ---
    --- The decoder allows a trailing newline (as per the little CSV standards that exist),
    --- meaning if the CSV only has a single column and the last row is an empty string,
    --- the last row won't be parsed as it's just considered a trailing newline.
    --- You can make sure this doesn't happen by encoding the final empty string as `""`. 
    --- 
    --- The config value `hasHeader` can be set to `true` to make the first row of the CSV string
    --- be considered a header. If this is the case, only the header will be decoded into integer keys,
    --- and all other columns will be under a string key specified by the header (non-header `columnId`s will be strings).
    --- 
    --- The config value `hasIdColumn` can be set to `true` to make the first column of the CSV string
    --- be considered a column of IDs. If this is the case, only the ID column will be an array of values,
    --- and all other columns (besides the header, if `hasHeader` is true) will be maps, mapping the
    --- ID of that row to their values instead (so non-idColumn and non-header `rowId`s will be strings).
    --- 
    --- ps. The decoding config is a bit hard to explain with just text. Sorgy.
    parsimmon.formats.CSV = parsimmon.wrapFormat(CSV)
end

return parsimmon