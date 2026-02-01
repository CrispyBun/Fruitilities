----------------------------------------------------------------------------------------------------
-- A powerful locali(s/z)ation library
-- written by yours truly, CrispyBun.
-- crispybun@pm.me
-- https://github.com/CrispyBun/Fruitilities
----------------------------------------------------------------------------------------------------
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
----------------------------------------------------------------------------------------------------

--- The package table - Calling is equivalent to `languava.get()`.
---@overload fun(query: string|Languava.Query, langcode: string?): string
local languava = {}
local languavaMT = {}

--------------------------------------------------
-- Options
-- (set these only once, before using the library)

--- The currently selected language, used as default when getting translations
languava.currentLanguage = "en_US"

--- If this is set to a string (could be an empty string),
--- whenever it's detected as the translation of some text,
--- it's replaced by `nil` instead.
--- 
--- Useful if your locale file doesn't allow for "no value" to be defined for a field,
--- such as CSV, which always has at least an empty string for each cell.
---@type string?
languava.missingTranslationKeyword = nil

--- If this is set to a language code, all languages will fallback to that language if they don't specify a different fallback.  
--- You can use this to, for example, display untranslated text in english instead of having just the text ID be displayed.
---@type string?
languava.defaultFallbackLanguage = nil

--- If this is set to a specific text ID (e.g. `"meta.fallback"`), the value of this field in languages
--- will be used to set the fallback language to the language code specified in the field (e.g. the "translation" for the text ID would be `"en_US"`).  
--- 
--- Useful if you want to be able to set the fallback language directly in the locale file.
---@type string?
languava.fallbackLanguageMetaField = nil

--- If this is set to a string, language subsets can be defined for a language with their langcode being
--- `<langcode>[separator]<subset>`. If the separator is `'@'`, for example, a language subset could be `en_US@plural`.
--- 
--- A subset can then be selected when querying for translations. For example, if the separator is the @ symbol:
--- * `languava.get("game.item.sword", "@plural")` actually searches in `<currentLanguage>@plural` (so, for example, `en_US@plural`).
--- * When querying a language class directly, `language:get(query, subset)` accepts the subset *name*, so in this case, just `"plural"`
--- 
--- Also, when a language is detected to be a subset (its langcode contains the separator),
--- its fallback will by default be set to the language it is a subset of.
--- 
--- The separator can be a full string, not just one symbol.
---@type string?
languava.languageSubsetSeparator = nil

--------------------------------------------------
-- Data

--- All of the defined languages
---@type Languava.LanguageList
languava.langs = {}

--------------------------------------------------
--- Definitions

---@class Languava.LanguageList
---@field [string] Languava.Language Each language code (e.g. `"en_US"`) mapped to its language definition

---@class Languava.Language
---@field fields table<string, string> Each text identifier (e.g. `"game.item.sword"`) mapped to its translation (e.g. `"Sword"`)
---@field fallbackLanguage? Languava.Language A language where translations will be looked for if this one doesn't have them
---@field fallbackFunction? fun(self: Languava.Language, query: string): string? A function that will be used to get the translation of a string query if a translation for it wasn't found in this language. May return nil.
---@field processingChain (fun(self: Languava.Language, query: Languava.Query): string?)[] Chain of functions that can process object queries. Is executed in order and the first one to return a string is used as the translation.
---@field subsetLanguages table<string, Languava.Language> Any subsets of this language
local Language = {}
local LanguageMT = {__index = Language}

--- Definition for the query object which can be passed into `languava.get()`. Feel free to inject your own fields into the definition.
---@class Languava.Query
---@field base string The textID of the main part of the query. If a query doesn't get processed programatically, simply the translation for the base (as a string) will be used.
---@field [any] any Any other values for the query which can be used when the query is being processed.

--------------------------------------------------
--- Getting translations

