------------------------------------------------------------
-- A custom JSON-like format (called ARSON) parsing library
-- written by yours truly, CrispyBun.
-- crispybun@pm.me
-- https://github.com/CrispyBun/Fruitilities
------------------------------------------------------------
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
------------------------------------------------------------

--- Inspired by some of the ways https://github.com/rxi/json.lua does its parsing

--- ARSON - Arbitrary Structure Object Notation  
--- Backwards compatible with JSON, allows for arbitrary custom types.
local parsimmon = {}

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

function parsimmon.throwParseError(str, i, message)
    -- todo: proper line and column info
    error("Error while parsing (" .. tostring(message) .. ")")
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
---@type table<string, fun(str: string, i: integer, context?: table): any, integer>
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
            local realChar = parsimmon.charMaps.escapedMeanings[escapedChar]
            if not realChar then parsimmon.throwParseError(str, i, "Invalid escape character") end
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
    if str:sub(i, i) == "]" then return out, i end

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

function parsimmon.parsers.customTypeOrLiteral(str, i)
    local j = parsimmon.findChar(str, i, parsimmon.charMaps.terminating)
    local terminator = str:sub(j, j)
    local text = str:sub(i, j-1)

    if terminator == "{" then
        -- todo: not a literal, this is a custom type
        error("NYI")
    end

    if text == "true" then return true, j-1 end
    if text == "false" then return false, j-1 end
    if text == "null" then return nil, j-1 end

    -- Numbers are also considered literals
    -- (this should only really ever happen for nans and infs though)
    local num = tonumber(text)
    if num then return num, j-1 end

    -- todo: custom literals

    parsimmon.throwParseError(str, i, "Unknown literal")
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

return parsimmon