local _, ES = ...
local L = ES.L

-- Ir al instructor o al vendedor más cercano:
--   · Qué instructor enseña qué profesión y hasta qué nivel viene en los datos
--     (ES.Data.<Profesión>.trainers, de QuestieDB); quién vende un objeto y dónde
--     está cada PNJ, en Data/Sources.lua (de QuestieDB), o de QuestieDB en el juego.
--   · El más cercano: por distancia en línea recta en tu continente; con Shortest
--     Path Forever, entre los más cercanos, por tiempo de viaje.
--   · El camino: la ruta de Shortest Path Forever si está, si no la flecha de
--     TomTom, si no el punto de ruta del mapa del juego en seguimiento (sale en
--     el minimapa y en la lista de seguimiento).

local WP = {}
ES.Waypoints = WP

local CONTRACT = 2 -- versión del contrato de LibQuestieDB para la que está escrito
-- Imprescindible: vendedores y PNJ. Opcional: misiones (si esta QuestieDB no
-- las trae, instructores y vendedores siguen funcionando)
local FIELDS = {
  Item = { "vendors" },
  Npc = { "name", "spawns", "zoneID", "friendlyToFaction" },
}
local QUEST_FIELDS = {
  Item = { "vendors", "questRewards" },
  Quest = { "name", "startedBy", "requiredLevel", "requiredRaces" },
}
local hasQuests = false
-- Razas (máscara de requiredRaces): Humano, Enano, Elfo de la noche, Gnomo | Orco, No-muerto, Tauren, Trol
local ALLIANCE_RACES, HORDE_RACES = 77, 178
local SIDES = { A = "A", H = "H", AH = "" }
local FACTION_CODES = { Alliance = "A", Horde = "H" }
-- Capitales por área: un PNJ "amistoso con ambos" dentro de una solo atiende a ese bando
local CAPITALS = { [1519] = "A", [1537] = "A", [1657] = "A", [1637] = "H", [1497] = "H", [1638] = "H" }
local MAX_ESTIMATES = 6 -- cuántos de los más cercanos se miden por tiempo de viaje

-- Libros de rango Experto de las secundarias (se compran a un vendedor)
WP.RANK_BOOKS = { Cooking = { [225] = 16072 }, FirstAid = { [225] = 16084 } }

local lib, zones, npcs, items = nil, nil, {}, {}

-- Tablas de zonas de QuestieDB (las guarda como código Lua de una tabla)
local function Table(source)
  local chunk = type(source) == "string" and loadstring(source)
  if not chunk then return nil end
  setfenv(chunk, {})
  local ok, value = pcall(chunk)
  return ok and type(value) == "table" and value or nil
end

-- QuestieDB tal como se lee aquí; nil si no está o no es la versión esperada
local function Load()
  if lib then return lib end
  local db = LibQuestieDB
  if type(db) ~= "table" or type(db.RequireContract) ~= "function" then return nil end
  local called, fits = pcall(db.RequireContract, CONTRACT)
  if not (called and fits) then return nil end
  local function Has(fieldSets)
    for name, fields in pairs(fieldSets) do
      local meta = type(db.Meta) == "table" and db.Meta[name .. "Meta"]
      local keys, reader = meta and meta[name:lower() .. "Keys"], db[name]
      if type(keys) ~= "table" or type(reader) ~= "table" or type(reader.GetAll) ~= "function" then return false end
      for _, field in ipairs(fields) do
        if not keys[field] then return false end
      end
    end
    return true
  end
  if not Has(FIELDS) then return nil end
  hasQuests = Has(QUEST_FIELDS)
  local zoneDB = type(db.Support) == "table" and type(db.Support.Get) == "function" and db.Support.Get("ZoneDB")
  local private = type(zoneDB) == "table" and zoneDB.private
  if type(private) ~= "table" then return nil end
  local area, parent = Table(private.areaIdToUiMapId), Table(private.subZoneToParentZone)
  if not (area and parent) then return nil end
  zones = {
    area = area, parent = parent,
    areaOverride = Table(private.areaIdToUiMapIdOverride) or {},
    parentOverride = Table(private.subZoneToParentZoneOverride) or {},
  }
  lib = db
  return lib
