local ADDON_NAME, ES = ...
local L = ES.L
_G.CraftersJournal = ES

ES.ICON = "Interface\\Icons\\Trade_BlackSmithing" -- martillo y yunque: profesiones (minimapa y lista de addons)
ES.ahOpen = false

-- AH abierta: por el evento o porque su ventana está a la vista (si el evento se
-- pierde, el botón de escanear no debe quedarse en gris con la AH delante)
-- El cliente puede tener las dos ventanas (moderna y clásica): vale cualquiera
local function AHFrameShown()
  for _, f in ipairs({ AuctionHouseFrame or false, AuctionFrame or false }) do
    if f and f.IsShown and f:IsShown() then return true end
  end
  return false
end

function ES:IsAuctionHouseOpen()
  if self.neutralAH then return false end -- (la neutral no tiene soporte: ver DetectAuctionHouse)
  if self.ahOpen then return true end
  if AHFrameShown() then
    self.ahOpen = true
    return true
  end
  return false
end

-- Recetas que solo puede aprender el otro bando (p. ej. el estandarte de facción):
-- fuera de los datos, así no salen en la colección, las rutas ni los contadores
function ES:DropOtherFactionRecipes()
  local mine = UnitFactionGroup and UnitFactionGroup("player")
  if mine ~= "Alliance" and mine ~= "Horde" then return end
  for _, prof in ipairs(self.PROFESSIONS) do
    local data = self.Data[prof.key]
    for id, r in pairs(data and data.recipes or {}) do
      if r.faction and r.faction ~= mine then data.recipes[id] = nil end
    end
  end
end

-- Icono de misión ("!" amarillo): el atlas en alta resolución del cliente si lo
-- tiene; si no, la textura clásica (pixelada a tamaño grande)
local QUEST_ATLAS, QUEST_TEXTURE = "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon"
local function HasAtlas(name)
  return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end
-- Para el texto: |A...|a o |T...|t
function ES.QuestIconMarkup(size)
  if HasAtlas(QUEST_ATLAS) then return string.format("|A:%s:%d:%d|a", QUEST_ATLAS, size, size) end
  return string.format("|T%s:%d|t", QUEST_TEXTURE, size)
end
-- Para una textura
function ES.SetQuestIcon(tex)
  if HasAtlas(QUEST_ATLAS) and tex.SetAtlas then tex:SetAtlas(QUEST_ATLAS) else tex:SetTexture(QUEST_TEXTURE) end
end
-- Las filas aceptan icon = ES.QUEST_ICON y lo pintan con ES.SetQuestIcon
ES.QUEST_ICON = "quest"

