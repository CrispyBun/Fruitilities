------------------------------------------------------------
-- A simple INI parsing library
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

local ini = {}

------------------------------------------------------------
--- ### ini.encode(t)
--- Encodes a table into an ini string. The table must be in the format:  
--- `{ section1 = {a=value,b=value,c=value}, section2 = {a=value,b=value}, ... }`  
---@param t table<string, table<string, any>>
---@return string
function ini.encode(t)
    local outStr = {}
    for sectionName, section in pairs(t) do
        if string.find(sectionName, "[", 1, true) then error("Section '" .. sectionName .. "' contains illegal character ( [ )", 2) end
        if string.find(sectionName, "]", 1, true) then error("Section '" .. sectionName .. "' contains illegal character ( ] )", 2) end

        table.insert(outStr, "[" .. sectionName .. "]\n")
        for key, value in pairs(section) do
            if string.find(key, "[", 1, true) then error("Key '" .. key .. "' contains illegal character ( [ )", 2) end
            if string.find(key, "]", 1, true) then error("Key '" .. key .. "' contains illegal character ( ] )", 2) end
            if string.find(key, "=", 1, true) then error("Key '" .. key .. "' contains illegal character ( = )", 2) end
            if string.find(key, "%s") then error("Key '" .. key .. "' contains illegal character ( whitespace )", 2) end

            table.insert(outStr, key .. " = " .. ini.encodeValue(value) .. "\n")
        end
        table.insert(outStr, "\n")
    end
    return table.concat(outStr)
end

------------------------------------------------------------
--- ### ini.decode(str)
--- Decodes an ini string into a table. The table will be in the format:  
--- `{ section1 = {a=value,b=value,c=value}, section2 = {a=value,b=value}, ... }`
---@param str string
---@return table<string, table<string, any>>
function ini.decode(str)
    local t = {}

    for sectionName, section in string.gmatch(str, "%[([^%]]*)%]([^%[]*)") do
        t[sectionName] = {}

        for key, value in string.gmatch(section, "([^\n=]*)=([^\n]*)\n") do

            if string.sub(key, 1, 1) ~= ";" then -- Skip comments
                key = key:match("^%s*(.-)%s*$")
                value = value:match("^%s*(.-)%s*$")
                t[sectionName][key] = ini.decodeValue(value)
            end
        end
    end

    return t
end

------------------------------------------------------------
--- ### ini.encodeValue(value)
--- Used internally. Returns a string of what a value will look like in an encoded ini file.
---@param value any
---@return string
function ini.encodeValue(value)
    local valueType = type(value)

    if valueType == "nil" then return "nil" end
    if valueType == "number" then return tostring(value) end
    if valueType == "boolean" then return value and "true" or "false" end

    if valueType == "string" then
        -- Replace newlines, quotes, backslashes, and =, [, ] with special escape characters to make the pattern matching in decoding easier.
        value = value:gsub("\\", "\\\\") -- backslashes need to be done first
        value = value:gsub("\n", "\\n")
        value = value:gsub("\"", "\\\"")
        value = value:gsub("=", "\\e")
        value = value:gsub("%[", "\\o")
        value = value:gsub("%]", "\\c")

        -- If there is a leading or trailing whitespace,
        -- or if the string would be interpreted as another type, wrap it in quotes.
        if value:sub(1, 1):match("%s") or value:sub(-1, -1):match("%s") or tonumber(value) ~= nil or value == "true" or value == "false" or value == "nil" then
            return "\"" .. value .. "\""
        end
        return value
    end

    error("Trying to encode unsupported value type: " .. valueType)
end

------------------------------------------------------------
--- ### ini.decodeValue(value)
--- Opposite of `ini.encodeValue(value)`. Used internally.
---@param value string
---@return any
function ini.decodeValue(value)
    local number = tonumber(value)
    if number ~= nil then return number end
    if value == "true" then return true end
    if value == "false" then return false end
    if value == "nil" then return nil end

    -- If we got here, the value is a string
    if string.sub(value, 1, 1) == "\"" then value = string.sub(value, 2, -2) end -- Trim the quotes at the ends if necessary
    -- Replace all escape characters with their meaning

    value = value:gsub("\\\\", "\\=") -- first replace double backslashes to something that can't appear in the string

    value = value:gsub("\\n", "\n")
    value = value:gsub("\\\"", "\"")
    value = value:gsub("\\e", "=")
    value = value:gsub("\\o", "[")
    value = value:gsub("\\c", "]")

    value = value:gsub("\\=", "\\") -- now finish double backslashes

    return value
end

-- Return
return ini