--- Gets the translation of the given `query`. Will use `languava.currentLanguage` if `langcode` isn't provided.
--- You can also call this function using `languava()`.
--- 
--- The query can either be a string of the textID itself for simple translations,
--- or a query object - an object which must have the `base` field with a textID,
--- and can have any other fields which your processing chain can use for the translation.
--- This is used for advanced programatically determined translations.
--- 
--- A langcode can be provided, which can either select the language to get the translation from,
--- or if it's in the format of `[languava.languageSubsetSeparator][subset name]`, to select a subset of the currently selected language.
---@param query string|Languava.Query The identifier of the translation (e.g. `"game.item.sword"` or `{base = "game.item.sword"}`)
---@param langcode? string Optional override or subset for the language to use instead of the currently selected one (e.g. `"en_US"` or `"@plural"` if @ is the subset separator)
---@return string translation The translated text, or just the query as a string if a translation wasn't found
---@return boolean found Whether or not a translation was found
function languava.get(query, langcode)
    if not query then error("No query provided", 2) end
    langcode = langcode or languava.currentLanguage

    ---@type string?
    local subsetName
    local subsetSeparator = languava.languageSubsetSeparator
    if subsetSeparator then
        if string.find(langcode, subsetSeparator, 1, true) == 1 then
            -- `langcode` is a subset, not a separate language, so:
            subsetName = string.sub(langcode, #subsetSeparator+1)
            langcode = languava.currentLanguage
        end
    end

    local language = languava.getLanguage(langcode)
    return language:get(query, subsetName)
end

---@param t any
---@param query string|Languava.Query
---@param langcode? string
---@return string
---@return boolean
function languavaMT.__call(t, query, langcode)
    return languava.get(query, langcode)
end

--- Sets the currently selected language.
---@param langcode string
function languava.setCurrentLanguage(langcode)
    languava.currentLanguage = langcode
end

--------------------------------------------------
--- Defining translations

--- Adds a single translation to the specified language.
--- 
--- Example usage:
--- ```lua
--- languava.addTranslation("en_US", "game.item.sword", "Sword")
--- ```
---@param langcode string The language code of the language (e.g. `"en_US"`)
---@param textID string The identifier of the translation (e.g. `"game.item.sword"`)
---@param translation string The translation itself (e.g. `"Sword"`)
function languava.addTranslation(langcode, textID, translation)
    if translation == languava.missingTranslationKeyword then return end
    textID = tostring(textID)

    local language = languava.getLanguage(langcode)
    language.fields[textID] = translation

    if textID == languava.fallbackLanguageMetaField then
        languava.deriveLanguage(langcode, translation)
    end
end

--- Adds a set of translations (where keys are textIDs and values are the translations) to the specified language.
--- 
--- Example usage:
--- ```lua
--- languava.addTranslations("en_US", {
---     ["game.item.sword"] = "Sword",
---     ["game.item.shield"] = "Shield"
--- })
--- ```
---@param langcode string The language code of the language (e.g. `"en_US"`)
---@param translations table<string, string> The identifiers of the translations mapped to their translations (e.g. `{ ["game.item.sword"] = "Sword" }`)
function languava.addTranslations(langcode, translations)
    for textID, translation in pairs(translations) do
        languava.addTranslation(langcode, textID, translation)
    end
end

--- Adds an entire table defining any amount of translations for any amount of languages.  
--- The keys of the table are langcodes, their values are tables that map textIDs to translations.
--- 
--- Example usage:
--- ```lua
--- languava.addTranslationTable({
---     en_US = {
---         ["game.item.sword"] = "Sword",
---         ["game.item.shield"] = "Shield"
---     },
---     de_DE = {
---         ["game.item.sword"] = "Schwert",
---         ["game.item.shield"] = "Schild"
---     },
--- })
--- ```
---@param table table<string, table<string, string>>
function languava.addTranslationTable(table)
    for langcode, translations in pairs(table) do
        languava.addTranslations(langcode, translations)
    end
end

--- Makes the language derive from a specified parent language (the parent language will be used as a fallback language).
---@param langcode string The child language (e.g. `"en_AU"`)
---@param parentLangcode string The language to derive from (e.g. `"en_GB"`)
function languava.deriveLanguage(langcode, parentLangcode)
    local child = languava.getLanguage(langcode)
    local parent = languava.getLanguage(parentLangcode)
    child.fallbackLanguage = parent
end
languava.defineLanguageFallback = languava.deriveLanguage

--- Sets the fallback function of the language.  
--- 
--- The function is called if a language doesn't find any translation for a given string query.
--- It's passed the language object and the string query, and it can either return a string of the translation,
--- or `nil`, in which case the fallback language will be used, if there is any.
---@param langcode string
---@param fallbackFn fun(self: Languava.Language, query: string): string?
function languava.setLanguageFallbackFunction(langcode, fallbackFn)
    local language = languava.getLanguage(langcode)
    language.fallbackFunction = fallbackFn
end

--- Adds a query processing function to the language's processing chain.  
--- 
--- The processing chain is executed in order for any object query (`Languava.Query` object),
--- and the first function in the chain to return a string is used for the translation.
--- If no function in the chain returns a string, the query will be processed as a regular string query (based on its `base` field).  
--- 
--- This is used for advanced, dynamically generated translations for more complex queries.
---@param langcode string
---@param processingFn fun(self: Languava.Language, query: Languava.Query): string?
function languava.addLanguageQueryProcessor(langcode, processingFn)
    local language = languava.getLanguage(langcode)
    language.processingChain[#language.processingChain+1] = processingFn
end

--------------------------------------------------
--- The Language class

--- Gets the actual object associated with the given langcode (or creates it, if it hasn't been yet).  
---@param langcode string The language code of the language (e.g. `"en_US"`)
---@return Languava.Language
function languava.getLanguage(langcode)
    local language = languava.langs[langcode]

    if not language then
        language = languava.newLanguage()
        languava.langs[langcode] = language

        -- Default fallback
        local defaultFallback = languava.defaultFallbackLanguage
        if defaultFallback and defaultFallback ~= langcode then
            languava.deriveLanguage(langcode, defaultFallback)
        end

        -- Deal with subsets
        local subsetSeparator = languava.languageSubsetSeparator
        if subsetSeparator then
            local baseLangcode, subsetName = string.match(langcode, "^(.*)" .. subsetSeparator .. "(.*)$")
            if baseLangcode and subsetName then
                -- Set fallback to the base language
                languava.deriveLanguage(langcode, baseLangcode)

                -- Assign self as a subset of the base language
                languava.getLanguage(baseLangcode).subsetLanguages[subsetName] = language
            end
        end
    end

    return language
end

--- Creates a new language object. Use this if you want to manage the language objects yourself,
--- otherwise this is used internally and you don't have to worry about it.
---@return Languava.Language
function languava.newLanguage()
    ---@type Languava.Language
    local language = {
        fields = {},
        subsetLanguages = {},
        processingChain = {}
    }
    return setmetatable(language, LanguageMT)
end

--- Returns the translation of the given `query`.
---@param query string|Languava.Query The query specifying what translation to get
---@param subset? string Can be used to look into a subset of the language instead of the language itself
---@return string translation The translated text, or just the query as a string if a translation wasn't found
---@return boolean found Whether or not a translation was found
function Language:get(query, subset)
    if type(query) == "table" and not query.base then
        error("Object query is missing 'base' field", 2)
    end
    local stringQuery = type(query) == "string" and query or query.base

    -- Querying a subset
    if subset then
        local subsetLanguage = self.subsetLanguages[subset]
        if not subsetLanguage then return stringQuery, false end -- Subset not found

        return subsetLanguage:get(query)
    end

    -- Object queries
    if type(query) == "table" then
        local chain = self.processingChain
        for processorIndex = 1, #chain do
            local processingFn = chain[processorIndex]
            local out = processingFn(self, query)
            if out then return out, true end
        end
    end

    -- Regular string query processing and fallbacks:

    local translation = self:getRaw(stringQuery)
    if translation then return translation, true end

    if self.fallbackFunction then
        local out = self:fallbackFunction(stringQuery)
        if out then return out, true end
    end

    if self.fallbackLanguage then return self.fallbackLanguage:get(query) end
    return stringQuery, false
end

--- Simply gets the text translation of a pure string query if it has one, or `nil` if it doesn't.  
--- Doesn't care about fallback languages, fallback functions, or anyting else fancy.
---@param query string
---@return string?
function Language:getRaw(query)
    return self.fields[query]
end

--------------------------------------------------
---@diagnostic disable-next-line: param-type-mismatch
return setmetatable(languava, languavaMT)