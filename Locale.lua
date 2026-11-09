local _, ES = ...

-- Idiomas del addon. El texto del código está en español y sirve de clave:
-- L["texto"] devuelve la traducción del idioma elegido, o el propio texto si
-- no hay traducción (así nada se rompe si falta alguna).
--
-- El idioma se lee de CraftersJournalDB.lang al cargar (ADDON_LOADED); hasta
-- entonces, el del cliente. Cambiarlo se aplica al momento (ES:SetLanguage): las
-- tablas que se crean al cargar los archivos se traducen donde se usan (L[TABLA[k]]).

ES.LANGS = {
  { key = "es", name = "Español" },
  { key = "en", name = "English" },
  { key = "de", name = "Deutsch" },
}
ES.Locales = {}

-- Idioma del cliente (GetLocale) -> idioma del addon; nil si el addon no lo tiene
local CLIENT_LANGS = { esES = "es", esMX = "es", enUS = "en", enGB = "en", deDE = "de" }
function ES.ClientLanguage()
  local loc = GetLocale and GetLocale() or "esES"
  return CLIENT_LANGS[loc]
end

-- Idioma por defecto: el del cliente si el addon lo tiene; si no, inglés
function ES.DefaultLanguage()
  return ES.ClientLanguage() or "en"
end

-- Idiomas que escriben los decimales con coma ("2,5"); los demás, con punto
ES.DECIMAL_COMMA = { es = true, de = true }

ES.lang = ES.DefaultLanguage()

ES.L = setmetatable({}, {
  __index = function(_, key)
    local t = ES.Locales[ES.lang]
    return t and t[key] or key
  end,
})

-- Tablas de textos que se crean al cargar los archivos (antes de saber el idioma
-- guardado): se registran aquí con su texto original (en español) y se traducen
-- en ADDON_LOADED y cada vez que se cambia de idioma.
--   ES.Localize(tabla)            traduce todos sus valores de texto
--   ES.Localize(tabla, "campo")   traduce ese campo de cada fila
local registry = {}
function ES.Localize(t, field)
  local orig = {}
  for k, v in pairs(t) do
    if field then
      if type(v) == "table" and type(v[field]) == "string" then orig[v] = v[field] end -- por fila: sobrevive a quitar filas
    elseif type(v) == "string" then
      orig[k] = v
    end
  end
  registry[#registry + 1] = { t = t, field = field, orig = orig }
  return t
end

function ES.ApplyLocalization()
  local L = ES.L
  for _, p in ipairs(registry) do
    for k, text in pairs(p.orig) do
      if p.field then k[p.field] = L[text] else p.t[k] = L[text] end
    end
  end
end

-- Elegir idioma: se aplica al momento, sin recargar la interfaz (Forever no deja
-- que un addon la recargue): textos, nombres de recetas y objetos, y la ventana
-- se vuelve a crear con el idioma nuevo.
function ES:SetLanguage(lang)
  if lang == self.lang then return end
  self.lang = lang
  self.db.lang = lang
  ES.ApplyLocalization()
  self:LocalizeRecipeNames()
  if self.ClearHomeCache then self:ClearHomeCache() end
  if self.RebuildMainFrame then self:RebuildMainFrame() end
end