-- Diario del escaneo en CraftersJournalDB.scanLog (últimas 40 entradas): qué eventos
-- de la AH llegaron y cómo acabó cada escaneo. Para diagnosticar fallos en el juego.
function ES:ScanLog(text)
  if not self.db then return end
  if type(self.db.scanLog) ~= "table" then self.db.scanLog = {} end
  local log = self.db.scanLog
  log[#log + 1] = (date and date("%H:%M:%S") or tostring(time())) .. " " .. text
  while #log > 40 do table.remove(log, 1) end
end

-- Nivel máximo de las profesiones (Artesano): los planes llegan hasta aquí
ES.MAX_SKILL = 300

-- Profesiones de fabricación (tarjetas de la portada). `key` es el nombre de su
-- tabla en ES.Data; `icon`, su imagen en el juego.
-- El orden de esta lista es el orden interno de las tarjetas (la portada y
-- Patterns, ver ES.SortProfessionCards): las principales y, al final, las
-- secundarias (Cocina, Primeros auxilios)
local ICONS = "Interface\\Icons\\"
ES.PROFESSIONS = {
  { key = "Alchemy",        label = "Alquimia",      icon = ICONS .. "Trade_Alchemy" },
  { key = "Blacksmithing",  label = "Herrería",      icon = ICONS .. "Trade_BlackSmithing" },
  { key = "Enchanting",     label = "Encantam.",     icon = ICONS .. "Trade_Engraving", name = "Encantamiento" },
  { key = "Engineering",    label = "Ingeniería",    icon = ICONS .. "Trade_Engineering" },
  { key = "Leatherworking", label = "Peletería",     icon = ICONS .. "INV_Misc_ArmorKit_17" },
  { key = "Tailoring",      label = "Sastrería",     icon = ICONS .. "Trade_Tailoring" },
  -- Secundarias
  { key = "Cooking",        label = "Cocina",        icon = ICONS .. "INV_Misc_Food_15" },
  { key = "FirstAid",       label = "Primeros aux.", icon = ICONS .. "Spell_Holy_SealOfSacrifice", name = "Primeros auxilios" },
}

-- Orden de las tarjetas de profesión (la portada y Patterns): primero las que
-- tiene el personaje y luego las demás; dentro de cada sección, el orden de
-- ES.PROFESSIONS. entries = { { learned, order } } (order: su posición en la lista)
function ES.SortProfessionCards(entries)
  table.sort(entries, function(a, b)
    if a.learned ~= b.learned then return a.learned end
    return a.order < b.order
  end)
end

function ES:ProfLabel(key)
  for _, p in ipairs(self.PROFESSIONS) do
    if p.key == key then return L[p.name or p.label] end
  end
  return key
end

local DEFAULTS = {
  minimap = { minimapPos = 225 }, -- (LibDBIcon: posición en grados y hide)
  scans = {},
}

-- Números para mostrar en español: coma decimal ("2,5"), sin decimales a
-- partir de 10 ("15", no "14.7", que en español parece catorce mil)
function ES.Num(x)
  if not x then return "—" end
  if math.abs(x) >= 10 then return tostring(math.floor(x + 0.5)) end
  local s = string.format("%.1f", x):gsub("%.0$", "")
  if ES.lang == "es" or ES.lang == "de" then s = s:gsub("%.", ",") end -- en inglés, punto decimal
  return s
end

function ES:Print(msg)
  print("|cff33ccffCrafter's Journal|r: " .. tostring(msg))
end

-- Clave por reino + casa de subastas: la de tu facción y la neutral (goblins de
-- Bahía del Botín, Gadgetzan, Vista Eterna) tienen subastas distintas.
local function FactionKey()
  return (GetRealmName() or "?") .. "-" .. (UnitFactionGroup("player") or "?")
end

-- La AH de tu facción: la neutral no tiene soporte (ver DetectAuctionHouse). Antes era
-- la última AH que abrió el personaje (ES.db.activeAH): quien pasó por la neutral se
-- quedaba con sus precios; ya no se lee
function ES:RealmKey()
  return FactionKey()
end

-- Al abrir la AH: el subastador neutral (Bahía del Botín, Gadgetzan, Vista Eterna) no
-- es de ninguna de las dos facciones. La AH neutral no tiene soporte: el addon hace
-- como si no hubiera ninguna AH abierta (ni escanea, ni lee el escaneo de otro addon,
-- ni abre sus ventanas) y sigue con los precios de la de tu facción. Antes pasaba a
-- usar los de la neutral, casi nunca escaneada, y las rutas se quedaban sin precios
-- hasta volver a abrir la de tu facción. Devuelve true si es la neutral
local function DetectAuctionHouse()
  local npcFaction = UnitFactionGroup("npc")
  local neutral = UnitExists("npc") and npcFaction ~= "Alliance" and npcFaction ~= "Horde"
  ES.neutralAH = neutral or nil
  if neutral and not ES.neutralWarned then
    ES.neutralWarned = true -- (una vez por sesión: no en cada visita)
    ES:Print(L["Casa de Subastas neutral: Crafter's Journal no le da soporte. Aquí no escanea ni abre sus ventanas; sus rutas y precios siguen siendo los de la Casa de Subastas de tu facción."])
  end
  return neutral
end

-- Personaje actual ("Nombre-Reino"): buzón, recetas sabidas, AH activa
function ES:CharKey()
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function ApplyDefaults(db, defaults)
  for k, v in pairs(defaults) do
    if type(v) == "table" then
      if type(db[k]) ~= "table" then db[k] = {} end
      ApplyDefaults(db[k], v)
    elseif db[k] == nil then
      db[k] = v
    end
  end
end

-- Helpers de objetos compatibles con API antigua y moderna
local GetItemInfoCompat = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstantCompat = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

-- Nombres propios (recetas y objetos) del idioma del addon: Data/Names_esES.lua o
-- Data/Names_deDE.lua; nil en inglés, que es el idioma de los datos
function ES:LangNames()
  return (self.lang == "es" and ES.Data.NamesES) or (self.lang == "de" and ES.Data.NamesDE) or nil
end

-- Nombre de un objeto en el idioma del addon según los datos propios: español
-- (Data/Names_esES.lua), alemán (Data/Names_deDE.lua) o inglés (ES.Data.ItemNames);
-- nil si no lo tenemos
function ES:DataItemName(itemID)
  local names = self:LangNames()
  local name = names and names.items[itemID]
  if name then return name end
  return ES.Data.ItemNames and ES.Data.ItemNames[itemID] -- en español o alemán, si no cambia, es igual que en inglés
end

-- Datos de un objeto. El nombre que da el juego va en el idioma del cliente: si el
-- addon está en otro idioma, se usa el de los datos propios (si lo tenemos)
function ES:GetItemData(itemID)
  local name, _, quality, _, _, _, _, _, _, texture = GetItemInfoCompat(itemID)
  if not texture and GetItemInfoInstantCompat then
    texture = select(5, GetItemInfoInstantCompat(itemID))
  end
  if name and self.lang ~= ES.DefaultLanguage() then name = self:DataItemName(itemID) or name end
  return name, quality, texture
end

-- Recetas con el nombre en el idioma del addon: en español, el de Data/Names_esES.lua;
-- en alemán, el de Data/Names_deDE.lua; en inglés, el original (guardado en nameEN,
-- que también usa el buscador)
function ES:LocalizeRecipeNames()
  local names = self:LangNames()
  names = names and names.spells or {}
  for _, prof in ipairs(self.PROFESSIONS) do
    for id, r in pairs(ES.Data[prof.key] and ES.Data[prof.key].recipes or {}) do
      if names[id] then
        r.nameEN = r.nameEN or r.name
        r.name = names[id]
      elseif r.nameEN then
        r.name = r.nameEN
      end
    end
  end
end

-- Cuántas unidades tienes de cada material de una profesión. Solo las bolsas: el
-- banco (y el correo) no se cuentan, lo que no llevas encima no se puede usar ya
-- y solo daba malentendidos ("tienes 88" con las chatarras ya convertidas)
-- Unidades de un objeto en las bolsas
function ES:ItemCount(itemID)
  local get = (C_Item and C_Item.GetItemCount) or GetItemCount
  return get and (get(itemID, false) or 0) or 0
end

-- ¿El personaje ya sabe esta receta? (las recetas son hechizos del libro de hechizos)
function ES:IsRecipeKnown(spellID)
  if not spellID or spellID <= 0 then return false end
  if C_SpellBook and C_SpellBook.IsSpellKnown then
    local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID)
    if ok and known then return true end
  end
  if IsPlayerSpell then
    local ok, known = pcall(IsPlayerSpell, spellID)
    if ok and known then return true end
  end
  return false
