------------------------------------------------------------
-- A simple CSV parsing library
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

local csv = {}
csv.separationSymbol = ","

------------------------------------------------------------
---@param str string
---@return string quotelessString
---@return string[] quotes
---@return string|nil err
local function parseCsvEscapes(str)
    local stringLength = #str
    local parsed = {}
    local quotes = {}
    local err = nil

    local escapeIndex = 1
    local startIndex = 1
    repeat
        local _, firstQuoteIndex = string.find(str, "\"", startIndex)
        if not firstQuoteIndex then break end

        ---@type integer|nil
        local secondQuoteIndex = firstQuoteIndex
        local doubleQuote
        repeat
            _, secondQuoteIndex, doubleQuote = string.find(str, "\"(\"?)", secondQuoteIndex + 1)
        until doubleQuote ~= "\""

        if not secondQuoteIndex then
            -- No quote pair
            err = "Missing quote pair"
            secondQuoteIndex = stringLength + 1
        end

        parsed[#parsed+1] = string.sub(str, startIndex, firstQuoteIndex-1) .. "\"" .. escapeIndex .. "\""
        quotes[escapeIndex] = str.sub(str, firstQuoteIndex+1, secondQuoteIndex-1):gsub("\"\"", "\"")
        escapeIndex = escapeIndex + 1

        startIndex = secondQuoteIndex + 1

    until startIndex > stringLength

    if startIndex <= stringLength then
        parsed[#parsed+1] = string.sub(str, startIndex)
    end

    return table.concat(parsed), quotes, err
end

---@param line string The line to decode, which must already have parsed quotes
---@param quotes string[] All parsed quotes that may be present in the line
---@param sep? string The separator to use
---@return string[]
local function decodeLine(line, quotes, sep)
    local output = {}
    local matchPattern = "[^" .. sep .. "]+"
    for value in line:gmatch(matchPattern) do
        local quote = value:match('^"(%d)"$')
        if quote then
            value = quotes[tonumber(quote)]
        end
        output[#output+1] = value
    end
    return output
end
------------------------------------------------------------

------------------------------------------------------------
--- ### csv.decode(str, sep)
--- Returns a key-value table of the decoded CSV, the keys being the first line (header).  
--- The optional "sep" parameter defaults to the value of csv.separationSymbol and must be a single character.
---@param str string The input CSV
---@param sep? string The separator to use
---@return table<string, string>
function csv.decode(str, sep)
    sep = sep or csv.separationSymbol

    local quotelessString, quotes, err = parseCsvEscapes(str)

    local headers
    local decodedTable = {}
    for line in quotelessString:gmatch("[^\n]+") do
        local lineValues = decodeLine(line, quotes, sep)

        if not headers then
            headers = lineValues
        else
            for valueIndex = 1, #lineValues do
                local header = headers[valueIndex]
                local value = lineValues[valueIndex]
                if not decodedTable[header] then decodedTable[header] = {} end
                decodedTable[header][#decodedTable[header]+1] = value
            end
        end
    end

    return decodedTable
end

return csv