end

-- Vacía lo leído (para pruebas, o si cambian los datos)
function WP.ResetCache()
  npcs, items = {}, {}
end

-- ¿Se sabe dónde está cada PNJ? Con los datos propios (Data/Sources.lua,
-- generados desde QuestieDB) siempre; si faltaran, con QuestieDB en el juego.
function WP.Available()
  return ES.Data.NPCs ~= nil or Load() ~= nil
end

local function Map(area)
  local map = zones.areaOverride[area] or zones.area[area]
  local parent = not map and (zones.parentOverride[area] or zones.parent[area])
  map = map or (parent and (zones.areaOverride[parent] or zones.area[parent]))
  return type(map) == "number" and map or nil
end

-- Un punto al que apuntar: en la zona habitual del PNJ, el aparecimiento más
-- cercano al centro de los suyos (QuestieDB da 0-100 en el mapa de la zona)
local function Spawn(spawns, home)
  if type(spawns) ~= "table" then return nil end
  local area = type(spawns[home]) == "table" and home or nil
  if not area then
    for candidate in pairs(spawns) do
      if type(candidate) == "number" and (not area or candidate < area) then area = candidate end
    end
  end
  local spots, sumX, sumY = {}, 0, 0
  for _, xy in ipairs(area and type(spawns[area]) == "table" and spawns[area] or {}) do
    local x, y = tonumber(xy[1]), tonumber(xy[2])
    if x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
      spots[#spots + 1] = { x, y }
      sumX, sumY = sumX + x, sumY + y
    end
  end
  local best, bestDistance
  for _, spot in ipairs(spots) do
    local d = (spot[1] - sumX / #spots) ^ 2 + (spot[2] - sumY / #spots) ^ 2
    if not bestDistance or d < bestDistance then best, bestDistance = spot, d end
  end
  if not best then return area end
  return area, best[1] / 100, best[2] / 100
end

-- Nombre, bando y sitio de un PNJ (mapa y coordenadas 0-1), o nil
function WP.NPC(npcID)
  if npcs[npcID] ~= nil then return npcs[npcID] or nil end
  local npc = false
  local baked = ES.Data.NPCs and ES.Data.NPCs[npcID]
  if baked then
    npc = { name = baked[1], side = baked[2] }
    if baked[3] and baked[3] ~= 0 then
      npc.map, npc.x, npc.y = baked[3], baked[4], baked[5]
    else
      npc.area = baked[6] -- mazmorra: solo el nombre de la zona
    end
    npcs[npcID] = npc
    return npc
  end
  local values = Load() and lib.Npc.GetAll(npcID, FIELDS.Npc)
  if values and type(values[1]) == "string" then
    local area, x, y = Spawn(values[2], values[3])
    local side = SIDES[values[4]]
    if side == "" and area then
      side = CAPITALS[area] or CAPITALS[zones.parentOverride[area] or zones.parent[area]] or ""
    end
    npc = { name = values[1], side = side }
    local map = area and x and Map(area)
    if map then npc.map, npc.x, npc.y = map, x, y else npc.area = area end
  end
  npcs[npcID] = npc
  return npc or nil
end

local function IDs(list)
  local out = {}
  for _, id in ipairs(type(list) == "table" and list or {}) do
    if type(id) == "number" then out[#out + 1] = id end
  end
  return out
end

-- Quién vende un objeto y qué misiones lo dan de recompensa
local function Item(itemID)
  if items[itemID] == nil then
    local baked = ES.Data.ItemSources and ES.Data.ItemSources[itemID]
    if baked then
      items[itemID] = { vendors = baked.v or {}, quests = baked.q or {} }
    elseif ES.Data.ItemSources and not Load() then
      items[itemID] = { vendors = {}, quests = {} } -- los datos propios no le conocen fuente
    else
      local values = Load() and lib.Item.GetAll(itemID, hasQuests and QUEST_FIELDS.Item or FIELDS.Item)
      items[itemID] = { vendors = IDs(values and values[1]), quests = IDs(hasQuests and values and values[2]) }
    end
  end
  return items[itemID]
end

function WP.Vendors(itemID)
  return Item(itemID).vendors
end

-- Botín: { npcs = { criaturas }, world = nº si es botín del mundo, levels = { mín, máx }
-- de esas criaturas, objects = nº de cofres } o nil
function WP.Drops(itemID)
  local baked = ES.Data.ItemSources and ES.Data.ItemSources[itemID]
  if not baked or not (baked.d or baked.w or baked.o) then return nil end
  return { npcs = baked.d or {}, world = baked.w, levels = baked.wl, objects = baked.o }
end

-- Nivel de una criatura que suelta pergaminos: "12" o "12-14" (nil si no se sabe)
function WP.NPCLevel(npcID)
  local lv = ES.Data.NPCLevels and ES.Data.NPCLevels[npcID]
  if not lv then return nil end
  return lv[1] == lv[2] and tostring(lv[1]) or (lv[1] .. "-" .. lv[2])
end

-- Solo la zona de un PNJ (sin coordenadas)
function WP.ZoneName(npc)
  local info = npc.map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(npc.map)
  if info then return info.name end
  return npc.area and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(npc.area) or L["lugar desconocido"]
end

local quests = {}

-- Una misión: nombre, quién la da, nivel mínimo y bando ("" los dos)
function WP.Quest(questID)
  if quests[questID] ~= nil then return quests[questID] or nil end
  local q = false
  local baked = ES.Data.Quests and ES.Data.Quests[questID]
  if baked then
    -- (asks: el texto de lo que pide entregar; chain: misiones antes en su cadena)
    q = { id = questID, name = baked[1], side = baked[2], level = baked[3] or 0, starters = baked[4] or {},
      asks = baked[5], chain = baked[6] or 0 }
    quests[questID] = q
    return q
  end
  local values = Load() and hasQuests and lib.Quest.GetAll(questID, QUEST_FIELDS.Quest)
  if values and type(values[1]) == "string" then
    local races = tonumber(values[4]) or 0
    local alliance, horde = bit.band(races, ALLIANCE_RACES) ~= 0, bit.band(races, HORDE_RACES) ~= 0
    local starters = type(values[2]) == "table" and IDs(values[2][1]) or {}
    q = { id = questID, name = values[1], starters = starters, level = tonumber(values[3]) or 0,
      side = alliance == horde and "" or (alliance and "A" or "H") }
  end
  quests[questID] = q
  return q or nil
end

-- Misiones de tu bando que dan este objeto
function WP.QuestsFor(itemID)
  local list = {}
  local mine = FACTION_CODES[UnitFactionGroup("player")]
  for _, questID in ipairs(Item(itemID).quests) do
    local q = WP.Quest(questID)
    if q and (q.side == "" or q.side == mine) then list[#list + 1] = q end
  end
  return list
end

-- Instructores de una profesión que enseñan el rango de `level`: el rango hasta
-- 150 para subir el tope a 150 o para recetas de 76 a 150, etc. En Forever cada
-- rango tiene sus instructores (Georgio Bolero solo enseña Experto); en los datos,
-- { PNJ, máscara }: 1 aprendiz, 2 oficial, 4 experto, 8 artesano.
function WP.RankBit(level)
  if level <= 75 then return 1 elseif level <= 150 then return 2 elseif level <= 225 then return 4 end
  return 8
end

function WP.Trainers(profKey, level)
  local list = {}
  local data = ES.Data[profKey]
  local bit = WP.RankBit(level)
  for _, row in ipairs(data and data.trainers or {}) do
    if math.floor(row[2] / bit) % 2 == 1 then list[#list + 1] = row[1] end
  end
  return list
end

local function Usable(npc)
  local side = npc and npc.side
  return side == "" or (side ~= nil and side == FACTION_CODES[UnitFactionGroup("player")])
end

-- Distancia al cuadrado en tu continente; infinita en otro o sin posición
local function Distance(npc)
  if not npc.map or not (C_Map and C_Map.GetWorldPosFromMapPos and UnitPosition and CreateVector2D) then return math.huge end
  if npc.world == nil then
    local ok, instance, position = pcall(C_Map.GetWorldPosFromMapPos, npc.map, CreateVector2D(npc.x, npc.y))
    npc.world = ok and instance and position and { instance, position:GetXY() } or false
  end
  local px, py, _, instance = UnitPosition("player")
  local w = npc.world
  if not (px and w) or w[1] ~= instance then return math.huge end
  return (px - w[2]) ^ 2 + (py - w[3]) ^ 2
end

local function ShortestPath()
  local api = ShortestPathForever and ShortestPathForever.API
  return api and api.version == 1 and api or nil
end

local function PlayerMapPosition()
  if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
  local map = C_Map.GetBestMapForUnit("player")
  local position = map and C_Map.GetPlayerMapPosition(map, "player")
  if not position then return nil end
  local x, y = position:GetXY()
  return { map = map, x = x, y = y }
end

-- El más cercano de tu bando entre estos PNJ, o nil. Con varios y ninguno en
-- tu continente no se elige ninguno (el orden de los datos no dice cuál está más cerca).
function WP.Nearest(npcIDs)
  local candidates = {}
  for index, npcID in ipairs(npcIDs or {}) do
    local npc = WP.NPC(npcID)
    if npc and Usable(npc) then
      candidates[#candidates + 1] = { npcID = npcID, npc = npc, distance = Distance(npc), index = index }
    end
  end
  table.sort(candidates, function(a, b)
    if a.distance ~= b.distance then return a.distance < b.distance end
    return a.index < b.index
  end)
  local first = candidates[1]
  local best = first and (first.distance < math.huge or #candidates == 1) and first or nil
  -- Con Shortest Path Forever, entre los más cercanos gana el de menos tiempo de viaje
  local api = first and not (InCombatLockdown and InCombatLockdown()) and ShortestPath()
  local from = api and type(api.Estimate) == "function" and PlayerMapPosition()
  if from then
    local bestSeconds
    for i = 1, math.min(#candidates, MAX_ESTIMATES) do
      local npc = candidates[i].npc
      local seconds = npc.map and api.Estimate(from.map, from.x, from.y, npc.map, npc.x, npc.y)
      if seconds and (not bestSeconds or seconds < bestSeconds) then best, bestSeconds = candidates[i], seconds end
    end
  end
  return best and best.npcID
end

-- PNJ de esta lista con los que tu bando puede tratar
function WP.Usable(npcIDs)
  local list = {}
  for _, npcID in ipairs(npcIDs or {}) do
    local npc = WP.NPC(npcID)
    if npc and Usable(npc) then list[#list + 1] = npcID end
  end
  return list
end

---------------------------------------------------------------------------
-- De dónde sale una receta de pergamino (prueba piloto: Cocina)
---------------------------------------------------------------------------
-- Profesiones en las que las recetas de pergamino se buscan por sus fuentes reales
-- (todas desde que las fuentes vienen en Data/Sources.lua)
WP.SOURCED_PROFESSIONS = {
  Alchemy = true, Blacksmithing = true, Cooking = true, Enchanting = true,
  Engineering = true, FirstAid = true, Leatherworking = true, Tailoring = true,
}

local sourceCache, sourceKey = {}, nil

-- Fuentes de la receta para tu personaje y la mejor (la más barata):
--   quest  = misión de tu bando que la da (gratis)
--   vendor = la vende un PNJ de tu bando (su precio)
--   ah     = la más barata anunciada ahora en la AH
-- `prices` es la tabla de precios del escaneo (ctx.prices). Sin ninguna fuente, best = nil.
-- Con `noQuests` (icono de misión desactivado) las misiones no cuentan: se listan
-- en el tooltip como desactivadas y la receta solo se consigue comprándola.
-- Con `noLimited` (opción: no contar con vendedores de stock limitado) el vendedor
-- de una receta con stock limitado (Data/Sources.lua, lim) no cuenta: se lista como
-- desactivado y la receta se consigue por misión o en la AH, si se puede
function WP.RecipeSource(recipe, prices, noQuests, noLimited)
  if not recipe.scroll then return nil end
  -- Se recalcula con otro escaneo, otro bando, el filtro de misiones o cuando Questie pasa a estar disponible
  local key = tostring(prices) .. (UnitFactionGroup("player") or "") .. tostring(WP.Available()) .. tostring(noQuests and true)
    .. tostring(noLimited and true) .. (ES.repStamp or "")
  if sourceKey ~= key then sourceCache, sourceKey = {}, key end
  local cached = sourceCache[recipe.scroll]
  if cached then return WP.WithOwned(cached, recipe.scroll) end
  local src = { options = {}, questsOff = noQuests and true or nil }
  if WP.Available() then
    src.quests = WP.QuestsFor(recipe.scroll)
    src.vendors = WP.Usable(WP.Vendors(recipe.scroll))
  else
    src.quests, src.vendors, src.noQuestie = {}, {}, true
  end
  local ah = prices and prices[recipe.scroll]
  if src.quests[1] and not noQuests then
    src.options[#src.options + 1] = { kind = "quest", cost = 0, quest = src.quests[1] }
  end
  local item = ES.Data.ItemSources and ES.Data.ItemSources[recipe.scroll]
  src.limited = item and item.lim and src.vendors[1] ~= nil or nil
  if src.vendors[1] and src.limited and noLimited then
    src.vendorsOff = true
  elseif src.vendors[1] then
    src.options[#src.options + 1] = { kind = "vendor", cost = recipe.scrollPrice or 0,
      unknownPrice = not recipe.scrollPrice }
  end
  if ah and ah.minUnit then
    src.ah = { price = ah.minUnit, listings = ah.listings or 1 }
    src.options[#src.options + 1] = { kind = "ah", cost = ah.minUnit }
  end
  -- La más barata; a igual precio, misión antes que vendedor antes que AH
  for _, o in ipairs(src.options) do
    if not src.best or o.cost < src.best.cost then src.best = o end
  end
  -- Sin la reputación que pide no se puede aprender, venga de donde venga
  if recipe.rep and not ES:RepMet(recipe.rep) then
    src.repLocked = { faction = recipe.rep[1], need = recipe.rep[2], have = (ES:Standing(recipe.rep[1])) }
    src.best = nil
  end
  sourceCache[recipe.scroll] = src
  return WP.WithOwned(src, recipe.scroll)
end

-- "Pide Amistoso con Bastión Fauces de Madera (tienes Neutral)"
function WP.RepText(lock)
  return string.format(L["Pide %s con %s (tienes %s)"], ES.StandingName(lock.need), ES:FactionName(lock.faction),
    ES.StandingName(lock.have))
end

-- Si llevas el pergamino en bolsas o banco, esa es la mejor fuente (gratis).
-- No se guarda en caché: tus bolsas cambian.
function WP.WithOwned(src, scrollID)
  local have = ES:ItemCount(scrollID)
  if have <= 0 or src.repLocked then return src end
  local owned = { kind = "owned", cost = 0, count = have }
  local copy = {}
  for k, v in pairs(src) do copy[k] = v end
  copy.owned, copy.best = have, owned
  return copy
end

-- "Zona  45, 60" de un PNJ
function WP.LocationText(npc)
  local info = npc.map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(npc.map)
  if info then return string.format("%s  %.0f, %.0f", info.name, npc.x * 100, npc.y * 100) end
  return npc.area and C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(npc.area) or L["lugar desconocido"]
end

-- Marca el camino a un PNJ: ruta de Shortest Path Forever, flecha de TomTom o
-- punto de ruta del juego en seguimiento. Devuelve true si se marcó.
function WP.SetWaypoint(npcID)
  local npc = WP.NPC(npcID)
  if not npc then return false end
  if not npc.map then
    if npc.area then -- en una mazmorra: se dice cuál
      ES:Print(string.format(L["%s está en %s."], npc.name, WP.LocationText(npc)))
    else -- PNJ nuevo de Forever que las bases de datos aún no han situado
      ES:Print(string.format(L["Aún no se sabe dónde está %s: es nuevo de Forever y las bases de datos no lo tienen situado."], npc.name))
    end
    return false
  end
  local where = WP.LocationText(npc)
  local api = ShortestPath()
  if api and type(api.Navigate) == "function" and api.Navigate("Crafter's Journal", npc.map, npc.x, npc.y, npc.name) then
    ES:Print(string.format(L["Ruta marcada hacia %s, %s."], npc.name, where))
    return true
  end
  if TomTom and TomTom.AddWaypoint then
    TomTom:AddWaypoint(npc.map, npc.x, npc.y, { title = npc.name, from = "Crafter's Journal" })
  elseif C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(npc.map) then
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(npc.map, npc.x, npc.y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  else
    ES:Print(string.format(L["%s está en %s."], npc.name, where))
    return false
  end
  ES:Print(string.format(L["Punto de ruta marcado hacia %s, %s."], npc.name, where))
  return true
end

---------------------------------------------------------------------------
-- Estrella sobre el PNJ al que te manda el addon (como RestedXP). Poner una marca
-- está protegido: el addon no puede hacerlo él solo ("bloqueado de una acción
-- solo disponible para la interfaz de Blizzard"), solo como respuesta a un clic
-- tuyo, con una macro (/targetexact nombre + /tm estrella) en un botón seguro.
---------------------------------------------------------------------------
local STAR = 1

-- Macro que selecciona al PNJ por su nombre exacto y le pone la estrella. Antes
-- quita el objetivo: si el PNJ no está cerca, /targetexact no encuentra a nadie y
-- /tm no marca a quien tuvieras seleccionado; y entonces se recupera el que
-- tenías (/targetlasttarget). En combate no hace nada
function WP.MarkMacro(name)
  return "/cleartarget [nocombat]\n/targetexact [nocombat] " .. name .. "\n/tm [nocombat,exists] " .. STAR
    .. "\n/targetlasttarget [nocombat,noexists]"
end

-- Clic en una fila de instructor o vendedor (ProfessionUI.lua): al pasar el ratón
-- se le pone encima un botón seguro invisible con la macro, así tu clic le pone la
-- estrella si está cerca y luego marca el camino como siempre. Es uno solo y cuelga
-- de UIParent: un botón seguro dentro de la ventana la volvería protegida y
-- cerrarla en combate daría el aviso de acción bloqueada. Se suelta al entrar en
-- combate (en ese momento aún se puede); en combate, la fila funciona como antes
local hover
local function ReleaseHover()
  if not hover or (InCombatLockdown and InCombatLockdown()) then return end
  if hover.row then hover.row:UnlockHighlight() end
  hover.row = nil
  hover:ClearAllPoints()
  hover:Hide()
end

function WP.HoverRow(row)
  if (InCombatLockdown and InCombatLockdown()) or not WP.Available() or not row.go then return end
  local npc = WP.NPC(row.go() or 0)
  if not (npc and npc.name) then return end
  if not hover then
    hover = CreateFrame("Button", "CraftersJournalRowMarkButton", UIParent, "SecureActionButtonTemplate")
    -- Solo el botón izquierdo, como la fila (bajando o soltando, según la opción del juego)
    hover:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
    hover:SetAttribute("type", "macro")
    -- Después de la macro, lo que haga la fila (marcar el camino, buscar en la AH...)
    hover:HookScript("PostClick", function(self, _, down)
      local onClick = not down and self.row and self.row:GetScript("OnClick")
      if onClick then onClick(self.row) end
    end)
    hover:SetScript("OnEnter", function(self)
      if not self.row then return end
      self.row:LockHighlight()
      if self.row.tooltip then self.row.tooltip(self.row) end
    end)
    hover:SetScript("OnLeave", function()
      GameTooltip:Hide()
      ReleaseHover()
    end)
    -- La rueda sigue moviendo la lista de debajo
    hover:EnableMouseWheel(true)
    hover:SetScript("OnMouseWheel", function(self, delta)
      local p = self.row
      while p and not p:GetScript("OnMouseWheel") do p = p:GetParent() end
      if p then p:GetScript("OnMouseWheel")(p, delta) end
    end)
  end
  hover.row = row
  hover:SetFrameStrata(row:GetFrameStrata())
  hover:SetFrameLevel(row:GetFrameLevel() + 5)
  hover:ClearAllPoints()
  -- Sin tapar la ✕ de la fila
  hover:SetPoint("TOPLEFT", row, "TOPLEFT")
  hover:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", row.onSkip and -28 or 0, 0)
  hover:SetAttribute("macrotext", WP.MarkMacro(npc.name))
  hover:Show()
end
WP.HoverButton = function() return hover end -- para pruebas
WP.ReleaseHover = ReleaseHover -- al cerrar la ventana (UI.lua)

-- Al entrar en combate se suelta (en ese momento aún se puede): la ventana no queda
-- atada a un botón seguro
do
  local f = CreateFrame("Frame")
  ES.SafeRegister(f, "PLAYER_REGEN_DISABLED")
  f:SetScript("OnEvent", ReleaseHover)
end

-- Para una fila de la ruta: devuelve una función que elige el PNJ al pulsar
-- (la posición del jugador puede cambiar) y las líneas del tooltip.
-- kind: "trainer" (profKey, cap), "vendor" (itemID), "auction" (subastador) o
-- "sell" (un PNJ que compra lo que fabricas: posadero o vendedor de materiales)
function WP.Target(kind, a, b)
  return function()
    if kind == "trainer" then return WP.Nearest(WP.Trainers(a, b)) end
    if kind == "auction" then return WP.Nearest(ES.Data.Auctioneers) end
    if kind == "sell" then return WP.Nearest(ES.Data.SellVendors) end
    return WP.Nearest(WP.Vendors(a))
  end
end

-- Añade al tooltip "Más cercano: nombre / zona" y qué hace el clic
function WP.AddToTooltip(label, pick)
  GameTooltip:AddLine(" ")
  if not WP.Available() then
    GameTooltip:AddLine(L["Instala Questie para ver dónde está y marcar el camino."], 0.6, 0.6, 0.6, true)
    return
  end
  local npcID = pick()
  local npc = npcID and WP.NPC(npcID)
  if not npc then
    GameTooltip:AddLine(L["No se conoce ninguno de tu bando cerca (o está en otro continente)."], 0.6, 0.6, 0.6, true)
    return
  end
  GameTooltip:AddDoubleLine(label, npc.name, 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine(" ", WP.LocationText(npc), 1, 1, 1, 0.6, 0.6, 0.6)
  GameTooltip:AddLine(L["Clic: marcar el camino (mapa, minimapa y seguimiento)."], 0.5, 0.8, 1)
end

-- Al pulsar: marcar el camino al PNJ elegido
function WP.Go(pick)
  if not WP.Available() then
    ES:Print(L["Instala Questie para poder marcar el camino al instructor o al vendedor."])
    return
  end
  local npcID = pick()
  if not npcID then
    ES:Print(L["No se conoce ninguno de tu bando cerca."])
    return
  end
  WP.SetWaypoint(npcID)
end
