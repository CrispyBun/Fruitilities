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

---@diagnostic disable-next-line: deprecated
local unpack = table.unpack or unpack

------------------------------------------------------------
--- Parses escapes, puts them into a separate table, and replaces them in the original string with indexes to that table in quotes ("1", "2", etc.)
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
---@param sep string The separator to use
---@return string[]
local function decodeLine(line, quotes, sep)
    local output = {}

    local searchStart = 1
    while searchStart <= #line+1 do -- +1 to take into account a possible trailing comma
        local commaIndex = string.find(line, sep, searchStart, true)
        if not commaIndex then commaIndex = #line + 1 end -- no comma, just finish the line

        local value = string.sub(line, searchStart, commaIndex-1)
        local quote = value:match('"(%d)"')
        if quote then
            value = quotes[tonumber(quote)]
        end

        output[#output+1] = value
        searchStart = commaIndex + 1
    end
    return output
end
------------------------------------------------------------

------------------------------------------------------------
--- ### csv.decode(str, headerless, sep)
--- Returns a key-value table of the decoded columns from the CSV.  
--- * If the `headerless` argument is false, the first line of the CSV will be interpreted as a header, and the keys to the columns will be strings taken from the header.  
--- * If the `headerless` argument is true, the columns will be numbered, and the keys to the columns will be integers.  
--- * Each column is an array of strings, in the same order as they appear in the CSV.
--- 
--- The optional `sep` parameter defaults to the value of `csv.separationSymbol` and must be a single character.
---@param str string The input CSV
---@param headerless? boolean Whether the CSV has no header (columns will be numbered instead of named)
---@param sep? string The separator to use
---@return table<string|number, string[]>
function csv.decode(str, headerless, sep)
    sep = sep or csv.separationSymbol

    local quotelessString, quotes, err = parseCsvEscapes(str)

    local headers
    local decodedTable = {}

    local searchStart = 1
    while searchStart <= #quotelessString+1 do -- +1 to take into account a possible trailing newline
        local newlineIndex = string.find(quotelessString, "\n", searchStart, true)
        if not newlineIndex then newlineIndex = #quotelessString + 1 end

        local line = string.sub(quotelessString, searchStart, newlineIndex-1)
        local lineValues = decodeLine(line, quotes, sep)

        if not headerless and not headers then
            headers = lineValues
            for _, header in ipairs(headers) do
                decodedTable[header] = {}
            end
        else
            for columnIndex = 1, #lineValues do
                local header = headers and headers[columnIndex] or columnIndex
                decodedTable[header] = decodedTable[header] or {}

                local value = lineValues[columnIndex]
                decodedTable[header][#decodedTable[header]+1] = value
            end
        end

        searchStart = newlineIndex + 1
    end

    return decodedTable
end

------------------------------------------------------------
--- ### csv.encode(t, sep)
--- Returns a CSV string encoded from a table.  
--- 
--- A `keys` table may be supplied to pick which columns to encode, as well as determine their order. If not supplied, all keys in the table are used (and are in an unpredictable order).  
--- Numeric keys will not be written as a header.  
--- 
--- The optional `sep` parameter defaults to the value of `csv.separationSymbol` and should be a single character.
---@param t table<string|number, string[]> The input table
---@param keys? (string|number)[] The keys to the columns to use
---@param sep? string The separator to use
function csv.encode(t, keys, sep)
    sep = sep or csv.separationSymbol

    if not keys then
        keys = {}
        for key in pairs(t) do
            keys[#keys+1] = key
        end
    end

    local allKeysAreNumeric = true
    local rowCount = 0
    for keyIndex = 1, #keys do
        local key = keys[keyIndex]
        if type(key) ~= "number" then allKeysAreNumeric = false end
        rowCount = math.max(rowCount, (t[key] and #t[key] or 0))
    end

    local lines = {}
    local startIndex = allKeysAreNumeric and 1 or 0 -- Any string keys must be included as a header
    for rowIndex = startIndex, rowCount do
        local line

        if rowIndex == 0 then
            line = {unpack(keys)}
        else
            line = {}
            for keyIndex = 1, #keys do
                local key = keys[keyIndex]
                local value = t[key] and t[key][rowIndex] or ""
                line[#line+1] = value
            end
        end

        for valueIndex = 1, #line do
            local value = line[valueIndex]
            local valueType = type(value)

            if valueType == "number" and rowIndex == 0 then value = "" end -- Dont add numbers as headers
            value = tostring(value)

            if string.find(value, sep, 1, true) or string.find(value, "\n", 1, true) or string.find(value, "\"", 1, true) then
                value = value:gsub("\"", "\"\"")
                value = "\"" .. value .. "\""
            end

            line[valueIndex] = value
        end

        lines[#lines+1] = table.concat(line, sep)
    end

    return table.concat(lines, "\n")
end

------------------------------------------------------------
--- ### csv.validateTable(t)
--- The encode and decode functions try to parse what they can without erroring, even if the CSV is malformed, so this function serves to check for malformed CSV data.  
--- 
--- To check if a table returned by `csv.decode()` is fully valid, or to check if a table is fully suitable for encoding, you can pass it into this function.  
--- Note that some slightly malformed CSV strings *may* pass this check (notably missing quote pairs do), but if so, they'll still be usable and the tables made from it will be consistent with valid CSVs.
---@param t table<string|number, string[]>
---@return boolean isValid
function csv.validateTable(t)
    local columnCount
    local keyType
    for key, column in pairs(t) do
        columnCount = columnCount or #column
        keyType = keyType or type(key)

        if #column ~= columnCount then return false end
        if type(key) ~= keyType then return false end -- Either numbered keys or string keys, not both
    end
    return true
end

return csv