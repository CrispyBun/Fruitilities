--- The package table - Calling is equivalent to `languava.get()`.
---@overload fun(query: string, langcode: string?): string
local languava = {}
local languavaMT = {}

--- The currently selected language, used as default when getting translations
languava.currentLanguage = "en_US"

--- If this is set to a language code, all languages will fallback to that language if they don't specify a different fallback.  
--- You can use this to, for example, display untranslated text in english instead of having just the text id be displayed.
---@type string?
languava.defaultFallbackLanguage = nil

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

    local language = languava.langs[langcode]
    if not language then return query end

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

--- Makes the language derive from a specified parent language (the parent language will be used as a fallback language).
---@param langcode string The child language (e.g. `"en_AU"`)
---@param parentLangcode string The language to derive from (e.g. `"en_GB"`)
function languava.deriveLanguage(langcode, parentLangcode)
    local child = languava.getLanguage(langcode)
    local parent = languava.getLanguage(parentLangcode)
    child.fallbackLanguage = parent
end
languava.defineLanguageFallback = languava.deriveLanguage

--- Adds a single translation to the specified language.
---@param langcode string The language code of the language (e.g. `"en_US"`)
---@param textID string The identifier of the translation (e.g. `"game.item.sword"`)
---@param translation string The translation itself (e.g. `"Sword"`)
function languava.addTranslation(langcode, textID, translation)
    local language = languava.getLanguage(langcode)
    language.fields[textID] = translation
end

--------------------------------------------------
--- The Language class

--- Gets the actual object associated with the given langcode (or creates it, if it hasn't been yet).  
--- There's not many uses for this besides internal library ones.
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

--- Returns the translation of the given `prompt`.
---@param prompt string
---@return string
function Language:get(prompt)
    local translation = self.fields[prompt]

    if translation then return translation end
    if self.fallbackLanguage then return self.fallbackLanguage:get(prompt) end
    return prompt
end

--------------------------------------------------
---@diagnostic disable-next-line: param-type-mismatch
return setmetatable(languava, languavaMT)