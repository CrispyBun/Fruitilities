------------------------------------------------------------
-- A custom JSON-like format (called ARSON) parsing library
-- written by yours truly, CrispyBun.
-- crispybun@pm.me
-- https://github.com/CrispyBun/Fruitilities
------------------------------------------------------------
--[[
MIT License

Copyright (c) 2024-2025 Ava "CrispyBun" Špráchalů

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

--- Inspired by some of the ways https://github.com/rxi/json.lua does its parsing

--- ARSON - Arbitrary Structure Object Notation  
--- Compatible with JSON, allows for arbitrary custom types.
local parsimmon = {}

--- This is probably the messiest library of Fruitilities

--- Can be set to a boolean to affect if tables, when being encoded as objects, will sort their keys in the output.
---@type boolean
parsimmon.sortEncodedObjects = true

--- If true, tables, when being encoded as objects, will be made multiline to be more readable.
---@type boolean
parsimmon.splitEncodedObjectLines = true

--- If true, tables, when being encoded as objects, will wrap square brackers around string keys.
---@type boolean
parsimmon.wrapStringKeysInBrackets = false

--- Normally, all tables are parsed as objects, which can result in more verbose outputs
--- when parsing arrays. You can implement this function to detect arrays and separate them from objects.
---@type (fun(value: any): boolean)?
parsimmon.isArray = nil

-- Custom types ------------------------------------------------------------------------------------

---@type table<string, Parsimmon.CustomType>
parsimmon.customTypes = {}

---@type table<string, any>
parsimmon.customLiterals = {}

--- Parser of a single value. For inspiration on how to write these, look into the parsers in `parsimmon.parsers`.
---@alias Parsimmon.ValueParser fun(str: string, i: integer, context?: table): any, integer

--- Encoder of a single value. Custom type encoders MUST wrap the encoded value in squiggly brackets! ('{' and '}')
---@alias Parsimmon.ValueEncoder fun(value: any, context?: table): string

--- A type checker for either a type or literal (based on context).
--- Gets any value, and if it's able to find out its type, returns the string identifying that type.
---@alias Parsimmon.TypeChecker fun(value: any): string?

--- Initializer for custom types.
--- Either a function that receives any value of that custom type that was just parsed,
--- or a table which will be assigned as a metatable to any parsed values of this type.
---@alias Parsimmon.ValueInitializer fun(value: any, context?: table)|table

--- A custom type and the functions that specify how it's parsed.  
--- The parsed area must always be enclosed between `{` and `}` symbols.
--- 
--- The parser function receives the full input string, the position at which this value starts (will be pointing to the `{` symbol),
--- and potentially the context table, given by some previous parser.  
--- It must output the parsed value and the position at which it ends (the position of the ending `}` character).
---@class Parsimmon.CustomType
---@field parser Parsimmon.ValueParser The parser for this type, a function in the same format as the functions in `parsimmon.parsers`.
---@field encoder Parsimmon.ValueEncoder The encoder for this type, a function in the same format as the functions in `parsimmon.encoders`.
---@field initializer? Parsimmon.ValueInitializer The initializer for parsed values of this type
local CustomType = {}
local CustomTypeMT = {__index = CustomType}

--- Defines a new custom type. The name must be composed of letters only.  
--- If the parser and decoder values are not supplied, the default used for them will be ones used for regular objects.  
--- 
--- For custom types to also be encoded correctly, a type checker must be defined for them using `parsimmon.addTypeChecker()`.
--- Otherwise, even though they can be decoded, they won't ever be encoded.
---
--- ---
--- 
--- Example simple custom type:
--- ```lua
--- parsimmon.defineCustomType("GameObject", GameObjectMetatable)
--- 
--- parsimmon.addTypeChecker(function (value)
---     local mt = getmetatable(value)
---     if not mt then return nil end
---     -- Type checkers can also be generalized, but this one just checks one type:
---     if mt == GameObjectMetatable then return "GameObject" end
--- end)
--- ```
--- 
--- ---
--- 
--- Example advanced custom type (with custom parsing):
--- ```lua
--- -- A custom type that overrides numbers
--- local numberType = parsimmon.defineCustomType("Number")
--- 
--- numberType:setParser(function (str, i, context)
---     local j = str:find("}", i, true)
---     if not j then parsimmon.throwParseError(str, i, "Missing closing bracket for Number type") end
--- 
---     local text = string.sub(str, i+1, j-1)
---     local num = tonumber(text)
---     if not num then parsimmon.throwParseError(str, i, "Couldn't parse number: " .. tostring(text)) end
--- 
---     return num, j --[[@as integer]]
--- end)
--- 
--- numberType:setEncoder(function (value, context)
---     if type(value) ~= "number" then error("Expected number") end
---     return '{' .. tostring(value) .. '}'
--- end)
--- 
--- parsimmon.addTypeChecker(function (value)
---     if type(value) == "number" then return "Number" end
---     return nil
--- end)
--- 
--- local obj = {
---     one = 1,
---     two = 2
--- }
--- print(parsimmon.encode(obj))
--- -- {
--- --     "one": Number{1},
--- --     "two": Number{2}
--- -- }
--- ```
---@param name string The name of the type
---@param initializer? Parsimmon.ValueInitializer The init function or metatable for the type
---@return Parsimmon.CustomType type The newly created type definition
function parsimmon.defineCustomType(name, initializer)
    local parser = parsimmon.parsers.object
    local encoder = parsimmon.encoders.object

    local type = {
        parser = parser,
        encoder = encoder,
        initializer = initializer
    }
    setmetatable(type, CustomTypeMT)

    parsimmon.customTypes[name] = type
    return type
end

--- Defines a custom literal. The name must be composed of letters only.  
--- If the literal with the name `name` is found, `value` will be returned for it.  
--- 
--- For custom literals to also be encoded correctly, a type checker must be defined for them using `parsimmon.addLiteralChecker()`.
--- Otherwise, even though they can be decoded, they won't ever be encoded.
---@param name string
---@param value any
function parsimmon.defineCustomLiteral(name, value)
    parsimmon.customLiterals[name] = value
end

--- Sets an initializer for parsed values of the custom type.
--- Either a function that receives the values as they're parsed,
--- or simply a table which will be assigned as the values' metatable.
---@param initializer Parsimmon.ValueInitializer
---@return Parsimmon.CustomType self
function CustomType:setInit(initializer)
    self.initializer = initializer
    return self
end

--- Sets the type's parser. If you set this, make sure you also set the encoder.
---@param parser Parsimmon.ValueParser The parser for the type
---@return Parsimmon.CustomType self
function CustomType:setParser(parser)
    self.parser = parser
    return self
end

--- Sets the type's encoder. If you set this, make sure you also set the parser.
--- 
--- The encoder MUST wrap the encoded value in squiggly brackets.
---@param encoder Parsimmon.ValueEncoder The encoder for this type
---@return Parsimmon.CustomType self
function CustomType:setEncoder(encoder)
    self.encoder = encoder
    return self
end

-- Detecting types for encoding --------------------------------------------------------------------

---@type Parsimmon.TypeChecker[]
parsimmon.customLiteralCheckers = {}

---@type Parsimmon.TypeChecker[]
parsimmon.customTypeCheckers = {}

---@type Parsimmon.TypeChecker[]
parsimmon.defaultTypeAndLiteralCheckers = {}

-- Default types and literals:

parsimmon.defaultTypeAndLiteralCheckers[1] = function (value)
    local valueType = type(value)
    if valueType ~= "table" then return valueType end
    return nil
end
parsimmon.defaultTypeAndLiteralCheckers[2] = function (value)
    if parsimmon.isArray and parsimmon.isArray(value) then return "array" end
    return nil
end
parsimmon.defaultTypeAndLiteralCheckers[3] = function (value)
    local valueType = type(value)
    if valueType ~= "table" then return nil end
    return "object"
end

-- Custom types and literals:

--- Adds a new type checker for literals into the chain (always executed in order).
--- 
--- This is a function that receives any value that's about to be encoded,
--- and if it detects it to be some custom literal, returns the registered name of that literal.
--- 
--- ```lua
--- parsimmon.addLiteralChecker(function (value)
---     local mt = getmetatable(value)
---     if not mt then return nil end
---     if mt.__name = "MyCustomLiteral" then return "MyCustomLiteral" end
---     return nil
--- end)
--- ```
---@param typeChecker Parsimmon.TypeChecker
function parsimmon.addLiteralChecker(typeChecker)
    parsimmon.customLiteralCheckers[#parsimmon.customLiteralCheckers+1] = typeChecker
end

--- Adds a new type checker for custom types into the chain (always executed in order).
--- 
--- This is a function that receives any value that's about to be encoded,
--- and if it detects it to be some custom type, returns the registered name of that type.
--- 
--- ```lua
--- parsimmon.addTypeChecker(function (value)
---     local mt = getmetatable(value)
---     if not mt then return nil end
---     if mt.__index == myCustomType then return "MyCustomType" end
---     return nil
--- end)
--- ```
---@param typeChecker Parsimmon.TypeChecker
function parsimmon.addTypeChecker(typeChecker)
    parsimmon.customTypeCheckers[#parsimmon.customTypeCheckers+1] = typeChecker
end

-- Encoding ----------------------------------------------------------------------------------------

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
local function compareAnything(a, b)
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

---@type table<string, Parsimmon.ValueEncoder>
parsimmon.encoders = {}

parsimmon.encoders.any = function (value, context)
    local customLiteralChecks = parsimmon.customLiteralCheckers
    local customTypeChecks = parsimmon.customTypeCheckers
    local defaultTypeAndLiteralCheckers = parsimmon.defaultTypeAndLiteralCheckers

    for funIndex = 1, #customLiteralChecks do
        local out = customLiteralChecks[funIndex](value)
        if out then return out end
    end

    for funIndex = 1, #customTypeChecks do
        local out = customTypeChecks[funIndex](value)
        if out then
            local typeDefinition = parsimmon.customTypes[out]
            if not typeDefinition then
                error("Trying to encode unregistered custom type '" .. tostring(out) .. "'")
            end

            local encoded = typeDefinition.encoder(value, context)
            return out .. encoded
        end
    end

    for funIndex = 1, #defaultTypeAndLiteralCheckers do
        local out = defaultTypeAndLiteralCheckers[funIndex](value)
        if out then
            local encoder = parsimmon.encoders[out]
            if not encoder then error("Trying to encode type '" .. tostring(out) .. "' (no encoder defined for this type)") end
            return encoder(value, context)
        end
    end

    error("Couldn't determine type of value: " .. tostring(value))
end

parsimmon.encoders["nil"] = function () return "null" end
parsimmon.encoders.number = function (value)
    return tostring(value)
end
parsimmon.encoders.string = function (value)
    value = string.gsub(value, "\\", "\\\\")
    value = string.gsub(value, '"', '\\"')
    value = string.gsub(value, "\n", "\\n")
    value = string.gsub(value, "\r", "\\r")
    value = string.gsub(value, "\t", "\\t")
    return '"' .. value .. '"'
end
parsimmon.encoders.boolean = function (value)
    return value and "true" or "false"
end
parsimmon.encoders.array = function (array)
    local out = {}
    for index = 1, #array do
        out[#out+1] = parsimmon.encoders.any(array[index])
    end
    return "[" .. table.concat(out, ",") .. "]"
end
parsimmon.encoders.object = function (object, context)
    local keys = {}
    for key in pairs(object) do
        keys[#keys+1] = key
    end
    local splitEncodedObjectLines = parsimmon.splitEncodedObjectLines

    if parsimmon.sortEncodedObjects then
        table.sort(keys, compareAnything)
    end

    local out = {"{"}

    local passedContext
    local objectDepth = 1
    if context and context.objectDepth then objectDepth = context.objectDepth end

    for keyIndex = 1, #keys do
        if splitEncodedObjectLines then
            passedContext = passedContext or {objectDepth = objectDepth + 1}

            out[#out+1] = "\n"
            out[#out+1] = string.rep("    ", objectDepth)
        end

        local key = keys[keyIndex]
        local keyType = type(key)
        local encodedKey

        if keyType == "string" then
            encodedKey = parsimmon.encoders.string(key)
            if parsimmon.wrapStringKeysInBrackets then encodedKey = "[" .. encodedKey .. "]" end
        else
            encodedKey = '[' .. parsimmon.encoders.any(key, passedContext) .. ']'
        end

        out[#out+1] = encodedKey
        out[#out+1] = ": "
        out[#out+1] = parsimmon.encoders.any(object[key], passedContext)
        if keyIndex < #keys then out[#out+1] = ',' end
    end

    if splitEncodedObjectLines and #keys > 0 then
        out[#out+1] = "\n"
        if context and context.objectDepth then out[#out+1] = string.rep("    ", context.objectDepth-1) end
    end
    out[#out+1] = "}"

    return table.concat(out)
end

-- Character lookup tables -------------------------------------------------------------------------

local charMaps = {}
parsimmon.charMaps = charMaps

charMaps.whitespace = {
    [" "] = true,
    ["\n"] = true,
    ["\r"] = true,
    ["\t"] = true,
}

charMaps.terminating = {
    [" "] = true,
    ["\n"] = true,
    ["\r"] = true,
    ["\t"] = true,
    [","] = true,
    [":"] = true,
    ["}"] = true,
    ["]"] = true,
    ["{"] = true,
    ["["] = true
}

charMaps.escapedMeanings = {
    ["n"] = "\n",
    ["r"] = "\r",
    ["t"] = "\t",
    ["\\"] = "\\",
    ['"'] = '"',
}

local symbols = {}

-- Parsing utility ---------------------------------------------------------------------------------

---@param str string
---@param i integer
---@param map table<string, boolean>
---@return integer
function parsimmon.findChar(str, i, map)
    while true do
        local char = str:sub(i, i)
        if map[char] then return i end
        if i > #str then return i end
        i = i + 1
    end
end

function parsimmon.findNotChar(str, i, map)
    while true do
        local char = str:sub(i, i)
        if not map[char] then return i end
        if i > #str then return i end
        i = i + 1
    end
end

---@param str string
---@param i integer
---@param message string
function parsimmon.throwParseError(str, i, message)
    local line = 1
    local column = 1
    for charIndex = 1, i do
        if str:sub(charIndex, charIndex) == "\n" then
            line = line + 1
            column = 1
        else
            column = column + 1
        end
    end
    error("Parse error near '" .. str:sub(i,i) .. "' at line " .. line .. " column " .. column .. ": " .. message)
end

-- Parsing functions -------------------------------------------------------------------------------

--- The parsing functions used by the library,
--- exposed so they can be used by custom parsers
--- (the one you'll want to use for basically any nested values is `parsimmon.parsers.any`).
--- 
--- The functions expect a string of the full data that's being parsed (`str`),
--- the index at which their value starts (`i`),
--- and may optionally receive a third argument, `context`, which might mean something different for each parser (but is always a table).
--- 
--- They must return the parsed value and the index at which it ends (`j`).
---@type table<string, Parsimmon.ValueParser>
parsimmon.parsers = {}

function parsimmon.parsers.number(str, i)
    local j = parsimmon.findChar(str, i, charMaps.terminating)
    local num = tonumber(str:sub(i, j-1))
    if not num then parsimmon.throwParseError(str, i, "Invalid number") end
    return num, j-1
end

function parsimmon.parsers.string(str, i)
    local out = {}
    while true do
        i = i + 1
        local char = str:sub(i, i)

        if char == "\\" then
            -- Currently unsupported, but support for escaped unicode (`\u0000`) would be nice
            local escapedChar = str:sub(i+1, i+1)
            local realChar = charMaps.escapedMeanings[escapedChar]
            if not realChar then realChar = escapedChar end -- If there's no special meaning, it's just kept as is

            out[#out+1] = realChar
            i = i + 1

        elseif char == "" then
            parsimmon.throwParseError(str, i, "Unterminated string")

        elseif char == '"' then
            return table.concat(out), i

        else
            out[#out+1] = char
        end
    end
end

--- Assumes `i` starts at its opening character.  
--- Goes on until the closing character, which can be specified in the context in `context.closingChar`.
function parsimmon.parsers.array(str, i, context)
    local closingChar = context and context.closingChar or "]"
    local out = {}

    i = parsimmon.findNotChar(str, i+1, charMaps.whitespace)
    if str:sub(i, i) == closingChar then return out, i end

    while true do
        local value
        value, i = parsimmon.parsers.any(str, i)
        out[#out+1] = value

        i = parsimmon.findNotChar(str, i+1, charMaps.whitespace)
        local char = str:sub(i, i)
        if char == closingChar then return out, i end
        if char ~= "," then parsimmon.throwParseError(str, i, "Expected comma or closing character") end

        i = parsimmon.findNotChar(str, i+1, charMaps.whitespace)
    end
end

--- Assumes `i` starts at its opening character.  
--- Goes on until the closing character, which can be specified in the context in `context.closingChar`.  
--- The delimiter character between keys and values can be configured in `context.delimiterChar`
function parsimmon.parsers.object(str, i, context)
    local closingChar = context and context.closingChar or "}"
    local delimiterChar = context and context.delimiterChar or ":"
    local out = {}

    i = parsimmon.findNotChar(str, i+1, charMaps.whitespace)
    if str:sub(i, i) == closingChar then return out, i end

    while true do
        local key
        local keyChar = str:sub(i, i)

        -- String key
        if keyChar == '"' then
            key, i = parsimmon.parsers.string(str, i)

        -- Literal key
        elseif keyChar == "[" then
            i = parsimmon.findNotChar(str, i+1, charMaps.whitespace)
            key, i = parsimmon.parsers.any(str, i)

            i = parsimmon.findNotChar(str, i+1, charMaps.whitespace)
            if str:sub(i, i) ~= "]" then parsimmon.throwParseError(str, i, "Expected closing bracket for object key: " .. tostring(key)) end
            if key == nil then parsimmon.throwParseError(str, i, "Object key cannot be null") end
            if key ~= key and type(key) == "number" then parsimmon.throwParseError(str, i, "Object key cannot be NaN") end

        -- Invalid key
        else
            parsimmon.throwParseError(str, i, "Expected quote or opening square bracket")
        end

        i = parsimmon.findNotChar(str, i+1, charMaps.whitespace)
        if str:sub(i, i) ~= delimiterChar then parsimmon.throwParseError(str, i, "Expected delimiter character (" .. tostring(delimiterChar) .. ")") end

        i = parsimmon.findNotChar(str, i+1, charMaps.whitespace)
        local value
        value, i = parsimmon.parsers.any(str, i)
        out[key] = value

        i = parsimmon.findNotChar(str, i+1, charMaps.whitespace)
        local char = str:sub(i, i)
        if char == closingChar then return out, i end
        if char ~= "," then parsimmon.throwParseError(str, i, "Expected comma or closing character") end

        i = parsimmon.findNotChar(str, i+1, charMaps.whitespace)
    end
end

function parsimmon.parsers.customTypeOrLiteral(str, i, context)
    local j = parsimmon.findChar(str, i, charMaps.terminating)
    local terminator = str:sub(j, j)
    local text = str:sub(i, j-1)

    if terminator == "{" then
        -- Not a literal, this is a custom type
        local typeDefinition = parsimmon.customTypes[text]
        if not typeDefinition then
            parsimmon.throwParseError(str, i, "Unknown type (" .. tostring(text) .. ")")
        end

        local parsed, nextIndex = typeDefinition.parser(str, j, context)
        local init = typeDefinition.initializer
        if init then
            if type(init) == "table" then setmetatable(parsed, init)
            else init(parsed, context) end
        end

        return parsed, nextIndex
    end

    if text == "true" then return true, j-1 end
    if text == "false" then return false, j-1 end
    if text == "null" then return nil, j-1 end

    -- Numbers are also considered literals
    -- (this should only really ever happen for nans and infs though)
    local num = tonumber(text)
    if num then return num, j-1 end

    -- Custom literals are last, meaning they can't overwrite default literals like `true` and `false`.
    if parsimmon.customLiterals[text] then return parsimmon.customLiterals[text], j-1 end

    parsimmon.throwParseError(str, i, "Unknown literal (" .. tostring(text) .. ")")
    error("Impossible to get here") -- Soothe annotations
end

---@param fn function
---@param chars string
local function registerSymbols(fn, chars)
    for charIndex = 1, #chars do
        local char = chars:sub(charIndex, charIndex)
        if symbols[char] then error(char .. " is already registered") end
        symbols[char] = fn
    end
end

registerSymbols(parsimmon.parsers.number, "-+0123456789")
registerSymbols(parsimmon.parsers.customTypeOrLiteral, "AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz")
registerSymbols(parsimmon.parsers.string, '"')
registerSymbols(parsimmon.parsers.array, "[")
registerSymbols(parsimmon.parsers.object, "{")

--- The holy grail  
--- 
--- Any time your custom parser allows for nested values, such as the values in an array, this should be used to parse those.
---
--- The `context` table passed into this parser will simply be forwarded to the actually used parser.
function parsimmon.parsers.any(str, i, context)
    local char = str:sub(i, i)
    local parseFn = symbols[char]
    if not parseFn then parsimmon.throwParseError(str, i, "Unexpected character") end
    return parseFn(str, i, context)
end

----------------------------------------------------------------------------------------------------

--- Parses the given ARSON string into data.
---@param str string
---@return any
function parsimmon.parse(str)
    local i = parsimmon.findNotChar(str, 1, charMaps.whitespace)
    local value, j = parsimmon.parsers.any(str, i)

    j = parsimmon.findNotChar(str, j+1, charMaps.whitespace)
    if j <= #str then parsimmon.throwParseError(str, j, "Unexpected character") end
    return value
end

--- Encodes the given value into an ARSON string.
---@param value any
---@return string
function parsimmon.encode(value)
    return parsimmon.encoders.any(value)
end

return parsimmon