end

-- Especializaciones (recipe.spec): el hechizo que se aprende al elegirla
local SPEC_SPELLS = {
  Armorsmith = 9788, Weaponsmith = 9787, Gnomish = 20219, Goblin = 20222,
  Dragonscale = 10656, Elemental = 10658, Tribal = 10660,
}
function ES:HasSpecialization(spec)
  return self:IsRecipeKnown(SPEC_SPELLS[spec])
end

---------------------------------------------------------------------------
-- Working Overtime (talento de legado de Forever, árbol de Professions): +4% de
-- probabilidad de subir punto por rango (5 rangos: +20%). El árbol de legado es un
-- árbol de talentos moderno (C_Traits, sistema 45), y se lee como lo lee Questie su
-- talento Diplomat: el nodo cuyo hechizo es Working Overtime, y su rango comprado.
-- Se reconoce por su hechizo (1225451, Warcraft Wiki / Wowhead) o, si cambiara, por
-- el nombre; el ID encontrado se guarda (ES.db.overtimeSpell).
-- Se SUMA a la probabilidad (+20 puntos), como "aumenta tu probabilidad" en WoW.
-- Ninguna fuente dice si suma o multiplica (Wowhead: "Aura #657", valores
-- 4/8/12/16/20); si se midiera que multiplica, se cambia en Planner.Chance
---------------------------------------------------------------------------
local LEGACY_SYSTEM_ID = 45
local OVERTIME_SPELL = 1225451
local OVERTIME_NAME = "Working Overtime"
local OVERTIME_ICON = "Interface\\Icons\\INV_Misc_PocketWatch_03"
ES.OVERTIME_PER_RANK = 0.04

-- Icono del talento (el del juego; si no lo da, el reloj de bolsillo de su ficha)
function ES:OvertimeIcon()
  local spellID = (self.db and self.db.overtimeSpell) or OVERTIME_SPELL
  if C_Spell and C_Spell.GetSpellTexture then
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
    if ok and tex then return tex end
  end
  if GetSpellTexture then
    local ok, tex = pcall(GetSpellTexture, spellID)
    if ok and tex then return tex end
  end
  return OVERTIME_ICON
end

local function SpellNameOf(spellID)
  if C_Spell and C_Spell.GetSpellName then
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if ok and name then return name end
  end
  if GetSpellInfo then
    local ok, name = pcall(GetSpellInfo, spellID)
    if ok then return name end
  end
end

