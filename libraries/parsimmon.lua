------------------------------------------------------------
-- A custom JSON-like format parsing library
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
-- (these assume the given `i` value starts directly at the beginning of the value to be parsed)

local function parseNumber(str, i)
    local j = parsimmon.findChar(str, i, charMaps.terminating)
    local num = tonumber(str:sub(i, j-1))
    if not num then parsimmon.throwParseError(str, i, "Invalid number") end
    return num, j-1
end
symbols["-"] = parseNumber
symbols["0"] = parseNumber symbols["1"] = parseNumber
symbols["2"] = parseNumber symbols["3"] = parseNumber
symbols["4"] = parseNumber symbols["5"] = parseNumber
symbols["6"] = parseNumber symbols["7"] = parseNumber
symbols["8"] = parseNumber symbols["9"] = parseNumber

-- todo: these won't just be a sign of numbers in the future
symbols["n"] = parseNumber symbols["N"] = parseNumber
symbols["i"] = parseNumber symbols["I"] = parseNumber

--- Parses a single value in the string starting at index `i`.  
--- This is used internally by other parsers, to parse a full string, use `parsimmon.parse()`.
---@param str string The string to parse from
---@param i integer The index to parse from
---@return any value The parsed value
---@return integer j The index of the last character in the parsed value
function parsimmon.parseValue(str, i)
    local char = str:sub(i, i)
    local parseFn = symbols[char]
    if not parseFn then parsimmon.throwParseError(str, i, "Unexpected character") end
    return parseFn(str, i)
end

----------------------------------------------------------------------------------------------------

function parsimmon.parse(str)
    local i = parsimmon.findNotChar(str, 1, charMaps.whitespace)
    local value, j = parsimmon.parseValue(str, i)

    j = parsimmon.findNotChar(str, j+1, charMaps.whitespace)
    if j <= #str then parsimmon.throwParseError(str, j, "Unexpected character") end
    return value
end

return parsimmon