--- The package table - Calling is equivalent to `languava.get()`.
---@overload fun(query: string, langcode: string?): string
local languava = {}
local languavaMT = {}

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
--- * A query object with the `subset` field set to `"plural"` will search in the same place as the above.
--- 
--- The separator can be a full string, not just one symbol.
---@type string?
languava.languageSubsetSeparator = nil

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
local Language = {}
local LanguageMT = {__index = Language}

--------------------------------------------------
--- Getting translations

--- Gets the translation of the given `query`. Will use `languava.currentLanguage` if `langcode` isn't provided.
--- You can also call this function using `languava()`.
---@param query string The identifier of the translation (e.g. `"game.item.sword"`)
---@param langcode? string
---@return string
function languava.get(query, langcode)
    if not query then error("No text query provided", 2) end
    langcode = langcode or languava.currentLanguage

    if languava.languageSubsetSeparator then
        if string.find(langcode, languava.languageSubsetSeparator, 1, true) == 1 then
            langcode = languava.currentLanguage .. langcode
        end
    end

    local language = languava.getLanguage(langcode)
    return language:get(query)
end

---@param t any
---@param query string
---@param langcode? string
---@return string
function languavaMT.__call(t, query, langcode)
    return languava.get(query, langcode)
end

--- Sets the currently selected language.
---@param langcode string
function languava.setLanguage(langcode)
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
---@param fallbackFn fun(language: Languava.Language, query: string): string?
function languava.setLanguageFallbackFunction(langcode, fallbackFn)
    local language = languava.getLanguage(langcode)
    language.fallbackFunction = fallbackFn
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

        local defaultFallback = languava.defaultFallbackLanguage
        if defaultFallback and defaultFallback ~= langcode then
            languava.deriveLanguage(langcode, defaultFallback)
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
        fields = {}
    }
    return setmetatable(language, LanguageMT)
end

--- Returns the translation of the given `query`.
---@param query string
---@return string
function Language:get(query)
    local translation = self.fields[query]

    if translation then return translation end

    if self.fallbackFunction then
        local out = self:fallbackFunction(query)
        if out then return out end
    end

    if self.fallbackLanguage then return self.fallbackLanguage:get(query) end
    return query
end

--------------------------------------------------
---@diagnostic disable-next-line: param-type-mismatch
return setmetatable(languava, languavaMT)