-- Rango de Working Overtime (0-5) y su hechizo, o nil si el juego no deja leerlo
function ES:ReadWorkingOvertime()
  local T = C_Traits
  if not (T and T.GetConfigIDBySystemID and T.GetConfigInfo and T.GetTreeNodes and T.GetNodeInfo
    and T.GetEntryInfo and T.GetDefinitionInfo) then return nil end
  local ok, configID = pcall(T.GetConfigIDBySystemID, LEGACY_SYSTEM_ID)
  if not ok or not configID then return nil end
  local okInfo, configInfo = pcall(T.GetConfigInfo, configID)
  if not okInfo or not configInfo or not configInfo.treeIDs then return nil end
  local known = self.db and self.db.overtimeSpell
  for _, treeID in ipairs(configInfo.treeIDs) do
    local okNodes, nodes = pcall(T.GetTreeNodes, treeID)
    for _, nodeID in ipairs(okNodes and nodes or {}) do
      local okNode, node = pcall(T.GetNodeInfo, configID, nodeID)
      for _, entryID in ipairs(okNode and node and node.entryIDs or {}) do
        local okEntry, entry = pcall(T.GetEntryInfo, configID, entryID)
        local okDef, def = false, nil
        if okEntry and entry and entry.definitionID then okDef, def = pcall(T.GetDefinitionInfo, entry.definitionID) end
        local spellID = okDef and def and def.spellID
        if spellID and (spellID == OVERTIME_SPELL or spellID == known or SpellNameOf(spellID) == OVERTIME_NAME
          or def.overrideName == OVERTIME_NAME) then
          if self.db then self.db.overtimeSpell = spellID end
          return node.currentRank or node.ranksPurchased or 0, spellID
        end
      end
    end
  end
  return 0, nil -- (el árbol se lee, pero no tiene el talento)
end

-- Lee el rango y, si cambió, lo aplica a las rutas (Planner.SKILL_BONUS) y las rehace
function ES:UpdateSkillUpBonus()
  local rank = self:ReadWorkingOvertime()
  if rank == nil then return end -- (sin datos aún: se queda lo que había)
  local bonus = rank * ES.OVERTIME_PER_RANK
  self.overtimeRank = rank
  if ES.Planner and ES.Planner.SKILL_BONUS ~= bonus then
    ES.Planner.SKILL_BONUS = bonus
    if self.ClearHomeCache then self:ClearHomeCache() end
    if self.RefreshAllViews then pcall(self.RefreshAllViews, self) end
  end
  -- (el indicador de la cabecera, si la ventana está creada)
  if self.RefreshOvertimeBadge then pcall(self.RefreshOvertimeBadge, self) end
end

do
  local f = CreateFrame("Frame")
  -- (con pcall: ES.SafeRegister se define más abajo; un evento que el cliente no tenga, se salta)
  for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CHANGED" }) do
    pcall(f.RegisterEvent, f, e)
  end
  f:SetScript("OnEvent", function()
    if not ES.db then return end
    -- (al entrar el árbol puede no estar aún: se mira otra vez un poco después)
    ES:UpdateSkillUpBonus()
    if C_Timer then C_Timer.After(3, function() if ES.db then ES:UpdateSkillUpBonus() end end) end
  end)
end

---------------------------------------------------------------------------
-- Reputación (recetas que piden un nivel con una facción: rep = { facción, nivel })
---------------------------------------------------------------------------
-- Nombres por si el juego aún no conoce la facción (no la has descubierto)
local FACTION_NAMES = ES.Localize({
  [59] = "Hermandad del Torio", [270] = "Tribu Zandalar", [529] = "El Alba Argenta",
  [576] = "Bastión Fauces de Madera", [609] = "Círculo Cenarion", [749] = "Srs. del Agua de Hydraxis",
})

-- Nivel actual con la facción (1 odiado ... 4 neutral ... 8 exaltado); neutral si no la conoces
function ES:Standing(factionID)
  if C_Reputation and C_Reputation.GetFactionDataByID then
    local ok, data = pcall(C_Reputation.GetFactionDataByID, factionID)
    if ok and data and data.reaction then return data.reaction, data.name end
  end
  if GetFactionInfoByID then
    local ok, name, _, standing = pcall(GetFactionInfoByID, factionID)
    if ok and standing then return standing, name end
  end
  return 4, nil
end

function ES:FactionName(factionID)
  local _, name = self:Standing(factionID)
  return name or FACTION_NAMES[factionID] or (L["facción "] .. factionID)
end

function ES.StandingName(standing)
  return _G["FACTION_STANDING_LABEL" .. standing] or (L["nivel "] .. standing)
end

-- ¿Tienes la reputación que pide? (sin requisito, sí)
function ES:RepMet(rep)
  return not rep or (self:Standing(rep[1])) >= rep[2]
end

-- Firma de tus niveles con las facciones que piden recetas: cambia solo al subir
-- de nivel (UPDATE_FACTION salta con cada punto de reputación)
function ES:RepStamp()
  if not self.repFactions then
    self.repFactions = {}
    local seen = {}
    for _, data in pairs(ES.Data) do
      if type(data) == "table" and data.recipes then
        for _, r in pairs(data.recipes) do
          if r.rep and not seen[r.rep[1]] then
            seen[r.rep[1]] = true
            self.repFactions[#self.repFactions + 1] = r.rep[1]
          end
        end
      end
    end
    table.sort(self.repFactions)
  end
  local parts = {}
  for i, f in ipairs(self.repFactions) do parts[i] = (self:Standing(f)) end
  return table.concat(parts, ",")
end

function ES:GetOwnedReagents(data)
  local owned, seen = {}, {}
  for _, r in pairs(data.recipes) do
    for _, rq in ipairs(r.r) do
      local itemID = rq[1]
      if not seen[itemID] then
        seen[itemID] = true
        local count = ES:ItemCount(itemID)
        if count and count > 0 then owned[itemID] = count end
      end
    end
  end
  -- Herramientas (bastones rúnicos)
  for _, tool in pairs(ES.Data.Tools or {}) do
    local count = ES:ItemCount(tool.item)
    if count and count > 0 then owned[tool.item] = count end
  end
  return owned
end

---------------------------------------------------------------------------
-- Botón del minimapa: con LibDBIcon (la librería estándar), no un botón propio.
-- Leatrix Plus avisaba ("This is a custom button. Please ask the addon author to use
-- the standard LibDBIcon library") y los addons que agrupan botones del minimapa
-- (MinimapButtonButton...) no lo reconocían. ES.db.minimap = { hide, minimapPos }:
-- la posición de antes (angle, en grados y con la misma convención) se conserva
---------------------------------------------------------------------------
local MINIMAP_NAME = "CraftersJournal"

local function CreateMinimapButton()
  local db = ES.db.minimap
  if db.minimapPos == nil and db.angle then db.minimapPos = db.angle % 360 end
  db.angle = nil
  local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
  local icon = LibStub and LibStub("LibDBIcon-1.0", true)
  if not (LDB and icon) then return end
  local object = LDB:NewDataObject(MINIMAP_NAME, {
    type = "launcher",
    text = "Crafter's Journal",
    icon = ES.ICON,
    OnClick = function() ES:ToggleMainFrame() end,
    OnTooltipShow = function(tt)
      tt:AddLine("Crafter's Journal")
      tt:AddLine(L["Clic: abrir/cerrar panel"], 1, 1, 1)
      tt:AddLine(L["Arrastrar: mover botón"], 1, 1, 1)
    end,
  })
  if not icon:IsRegistered(MINIMAP_NAME) then icon:Register(MINIMAP_NAME, object, db) end
  ES.minimapIcon = icon
end
ES.CreateMinimapButton = CreateMinimapButton -- (pruebas)

-- Enseñar u ocultar el botón (/cj minimap)
function ES:SetMinimapShown(show)
  self.db.minimap.hide = not show or nil
  if not self.minimapIcon then return end
  if show then self.minimapIcon:Show(MINIMAP_NAME) else self.minimapIcon:Hide(MINIMAP_NAME) end
end

-- Recalcula todos los apartados que dependen de los datos de la AH activa (tras
-- un escaneo o al cambiar de AH). Lo que no está a la vista se recalcula al mostrarse.
function ES:RefreshAllViews()
  if self.ClearHomeCache then self:ClearHomeCache() end        -- precios nuevos: planes de las tarjetas
  if self.RenderHome then self:RenderHome() end                -- portada (tarjetas)
  if self.RefreshProfessionPages then self:RefreshProfessionPages() end -- planes de cada profesión
  if self.Earn then self.Earn:Clear() end                       -- Ganar dinero
  if self.RenderEarn then self:RenderEarn() end
  if self.RenderInventory then self:RenderInventory() end      -- Inventario
  if self.RefreshPatternPages then self:RefreshPatternPages() end -- Colección de recetas
  if self.RenderCalculator then self:RenderCalculator() end    -- Calculadora (sus precios salen del escaneo)
  if self.RenderShopping then self:RenderShopping() end        -- Lista de compra
end

-- Menú de addons del minimapa (compartment)
function CraftersJournal_OnAddonCompartmentClick()
  ES:ToggleMainFrame()
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
-- Registro protegido: si un evento no existe en este cliente, no rompe la carga del addon
function ES.SafeRegister(frame, event)
  local ok = pcall(frame.RegisterEvent, frame, event)
  return ok
end
-- Lo de cada personaje: las rutas empezadas, los ajustes de cada profesión (objetivo,
-- opciones, recetas quitadas) y la última profesión vista. Se guarda en
-- ES.db.characters[GUID del personaje]; mientras juegas, ES.db.prof y ES.db.lastProf
-- son los suyos. Así otro personaje no ve tu ruta, y al volver con este la recuperas.
-- Por GUID y no por "nombre-reino": en Forever varios personajes de la cuenta
-- pueden llamarse igual en el mismo reino (Ventura...) y compartían rutas.
local PENDING = "pending" -- el juego aún no da el GUID (se corrige al entrar al mundo)
local function CharDataKey()
  local guid = UnitGUID and UnitGUID("player")
  return (type(guid) == "string" and guid ~= "") and guid or PENDING
end

local function LoadCharacterData()
  local db = ES.db
  local key = CharDataKey()
  -- Lo guardado por nombre (ES.db.chars) o para toda la cuenta no se sabe de qué
  -- personaje es: no se reparte (cada uno empieza de cero una vez)
  db.chars, db.charsMigrated = nil, nil
  db.characters = db.characters or {}
  local c = db.characters[key] or {}
  db.characters[key] = c
  c.prof = c.prof or {}
  -- El máximo pasó de 225 a 300: el objetivo guardado en 225 era el máximo de
  -- antes, no uno elegido; pasa al nuevo (una vez; una ruta empezada no se toca)
  if not c.max300 then
    for _, settings in pairs(c.prof) do
      if type(settings) == "table" and settings.target == 225 and not settings.lock then settings.target = nil end
    end
    c.max300 = true
  end
  -- El objetivo por defecto pasó del máximo a tu nivel + 150 (las rutas largas tardan
  -- mucho en calcularse). Antes se guardaba siempre: el 300 guardado era el de
  -- entonces, no uno elegido; pasa al nuevo (una vez; una ruta empezada no se toca)
  if not c.target150 then
    for _, settings in pairs(c.prof) do
      if type(settings) == "table" and settings.target == 300 and not settings.lock then settings.target = nil end
    end
    c.target150 = true
  end
  -- El objetivo por defecto pasó de tu nivel + 150 (151, 152...) al final de tu tope
  -- (150, 225 o 300). Los guardados que no son uno de esos salían de ese nivel + 150
  -- (al subir, el anterior se quedaba guardado): fuera, una vez (sin tocar rutas empezadas)
  if not c.targetCaps then
    for _, settings in pairs(c.prof) do
      local t = type(settings) == "table" and settings.target
      if t and not settings.lock and t ~= 150 and t ~= 225 and t ~= 300 then settings.target = nil end
    end
    c.targetCaps = true
  end
  c.books = nil -- (la contabilidad del dinero ya no existe: fuera lo que guardó)
  db.tabs = nil -- (orden y pestañas ocultas: se quitó de Opciones)
  db.autoCraft = nil -- (pulsar un paso siempre fabrica: ya no es una opción)
  for _, settings in pairs(c.prof) do -- (ruta sin AH: ya no existe; la ruta siempre puede usarla)
    if type(settings) == "table" then settings.useAH = nil end
  end
  -- Las listas de la compra de una ruta ya no se añaden a mano: con la ruta empezada
  -- salen solas (Shopping.PhaseList). Las guardadas de antes se quitan, una vez
  if not c.routeListsLive and type(c.shopping) == "table" then
    for i = #c.shopping, 1, -1 do
      if type(c.shopping[i]) == "table" and c.shopping[i].kind == "route" then table.remove(c.shopping, i) end
    end
  end
  c.routeListsLive = true
  db.prof, db.lastProf = c.prof, c.lastProf
  ES.charData, ES.charDataKey = c, key
end

-- Al entrar al mundo el GUID ya es seguro: si al cargar el addon el juego aún no lo
-- daba, lo de esta sesión (guardado como pendiente) pasa a ser de este personaje
local function CheckCharacterData()
  local key = CharDataKey()
  if not ES.charDataKey or ES.charDataKey == key or key == PENDING then return end
  local db = ES.db
  local old = db.characters[ES.charDataKey]
  db.characters[ES.charDataKey] = nil
  if ES.charDataKey == PENDING and not db.characters[key] then db.characters[key] = old end
  LoadCharacterData()
end

-- Al salir: lo del personaje queda solo en ES.db.characters (sin copias sueltas en ES.db)
local function SaveCharacterData()
  if not (ES.db and ES.charData) then return end
  ES.charData.lastProf = ES.db.lastProf
  ES.db.prof, ES.db.lastProf = nil, nil
end

ES.LoadCharacterData, ES.SaveCharacterData = LoadCharacterData, SaveCharacterData -- para pruebas

---------------------------------------------------------------------------
-- Registro de errores: los errores de Lua de este addon y las acciones que el
-- juego le bloquea se apuntan en CraftersJournalDB.errorLog (los mismos juntos,
-- con cuántas veces), para revisarlos después (/cj errores, o el archivo de
-- SavedVariables). Siguen saliendo como siempre (ventana de errores, BugSack...).
---------------------------------------------------------------------------
local MAX_ERRORS = 50

local function AddonVersion()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  return get and get(ADDON_NAME, "Version") or "?"
end

function ES:RecordError(kind, msg, stack)
  if not self.db then return end
  msg = tostring(msg or "?"):sub(1, 300)
  self.db.errorLog = self.db.errorLog or {}
  local log, now = self.db.errorLog, time()
  for _, e in ipairs(log) do
    if e.kind == kind and e.msg == msg then
      e.count, e.last = e.count + 1, now
      return
    end
  end
  log[#log + 1] = { kind = kind, msg = msg, stack = stack and tostring(stack):sub(1, 1500) or nil, count = 1,
    first = now, last = now, version = AddonVersion() }
  while #log > MAX_ERRORS do table.remove(log, 1) end
end

do
  -- Errores de Lua: solo los que pasan por los archivos de este addon. Se apunta
  -- y se pasa al manejador que hubiera (el del juego, BugGrabber...). Si otro addon
  -- de errores se carga después y pone el suyo, al entrar al mundo se vuelve a
  -- enganchar delante (busy: por si los dos se llaman entre sí)
  local previous, busy
  local function Handler(msg, ...)
    if busy then return end -- (el otro manejador nos ha vuelto a llamar: se corta aquí)
    busy = true
    local stack = debugstack and debugstack(2) or ""
    if tostring(msg):find(ADDON_NAME, 1, true) or stack:find(ADDON_NAME, 1, true) then
      pcall(ES.RecordError, ES, "lua", msg, stack)
    end
    if previous then pcall(previous, msg, ...) end
    busy = false
  end
  local function Install()
    if not (geterrorhandler and seterrorhandler) then return end
    local current = geterrorhandler()
    if current ~= Handler then
      previous = current
      seterrorhandler(Handler)
    end
  end
  Install()
  -- Acciones bloqueadas por el juego (funciones protegidas)
  local f = CreateFrame("Frame")
  ES.SafeRegister(f, "ADDON_ACTION_BLOCKED")
  ES.SafeRegister(f, "ADDON_ACTION_FORBIDDEN")
  ES.SafeRegister(f, "PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", function(_, event, addon, func)
    if event == "PLAYER_ENTERING_WORLD" then Install() return end
    if addon == ADDON_NAME then
      ES:RecordError(event == "ADDON_ACTION_FORBIDDEN" and "prohibida" or "bloqueada", tostring(func),
        debugstack and debugstack(2) or nil)
    end
  end)
end

ES.SafeRegister(events, "ADDON_LOADED")
ES.SafeRegister(events, "PLAYER_LOGIN")
ES.SafeRegister(events, "PLAYER_LOGOUT")
ES.SafeRegister(events, "AUCTION_HOUSE_SHOW")
ES.SafeRegister(events, "AUCTION_HOUSE_CLOSED")
ES.SafeRegister(events, "UPDATE_FACTION")

events:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
    CraftersJournalDB = CraftersJournalDB or {}
    ApplyDefaults(CraftersJournalDB, DEFAULTS)
    ES.db = CraftersJournalDB
    LoadCharacterData()
    ES.lang = ES.db.lang or ES.DefaultLanguage()
    ES.db.lastGetAll, ES.db.serverLimit = nil, nil -- claves de versiones anteriores (ver Scanner.lua)
    -- (de versiones anteriores: modo desarrollo, pestaña Subastas y comandos de depuración)
    ES.db.userPreview, ES.db.topSortBy, ES.db.topWindow, ES.db.debugFrame, ES.db.trainerFeesCSV = nil, nil, nil, nil, nil
    ES.db.useGPS = nil -- (/cj gps de las pruebas: el GPS ya es el planificador de todos)
    ES.db.mail = nil   -- (lo que se leía del buzón en versiones anteriores: ya no se guarda nada del correo)
    ES.db.earnBudget = nil -- (presupuesto de Ganar dinero: ya no existe)
    ES.db.activeAH = nil -- (la última AH abierta: siempre es la de tu facción, ver RealmKey)
    ES.db.sellGear = nil -- (la opción del equipo es ahora protectGear, desactivada por defecto)
    ES.db.atrPrices = nil -- (precios de las búsquedas en Auctionator: ya no hay botón)
    ES.ApplyLocalization()
    ES:LocalizeRecipeNames()
  elseif event == "PLAYER_LOGOUT" then
    SaveCharacterData()
  elseif event == "PLAYER_LOGIN" then
    CheckCharacterData()
    ES:DropOtherFactionRecipes()
    CreateMinimapButton()
    ES.repStamp = ES:RepStamp()
  elseif event == "UPDATE_FACTION" then
    -- Al subir de nivel con una facción, las recetas que pedía pasan a estar disponibles
    local stamp = ES:RepStamp()
    if ES.repStamp and stamp ~= ES.repStamp then
      ES.repStamp = stamp
      if ES.ClearHomeCache then ES:ClearHomeCache() end
      if ES.RenderHome then ES:RenderHome() end
      if ES.RefreshProfessionPages then ES:RefreshProfessionPages() end
      if ES.RefreshPatternPages then ES:RefreshPatternPages() end
    end
    ES.repStamp = stamp
  elseif event == "AUCTION_HOUSE_SHOW" then
    ES:ScanLog("AUCTION_HOUSE_SHOW")
    ES.ahSession = (ES.ahSession or 0) + 1
    -- La neutral: como si no hubiera AH abierta (sin botones ni ventanas del addon)
    if DetectAuctionHouse() then
      ES:ScanLog("AH neutral: sin soporte")
      if ES.HideAuctionHouseUI then ES:HideAuctionHouseUI() end
      ES:RefreshScanButtons()
      return
    end
    ES.ahOpen = true
    ES:RefreshScanButtons() -- lo primero: si algo de abajo falla, el botón ya está activo
    -- Antes que los addons que escanean solos al abrir (ForeverForge, a los 3 s)
    pcall(ES.Scanner.InstallHooks, ES.Scanner)
    ES:OnAuctionHouseShow()
    ES:RefreshAllViews()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    -- Puede llegar con la ventana aún abierta (p. ej. tras un escaneo completo):
    -- solo cuenta como cerrada si la ventana de la AH ya no se ve
    ES:ScanLog("AUCTION_HOUSE_CLOSED, ventana visible: " .. tostring(AHFrameShown()))
    local session = ES.ahSession
    C_Timer.After(0.2, function()
      if session ~= ES.ahSession or AHFrameShown() then return end -- ya se reabrió, o sigue abierta
      ES.ahOpen = false
      ES.neutralAH = nil
      -- El servidor ya contó la petición: hay que esperar sus 15 min igualmente
      ES.Scanner:Abort(string.format(L["Has cerrado la Casa de Subastas; escaneo cancelado. Déjala abierta hasta que termine. Podrás volver a escanear en %s."],
        ES.Countdown(ES.Scanner:SecondsUntilNextScan())))
      ES:RefreshScanButtons()
    end)
  end
end)

---------------------------------------------------------------------------
-- Comandos
---------------------------------------------------------------------------
SLASH_CRAFTERSJOURNAL1 = "/craftersjournal"
SLASH_CRAFTERSJOURNAL2 = "/cj"
SLASH_CRAFTERSJOURNAL3 = "/es" -- el de antes (cuando se llamaba EasySkills)
SlashCmdList.CRAFTERSJOURNAL = function(msg)
  msg = strtrim(msg or ""):lower()
  if msg == "scan" then
    ES:ShowMainFrame()
    ES.Scanner:Start()
  elseif msg == "cancel" then
    if ES.Scanner:IsBusy() then
      ES.Scanner:Abort(L["Escaneo cancelado."])
    else
      ES:Print(L["No hay ningún escaneo en curso."])
    end
  elseif msg == "opciones" or msg == "options" or msg == "config" then
    ES:OpenOptions()
  elseif msg == "minimap" then
    ES:SetMinimapShown(ES.db.minimap.hide and true or false)
  elseif msg == "errores" or msg == "errors" or msg == "errores borrar" or msg == "errors clear" then
    -- Lo apuntado por ES:RecordError (ver arriba)
    if msg:find(" ") then
      ES.db.errorLog = nil
      ES:Print(L["Registro de errores vaciado."])
      return
    end
    local log = ES.db.errorLog or {}
    if #log == 0 then
      ES:Print(L["Ningún error registrado."])
      return
    end
    ES:Print(string.format(L["%d errores distintos registrados (el más reciente al final):"], #log))
    for _, e in ipairs(log) do
      print(string.format("|cffff6060[%s]|r x%d %s %s%s", e.kind, e.count, date and date("%d/%m %H:%M", e.last) or "",
        e.msg, ""))
    end
    ES:Print(L["Detalle completo en CraftersJournalDB.errorLog (SavedVariables, tras /reload). /cj errores borrar para vaciarlo."])
  else
    ES:ToggleMainFrame()
  end
end
