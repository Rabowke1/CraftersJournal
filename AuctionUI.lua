local _, ES = ...
local L = ES.L

-- Panel junto a la Casa de Subastas con la lista de la compra de la ruta:
--   Comprar:  materiales que el plan compra en la AH; clic en una fila (o "Buscar
--             siguiente") abre la compra de Blizzard con la cantidad puesta.
--             El botón "Comprar" compra con tu clic lo que falta del siguiente
--             material, si lo que hay ahora a la venta no pasa de lo previsto por
--             la ruta más el margen del regulador ("hasta X de oro más de lo
--             previsto", para toda la ruta). Solo con la AH de Forever
--             (C_AuctionHouse); con la clásica, el botón no sale.
--   Vender:   lo fabricado que llevas encima y conviene anunciar (Planner.SaleAdvice)
--   Recetas:  modo aparte del selector: las recetas que te faltan de tus profesiones
--             y están a la venta en la AH (último escaneo), con su precio; clic abre
--             su compra y "Comprar" compra la subasta más barata con tu clic.
-- El addon nunca compra sin un clic tuyo que diga qué compra: el juego solo deja
-- comprar en la AH como respuesta a una pulsación (no desde un temporizador), así
-- que es un material por clic. La compra va en dos pasos (pedir el precio real al
-- servidor y confirmarlo): si el precio sigue dentro del margen se confirma sola;
-- si el juego exige otra pulsación para confirmar, el botón pasa a "Confirmar".

local PANEL_W, PANEL_H, ROW_H = 300, 500, 34
local GOLD, GREEN, GREY, ORANGE = "|cffffd100", "|cff40ff40", "|cff999999", "|cffff9933"
local SEARCH_RETRY = 0.3
local PRICE_TIMEOUT, CONFIRM_TIMEOUT = 6, 10 -- s esperando al servidor (precio real; compra confirmada)
local AUTO_CONFIRM_GRACE = 1 -- s para que la confirmación automática llegue antes de enseñar "Confirmar"
local LEGACY_CONFIRM = 2 -- s: la AH clásica no confirma la compra; sin error en ese tiempo, se da por hecha

local panel, toggleButton
-- profKey, plan, baseline[itemID], need[itemID], live[itemID] (ofertas de ahora), buying (compra en curso),
-- bought[itemID] (comprado con el botón: lo de la AH de Forever puede llegar por correo, no a las bolsas)
local state = { lines = {}, live = {}, bought = {} }

local function ItemName(itemID)
  local name = ES:GetItemData(itemID)
  return name
end

-- Modos del panel: "money" (lote de Ganar dinero) y las profesiones con una ruta
-- empezada ("Empezar ruta"): es lo que vas a comprar. Sin ninguna, el panel dice
-- cómo empezar una.
local MONEY = "money"
local RECIPES = "recipes" -- recetas que te faltan y están en la AH
-- (la Pesca no compra nada: fuera)
local function ProfessionKeys()
  local keys = {}
  for _, p in ipairs(ES.PROFESSIONS) do
    local data = ES.Data[p.key]
    if data and not data.guide and ES:RouteLock(p.key) then keys[#keys + 1] = p.key end
  end
  keys[#keys + 1] = RECIPES -- sin ruta empezada, lo primero que sale
  keys[#keys + 1] = MONEY
  return keys
end

-- ¿La AH moderna (C_AuctionHouse) con búsqueda y compra?
local function Modern()
  local A = C_AuctionHouse
  return A ~= nil and A.MakeItemKey ~= nil and A.SendSearchQuery ~= nil and A.StartCommoditiesPurchase ~= nil
end

-- ¿La AH clásica (QueryAuctionItems / GetAuctionItemInfo)? Es la que usa el escaneo en
-- Forever y la que da los precios buenos: si está, manda sobre la moderna (en el juego,
-- la búsqueda moderna devolvía 2c por una receta que costaba 2s)
local function Legacy()
  return QueryAuctionItems ~= nil and GetAuctionItemInfo ~= nil and GetNumAuctionItems ~= nil
end

-- ¿Se puede comprar desde el panel? Clásica con PlaceAuctionBid (una subasta por clic) o moderna
local function CanBuy()
  return (Legacy() and PlaceAuctionBid ~= nil) or Modern()
end

-- Mensajes del juego que dicen que una compra clásica no se hizo
local AUCTION_ERRORS = { "ERR_NOT_ENOUGH_MONEY", "ERR_AUCTION_BID_OWN", "ERR_AUCTION_HIGHER_BID", "ERR_AUCTION_BID_INCREMENT",
  "ERR_AUCTION_MIN_BID", "ERR_AUCTION_DATABASE_ERROR", "ERR_AUCTION_ALREADY_BID", "ERR_ITEM_NOT_FOUND", "ERR_AUCTION_REMOVED",
  "ERR_AUCTION_HOUSE_UNAVAILABLE", "ERR_AUCTION_ITEM_NOT_FOUND", "ERR_AUCTION_BAG" }
local function IsAuctionError(text)
  for _, key in ipairs(AUCTION_ERRORS) do
    if _G[key] and _G[key] == text then return true end
  end
  return false
end

-- Patrón del mensaje "Has ganado una subasta de X" (ERR_AUCTION_WON_S) para dar por
-- hecha una compra clásica en cuanto el juego lo dice
local function WonPattern()
  local s = ERR_AUCTION_WON_S
  if type(s) ~= "string" then return nil end
  local pat = s:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0")
  pat = pat:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
  return "^" .. pat .. "$"
end

---------------------------------------------------------------------------
-- Margen: hasta cuánto oro más de lo previsto puede pagar "Comprar"
---------------------------------------------------------------------------
-- El margen se guarda con los ajustes de la profesión (sigue al rehacer la ruta);
-- lo gastado de más y lo comprado con el botón, con la ruta empezada (se olvidan al
-- soltarla). En el lote de Ganar dinero, el margen es de la cuenta y lo gastado
-- dura hasta recalcular.
local function BudgetStore()
  if state.profKey == RECIPES then return nil, nil end -- las recetas se compran al precio que digas con el clic: sin margen
  if state.profKey == MONEY then return ES.db, state end
  local settings = state.profKey and ES.db.prof and ES.db.prof[state.profKey]
  return settings, settings and settings.lock
end

local function Tolerance()
  local s = BudgetStore()
  return s and s.ahOverspend or 0
end

local function Overspent()
  local _, lock = BudgetStore()
  return lock and lock.ahOverspent or 0
end

local function SetTolerance(copper)
  local s = BudgetStore()
  if s then s.ahOverspend = copper > 0 and copper or nil end
end

-- Apunta una compra hecha con el botón: lo pagado sobre lo previsto y las unidades
local function NotePurchase(itemID, qty, total, unit)
  local _, lock = BudgetStore()
  if lock then lock.ahOverspent = (lock.ahOverspent or 0) + (total - unit * qty) end
  if lock and lock ~= state then -- con la ruta empezada: sobrevive a recargar
    lock.ahBought = lock.ahBought or {}
    lock.ahBought[itemID] = (lock.ahBought[itemID] or 0) + qty
  end
  state.bought[itemID] = (state.bought[itemID] or 0) + qty
end

local function BoughtWithButton(itemID)
  local _, lock = BudgetStore()
  local saved = lock and lock ~= state and lock.ahBought and lock.ahBought[itemID] or 0
  return math.max(saved, state.bought[itemID] or 0)
end

---------------------------------------------------------------------------
-- Búsqueda en la ventana de la AH
---------------------------------------------------------------------------
local function CanQuery()
  if not CanSendAuctionQuery then return true end
  return (CanSendAuctionQuery())
end

-- Rellena la búsqueda de la AH con el nombre del objeto y la lanza
function ES:SearchAuction(itemID, tries)
  local name = ItemName(itemID)
  if not name then
    -- El juego aún no tiene el nombre: lo pide y reintenta
    if (tries or 0) < 10 then C_Timer.After(SEARCH_RETRY, function() ES:SearchAuction(itemID, (tries or 0) + 1) end) end
    return
  end
  state.searching = itemID
  -- Clásica: pestaña Explorar, caja de nombre y botón Buscar de Blizzard
  if AuctionFrame and BrowseName then
    if AuctionFrameTab1 and AuctionFrameTab_OnClick and AuctionFrame.selectedTab ~= 1 then
      AuctionFrameTab_OnClick(AuctionFrameTab1)
    end
    if not CanQuery() then
      if (tries or 0) < 20 then C_Timer.After(SEARCH_RETRY, function() ES:SearchAuction(itemID, (tries or 0) + 1) end) end
      return
    end
    BrowseName:SetText(name)
    if BrowseMinLevel then BrowseMinLevel:SetText("") end
    if BrowseMaxLevel then BrowseMaxLevel:SetText("") end
    if AuctionFrameBrowse_Search then
      AuctionFrameBrowse_Search()
    elseif QueryAuctionItems then
      QueryAuctionItems(name, nil, nil, 0, nil, nil, false, true, nil)
    end
  -- Moderna: barra de búsqueda de AuctionHouseFrame
  elseif AuctionHouseFrame and AuctionHouseFrame.SearchBar then
    local bar = AuctionHouseFrame.SearchBar
    if bar.SetSearchText then bar:SetSearchText(name) end
    if bar.StartSearch then bar:StartSearch() end
  end
  ES:RenderAuctionPanel()
end

-- Pide a la AH de Forever las ofertas de un material (todas, de la más barata a la
-- más cara). Llegan con COMMODITY_SEARCH_RESULTS_UPDATED (materiales) o
-- ITEM_SEARCH_RESULTS_UPDATED (objetos no apilables). Si la AH está ocupada, se
-- repite cuando avisa (AUCTION_HOUSE_THROTTLED_SYSTEM_READY)
local function RequestOffers(itemID, tries)
  if not itemID then return end
  if Legacy() then
    -- AH clásica: búsqueda exacta por nombre, las más baratas primero (página 1); los
    -- resultados llegan con AUCTION_ITEM_LIST_UPDATE (ReadLivePrice). Si el juego aún
    -- no deja otra consulta, se repite en un momento
    local name = ItemName(itemID)
    local attempt = tries or 0
    if not name or (CanSendAuctionQuery and not CanSendAuctionQuery()) then
      if attempt < 20 then C_Timer.After(SEARCH_RETRY, function() RequestOffers(itemID, attempt + 1) end) end
      return
    end
    state.searching, state.legacyQuery = itemID, itemID
    if SortAuctionClearSort and SortAuctionSetSort and SortAuctionApplySort then
      pcall(SortAuctionClearSort, "list")
      if not pcall(SortAuctionSetSort, "list", "unitprice", false) then pcall(SortAuctionSetSort, "list", "buyout", false) end
      pcall(SortAuctionApplySort, "list")
    end
    pcall(QueryAuctionItems, name, nil, nil, 0, nil, nil, false, true, nil)
    return
  end
  if not Modern() then return end
  local A = C_AuctionHouse
  state.searching = itemID
  if A.IsThrottledMessageSystemReady and not A.IsThrottledMessageSystemReady() then
    state.wantOffers = itemID
    return
  end
  state.wantOffers = nil
  local price = Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0
  pcall(A.SendSearchQuery, A.MakeItemKey(itemID), { { sortOrder = price, reverseSort = false } }, false)
end

-- Cantidad en la página de compra de materiales de la AH moderna (la de Blizzard)
local function SetBuyQuantity(qty)
  local buy = AuctionHouseFrame and AuctionHouseFrame.CommoditiesBuyFrame
  local display = buy and (buy.BuyDisplay or (buy.GetBuyDisplay and buy:GetBuyDisplay()))
  if not (display and buy:IsShown()) then return false end
  if display.SetQuantitySelected then
    return pcall(display.SetQuantitySelected, display, qty)
  end
  local input = display.QuantityInput
  if input and input.SetQuantity then return pcall(input.SetQuantity, input, qty) end
  return false
end

-- Abre la compra de un material en la AH con la cantidad ya puesta (solo falta
-- pulsar "Comprar ahora" de Blizzard). Si no es un material de la AH moderna, o el
-- juego no deja, se busca como siempre (ES:SearchAuction) y se piden sus ofertas
function ES:OpenAuctionBuy(itemID, qty)
  local A, f = C_AuctionHouse, AuctionHouseFrame
  if not (A and A.MakeItemKey and f and f.SelectBrowseResult and f.CommoditiesBuyFrame) then
    self:SearchAuction(itemID)
    RequestOffers(itemID)
    return
  end
  local ok = pcall(function()
    f:SelectBrowseResult({ itemKey = A.MakeItemKey(itemID), minPrice = 0, totalQuantity = 0, containsOwnerItem = false })
  end)
  -- Materiales: la página de compra con cantidad; objetos no apilables (recetas): la lista de subastas
  local commodities = ok and f.CommoditiesBuyFrame:IsShown()
  local items = ok and f.ItemBuyFrame and f.ItemBuyFrame:IsShown()
  if not commodities and not items then
    self:SearchAuction(itemID)
    RequestOffers(itemID)
    return
  end
  state.searching = itemID
  if commodities then
    -- Los resultados llegan un momento después: se pone la cantidad en cuanto se pueda
    SetBuyQuantity(qty)
    C_Timer.After(0.4, function() SetBuyQuantity(qty) end)
    C_Timer.After(1.2, function() SetBuyQuantity(qty) end)
  end
  if Legacy() then RequestOffers(itemID) end -- las ofertas que valen: las de la lista clásica
  ES:RenderAuctionPanel()
end

-- Lo que hay ahora en la página de resultados para el objeto buscado (AH clásica)
-- Lo que hay ahora en la lista de la AH clásica para el objeto buscado: escalera de
-- subastas (precio por unidad, pila, índice en la lista para PlaceAuctionBid, si es
-- tuya), de la más barata a la más cara. Solo la página actual (hasta 50 subastas)
local function ReadLivePrice()
  local itemID = state.searching
  if not itemID or not GetNumAuctionItems or not GetAuctionItemInfo then return end
  local n = GetNumAuctionItems("list") or 0
  local me = UnitName and UnitName("player")
  local ladder, units, rows = {}, 0, 0
  for i = 1, n do
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, id = GetAuctionItemInfo("list", i)
    if id == itemID and count and count > 0 then
      rows, units = rows + 1, units + count
      if buyout and buyout > 0 then
        ladder[#ladder + 1] = { price = buyout / count, qty = count, buyout = buyout, index = i, own = owner ~= nil and owner == me }
      end
    end
  end
  -- Una lista sin el objeto (otra búsqueda, otra página) no dice nada; la de nuestra
  -- consulta sí: no hay ninguna
  if rows == 0 and state.legacyQuery ~= itemID then return end
  state.legacyQuery = nil
  table.sort(ladder, function(a, b) return a.price < b.price end)
  state.live[itemID] = { min = ladder[1] and ladder[1].price, units = units, ladder = ladder, legacy = true, at = GetTime() }
  ES:RenderAuctionPanel()
end

-- Ofertas de un material en la AH de Forever, de la más barata a la más cara:
-- { price = por unidad, qty, own = es tuya, auctionID y buyout (objetos no apilables) }
local function ReadOffers(itemID, commodity)
  local A = C_AuctionHouse
  if not (A and itemID) or Legacy() then return end
  local ladder, units = {}, 0
  if commodity then
    local n = A.GetNumCommoditySearchResults and A.GetNumCommoditySearchResults(itemID) or 0
    for i = 1, n do
      local r = A.GetCommoditySearchResultInfo(itemID, i)
      if r and (r.quantity or 0) > 0 and (r.unitPrice or 0) > 0 then
        ladder[#ladder + 1] = { price = r.unitPrice, qty = r.quantity, own = r.containsOwnerItem }
        units = units + r.quantity
      end
    end
  else
    local key = A.MakeItemKey(itemID)
    local n = A.GetNumItemSearchResults and A.GetNumItemSearchResults(key) or 0
    for i = 1, n do
      local r = A.GetItemSearchResultInfo(key, i)
      if r and (r.buyoutAmount or 0) > 0 then
        local q = r.quantity or 1
        ladder[#ladder + 1] = { price = r.buyoutAmount / q, qty = q, own = r.containsOwnerItem, auctionID = r.auctionID, buyout = r.buyoutAmount }
        units = units + q
      end
    end
  end
  table.sort(ladder, function(a, b) return a.price < b.price end)
  state.live[itemID] = { min = ladder[1] and ladder[1].price, units = units, ladder = ladder, commodity = commodity, at = GetTime() }
end

---------------------------------------------------------------------------
-- Datos: plan de la profesión elegida
---------------------------------------------------------------------------
local function Remaining(itemID)
  local bought = math.max(0, ES:ItemCount(itemID) - (state.baseline[itemID] or 0))
  return math.max(0, (state.need[itemID] or 0) - math.max(bought, BoughtWithButton(itemID)))
end

-- Siguiente objeto que te falta comprar (después del último buscado)
local function NextToBuy()
  local list, start = {}, 1
  for _, l in ipairs(state.lines) do
    if l.buy and Remaining(l.itemID) > 0 then list[#list + 1] = l.itemID end
  end
  for i, id in ipairs(list) do if id == state.searching then start = i + 1 end end
  return list[start] or list[1]
end

-- Líneas: sección Comprar (AH) y sección Vender (lo fabricado que llevas encima)
-- Recetas que te faltan de tus profesiones y están en la AH (último escaneo), por
-- profesión: { profKey, e (Collection), scroll, unit = la más barata del escaneo,
-- listings, level, learnable, cheaper = { kind, cost } si sale más barata en el
-- instructor o un vendedor a mano }. Primero las que puedes aprender ya
local function BuildRecipes()
  local list = {}
  for _, p in ipairs(ES.PROFESSIONS) do
    local data = ES.Data[p.key]
    if data and not data.guide and ES:ProfessionVisible(p) and ES:GetProfessionSkill(data.skillLine) then
      local res = ES.Collection:Build(p.key)
      local rows = {}
      for _, e in ipairs(res.entries) do
        local r = e.recipe
        if not e.known and r.scroll and e.scrollAH then
          local cheaper
          for _, src in ipairs(e.sources) do
            local here = src.kind == "trainer" or ((src.kind == "vendor" or src.kind == "rep") and src.usable)
            if here and src.cost and src.cost < e.scrollAH and (not cheaper or src.cost < cheaper.cost) then
              cheaper = { kind = src.kind, cost = src.cost }
            end
          end
          rows[#rows + 1] = { profKey = p.key, e = e, scroll = r.scroll, unit = e.scrollAH, listings = e.scrollListings, level = e.level,
            learnable = e.learnableNow and true or false, cheaper = cheaper }
        end
      end
      table.sort(rows, function(a, b)
        if a.learnable ~= b.learnable then return a.learnable end
        if a.level ~= b.level then return a.level < b.level end
        return a.unit < b.unit
      end)
      for _, row in ipairs(rows) do list[#list + 1] = row end
    end
  end
  return list
end

local function BuildLines()
  local lines = {}
  local plan, earn = state.plan, state.earn
  if state.recipes then
    local prof
    for _, rec in ipairs(state.recipes) do
      if rec.profKey ~= prof then
        prof = rec.profKey
        local n = 0
        for _, other in ipairs(state.recipes) do if other.profKey == prof then n = n + 1 end end
        lines[#lines + 1] = { section = ES:ProfLabel(prof) .. " · " .. n }
      end
      lines[#lines + 1] = { buy = true, itemID = rec.scroll, it = { unit = rec.unit, quantity = 1 }, rec = rec }
    end
    return lines
  end
  if not plan and not earn then return lines end
  local buy = {}
  for _, it in ipairs(plan and plan.shopping or earn.shopping) do
    if it.source == "ah" and (plan or state.need[it.itemID] > 0) then -- del lote, solo lo que no llevas ya
      buy[#buy + 1] = it
    end
  end
  if #buy > 0 then
    lines[#lines + 1] = { section = L["Comprar en la AH"] }
    for _, it in ipairs(buy) do lines[#lines + 1] = { buy = true, itemID = it.itemID, it = it } end
  end
  local sell = {}
  if plan then
    for _, d in ipairs(plan.destinations or {}) do
      local a = ES.Planner.SaleAdvice(d)
      local have = ES:ItemCount(d.itemID)
      if a.ah > 0 and have > 0 then sell[#sell + 1] = { itemID = d.itemID, advice = a, have = have, d = d } end
    end
  else
    -- Lote de Ganar dinero: lo fabricado que llevas, a anunciar
    for _, idea in ipairs(earn.batch) do
      local have = ES:ItemCount(idea.itemID)
      if idea.sellWhere == "ah" and have > 0 then
        sell[#sell + 1] = { itemID = idea.itemID, have = have,
          advice = { ah = idea.crafts * idea.e.qty, price = idea.price, verdict = idea.verdict,
            inflated = idea.e.fair and idea.e.fair.inflated } }
      end
    end
  end
  if #sell > 0 then
    lines[#lines + 1] = { section = L["Vender en la AH (lo llevas encima)"] }
    for _, s in ipairs(sell) do lines[#lines + 1] = { sell = true, itemID = s.itemID, s = s } end
  end
  return lines
end

-- Se calcula una vez al abrir (o al cambiar de profesión / Recalcular). Lo que
-- compras se descuenta comparando con lo que tenías en ese momento, sin
-- recalcular la ruta con cada compra.
function ES:RefreshAuctionPlan(force)
  -- Al abrir la AH se pide dos veces seguidas (panel y refresco general): una basta
  if not force and state.at and GetTime() - state.at < 1 then return end
  state.at = GetTime()
  local keys = ProfessionKeys()
  local function Valid(k)
    for _, key in ipairs(keys) do if key == k then return true end end
  end
  if not Valid(state.profKey) then
    state.profKey = Valid(self.db.lastProf) and self.db.lastProf or keys[1]
  end
  state.need, state.baseline, state.live, state.bought = {}, {}, {}, {}
  state.plan, state.earn, state.recipes = nil, nil, nil
  state.ahOverspent = nil -- lo gastado de más del lote de Ganar dinero: hasta recalcular
  if not state.profKey then
    -- Ninguna ruta empezada: nada que comprar (RenderAuctionPanel lo explica)
  elseif state.profKey == RECIPES then
    -- Recetas que te faltan y están en la AH: una de cada (el pergamino)
    local scan = ES.db.scans and ES.db.scans[ES:RealmKey()]
    state.scanned = scan ~= nil
    state.recipes = scan and BuildRecipes() or {}
    for _, rec in ipairs(state.recipes) do
      state.need[rec.scroll] = 1
      state.baseline[rec.scroll] = ES:ItemCount(rec.scroll)
    end
  elseif state.profKey == MONEY then
    -- Lote de Ganar dinero: lo que ya llevas cuenta (no hay que comprarlo)
    state.earn = ES.Earn:Ideas()
    for _, it in ipairs(state.earn.shopping) do
      if it.source == "ah" then
        local have = ES:ItemCount(it.itemID)
        state.need[it.itemID] = math.max(0, it.quantity - have)
        state.baseline[it.itemID] = have
      end
    end
  else
    state.plan, state.from, state.to = self:ProfessionPlan(state.profKey)
    for _, it in ipairs(state.plan and state.plan.shopping or {}) do
      if it.source == "ah" then
        state.need[it.itemID] = it.quantity
        state.baseline[it.itemID] = ES:ItemCount(it.itemID)
      end
    end
  end
  state.lines = BuildLines()
  -- Las ofertas de ahora del primer material pendiente, para que "Comprar" sepa qué cuesta
  if CanBuy() and self:IsAuctionHouseOpen() then
    state.searching = nil
    RequestOffers(NextToBuy())
  end
  self:RenderAuctionPanel()
end

---------------------------------------------------------------------------
-- Comprar con el botón
---------------------------------------------------------------------------
local function LineOf(itemID)
  for _, l in ipairs(state.lines) do if l.buy and l.itemID == itemID then return l end end
end

-- Lo que costaría comprar `qty` unidades empezando por la más barata (sin las
-- tuyas). nil y cuántas hay si no hay bastantes
local function LadderCost(ladder, qty)
  local left, total = qty, 0
  for _, o in ipairs(ladder) do
    if not o.own then
      local take = math.min(left, o.qty)
      total, left = total + take * o.price, left - take
      if left <= 0 then return total end
    end
  end
  return nil, qty - left
end

-- Lo que falta de un material a los precios de ahora: cantidad, coste, cuánto se
-- pasa de lo previsto y si solo hay parte. nil sin ofertas leídas; { none = true }
-- sin nada a la venta
local function Quote(l)
  local live = state.live[l.itemID]
  local rem = Remaining(l.itemID)
  if not live or rem == 0 then return nil end
  local qty, cost = rem, nil
  if live.ladder then
    local have
    cost, have = LadderCost(live.ladder, rem)
    if not cost then
      if (have or 0) == 0 then return { none = true } end
      qty = have
      cost = LadderCost(live.ladder, have)
    end
  elseif live.min then -- AH clásica: solo se sabe la más barata
    cost = live.min * rem
  else
    return { none = true }
  end
  -- El servidor ya dijo lo que cuesta esa cantidad (y se rechazó): manda hasta leer ofertas nuevas
  if live.serverTotal and live.serverQty == qty then cost = live.serverTotal end
  -- La subasta más barata que no sea tuya: lo que compra un clic en la AH clásica (una pila)
  local first
  for _, o in ipairs(live.ladder or {}) do
    if not o.own then
      first = { qty = o.qty, cost = o.buyout or o.price * o.qty, index = o.index, auctionID = o.auctionID }
      break
    end
  end
  return { qty = qty, cost = cost, over = cost - l.it.unit * qty, partial = qty < rem, first = first }
end

-- ¿Entra en el margen lo que falta por gastar de más?
local function Affordable(over)
  if state.profKey == RECIPES then return true end -- el botón enseña el precio exacto: tu clic es el consentimiento
  return over <= Tolerance() - Overspent() + 0.5
end

-- El material sobre el que actúa "Comprar": el buscado, si le falta; si no, el siguiente
local function BuyTarget()
  if state.searching and Remaining(state.searching) > 0 and LineOf(state.searching) then return state.searching end
  return NextToBuy()
end

-- Si el servidor no responde, la compra en curso se da por perdida (`buying` es la
-- misma tabla: una compra nueva no se ve afectada por el aviso de la anterior)
local Purchased -- (más abajo: se usa desde la compra)

local function Watch(buying, seconds, message)
  C_Timer.After(seconds, function()
    if state.buying ~= buying then return end
    state.buying = nil
    ES:Print(message)
    ES:RenderAuctionPanel()
  end)
end

-- Clic en "Comprar" (o en "Confirmar"): siempre con tu pulsación, como exige el juego
function ES:AuctionBuyClick()
  if not CanBuy() then return end
  local A = C_AuctionHouse
  local buying = state.buying
  if buying then
    -- El juego no aceptó la confirmación automática: con tu pulsación sí
    if buying.step == "confirm" and A then pcall(A.ConfirmCommoditiesPurchase, buying.itemID, buying.qty) end
    return
  end
  local id = BuyTarget()
  local l = id and LineOf(id)
  if not l then return end
  local q = Quote(l)
  if not q then -- sin ofertas leídas: se piden; cuando lleguen, el botón dirá qué cuesta
    RequestOffers(id)
    self:RenderAuctionPanel()
    return
  end
  if q.none then return end
  local live = state.live[id]
  if not live.ladder then RequestOffers(id) return end
  local name = ES:DataItemName(id) or id
  if live.legacy then
    -- AH clásica: la subasta más barata que no sea tuya, una pila por clic. Antes de
    -- pujar se comprueba que esa fila de la lista sigue siendo la misma subasta
    local offer = q.first
    if not offer or not PlaceAuctionBid then return end
    if not Affordable(offer.cost - l.it.unit * offer.qty) or (GetMoney and offer.cost > GetMoney()) then return end
    local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, rowID = GetAuctionItemInfo("list", offer.index)
    if rowID ~= id or count ~= offer.qty or buyout ~= offer.cost then
      self:Print(L["La lista de la Casa de Subastas ha cambiado: se vuelven a leer las ofertas."])
      RequestOffers(id)
      return
    end
    buying = { itemID = id, qty = offer.qty, unit = l.it.unit, step = "bid", legacy = true, index = offer.index, total = offer.cost }
    state.buying = buying
    local ok, err = pcall(PlaceAuctionBid, "list", offer.index, offer.cost)
    if not ok then
      state.buying = nil
      self:Print(string.format(L["No se pudo comprar %s: %s"], name, tostring(err)))
    else
      -- La AH clásica no avisa de que la compra se hizo (salvo el mensaje de "has ganado
      -- una subasta"): si el juego no da error en un momento, se da por hecha
      C_Timer.After(LEGACY_CONFIRM, function() if state.buying == buying then Purchased(buying) end end)
    end
    self:RenderAuctionPanel()
    return
  end
  if not Modern() then return end
  if not Affordable(q.over) or (GetMoney and q.cost > GetMoney()) then return end
  if live.commodity then
    buying = { itemID = id, qty = q.qty, unit = l.it.unit, step = "price" }
    state.buying = buying
    local ok, err = pcall(A.StartCommoditiesPurchase, id, q.qty)
    if not ok then
      state.buying = nil
      self:Print(string.format(L["No se pudo comprar %s: %s"], name, tostring(err)))
    else
      Watch(buying, PRICE_TIMEOUT, string.format(L["La Casa de Subastas no dio el precio de %s: vuelve a pulsar Comprar."], name))
    end
  else
    -- Objeto no apilable: la subasta más barata que no sea tuya, una por clic
    local offer
    for _, o in ipairs(live.ladder) do if not o.own and o.auctionID then offer = o break end end
    if not offer or not A.PlaceBid then return end
    buying = { itemID = id, qty = offer.qty, unit = l.it.unit, step = "bid", auctionID = offer.auctionID, total = offer.buyout }
    state.buying = buying
    local ok, err = pcall(A.PlaceBid, offer.auctionID, offer.buyout)
    if not ok then
      state.buying = nil
      self:Print(string.format(L["No se pudo comprar %s: %s"], name, tostring(err)))
    else
      Watch(buying, CONFIRM_TIMEOUT, string.format(L["La Casa de Subastas no confirmó la compra de %s: mira tus bolsas o el correo antes de volver a comprar."], name))
    end
  end
  self:RenderAuctionPanel()
end

-- El servidor dice lo que cuesta de verdad la cantidad pedida: si entra en el
-- margen, se confirma; si no, se cancela y se avisa
local function PriceUpdated(unit, total)
  local buying = state.buying
  if not (buying and buying.step == "price") then return end
  local A = C_AuctionHouse
  local name = ES:DataItemName(buying.itemID) or buying.itemID
  total = tonumber(total) or (tonumber(unit) or 0) * buying.qty
  local over = total - buying.unit * buying.qty
  if not Affordable(over) or (GetMoney and total > GetMoney()) then
    pcall(A.CancelCommoditiesPurchase)
    state.buying = nil
    if GetMoney and total > GetMoney() then
      ES:Print(string.format(L["No se compra: %d× %s cuestan %s y no llevas tanto oro."], buying.qty, name, ES.Money(total)))
    else
      ES:Print(string.format(L["No se compra: ahora %d× %s cuestan %s, %s más de lo previsto. Sube el margen o pulsa Buscar siguiente."],
        buying.qty, name, ES.Money(total), ES.Money(over - (Tolerance() - Overspent()))))
    end
    -- Que la fila y el botón lo enseñen aunque las ofertas leídas digan otra cosa, y
    -- se piden ofertas nuevas (las leídas se habían quedado viejas)
    local live = state.live[buying.itemID]
    if live then live.serverTotal, live.serverQty = total, buying.qty end
    RequestOffers(buying.itemID)
    return
  end
  buying.total, buying.step, buying.confirmedAt = total, "confirm", GetTime()
  pcall(A.ConfirmCommoditiesPurchase, buying.itemID, buying.qty)
  Watch(buying, CONFIRM_TIMEOUT, string.format(L["La Casa de Subastas no confirmó la compra de %s: mira tus bolsas o el correo antes de volver a comprar."], name))
  C_Timer.After(AUTO_CONFIRM_GRACE, function() ES:RenderAuctionPanel() end) -- si sigue pendiente, "Confirmar"
end

-- Compra hecha: se apunta, se pasa al siguiente material y se piden sus ofertas
function Purchased(buying)
  local name = ES:DataItemName(buying.itemID) or buying.itemID
  local total = buying.total or buying.unit * buying.qty
  NotePurchase(buying.itemID, buying.qty, total, buying.unit)
  local over = total - buying.unit * buying.qty
  if state.profKey == RECIPES then
    ES:Print(string.format(L["Comprados %d× %s por %s."], buying.qty, name, ES.Money(total)))
  elseif over >= 0.5 then
    ES:Print(string.format(L["Comprados %d× %s por %s (%s más de lo previsto)."], buying.qty, name, ES.Money(total), ES.Money(over)))
  elseif over <= -0.5 then
    ES:Print(string.format(L["Comprados %d× %s por %s (%s menos de lo previsto)."], buying.qty, name, ES.Money(total), ES.Money(-over)))
  else
    ES:Print(string.format(L["Comprados %d× %s por %s."], buying.qty, name, ES.Money(total)))
  end
  state.buying = nil
  state.live[buying.itemID] = nil -- ya no vale: lo comprado ya no está
  -- Si aún falta de este material (compra por pilas), se sigue con él; si no, el siguiente
  local nextID = Remaining(buying.itemID) > 0 and buying.itemID or NextToBuy()
  if nextID then RequestOffers(nextID) end
  ES:RenderAuctionPanel()
end

-- Eventos de la compra y de las ofertas (AH de Forever). Se atienden aunque el
-- panel esté escondido: la compra ya está en marcha
local function OnAuctionEvent(event, a, b)
  local buying = state.buying
  if event == "UI_ERROR_MESSAGE" then
    -- Compra clásica rechazada por el juego (sin oro, puja propia, ya no existe...)
    if buying and buying.legacy and IsAuctionError(b) then
      state.buying = nil
      ES:Print(string.format(L["No se pudo comprar %s: %s"], ES:DataItemName(buying.itemID) or buying.itemID, tostring(b)))
    else
      return
    end
  elseif event == "CHAT_MSG_SYSTEM" then
    -- "Has ganado una subasta de X": la compra clásica, hecha
    local pat = buying and buying.legacy and WonPattern()
    local won = pat and type(a) == "string" and a:match(pat)
    if won then Purchased(buying) end
    return
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" or event == "COMMODITY_SEARCH_RESULTS_ADDED" then
    if a then ReadOffers(a, true) end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" or event == "ITEM_SEARCH_RESULTS_ADDED" then
    local itemID = type(a) == "table" and a.itemID or a
    if itemID then ReadOffers(itemID, false) end
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if state.wantOffers then RequestOffers(state.wantOffers) end
  elseif event == "COMMODITY_PRICE_UPDATED" then
    PriceUpdated(a, b)
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" then
    if buying and buying.step == "price" then
      state.buying = nil
      ES:Print(string.format(L["Ya no hay %s a la venta."], ES:DataItemName(buying.itemID) or buying.itemID))
      RequestOffers(buying.itemID)
    end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    if buying and buying.step == "confirm" then Purchased(buying) return end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    if buying and buying.step ~= "bid" then
      state.buying = nil
      ES:Print(string.format(L["La compra de %s no se hizo."], ES:DataItemName(buying.itemID) or buying.itemID))
    end
  elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    if buying and buying.step == "bid" and (a == nil or a == buying.auctionID) then Purchased(buying) return end
  elseif event == "AUCTION_HOUSE_SHOW_ERROR" then
    if buying then
      state.buying = nil
      ES:Print(string.format(L["La compra de %s no se hizo."], ES:DataItemName(buying.itemID) or buying.itemID))
    end
  end
  ES:RenderAuctionPanel()
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function CreateRow(parent, i)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(PANEL_W - 44, ROW_H)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.82, 0.25, 0.10)
  row.sel = row:CreateTexture(nil, "BACKGROUND")
  row.sel:SetAllPoints()
  row.sel:SetColorTexture(0.2, 0.6, 1, 0.18)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(26, 26)
  row.icon:SetPoint("LEFT", 2, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.check = row:CreateTexture(nil, "OVERLAY")
  row.check:SetSize(16, 16)
  row.check:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 4, -4)
  row.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
  row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
  row.title:SetPoint("RIGHT", -2, 0)
  row.title:SetJustifyH("LEFT")
  row.title:SetWordWrap(false)
  row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
  row.sub:SetPoint("RIGHT", -2, 0)
  row.sub:SetJustifyH("LEFT")
  row.sub:SetWordWrap(false)
  row.sub:SetTextColor(0.75, 0.72, 0.65)
  row.section = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.section:SetPoint("LEFT", 2, 0)
  row:SetScript("OnClick", function(self)
    if not self.itemID then return end
    -- Con lo que falta: la compra abierta con la cantidad puesta; si no, buscarlo
    local left = Remaining(self.itemID)
    if left > 0 then ES:OpenAuctionBuy(self.itemID, left) else ES:SearchAuction(self.itemID) end
  end)
  row:SetScript("OnEnter", function(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. self.itemID)
    GameTooltip:AddLine(" ")
    if self.hint then GameTooltip:AddLine(self.hint, 0.8, 0.8, 0.8, true) end
    GameTooltip:AddLine(L["Clic: buscarlo en la Casa de Subastas."], 0.5, 0.8, 1)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return row
end

-- Regulador horizontal sin plantilla (las de Blizzard traen los rótulos LOW/HIGH)
local function CreateSlider(parent)
  local s = CreateFrame("Slider", nil, parent)
  s:SetOrientation("HORIZONTAL")
  s:SetHeight(16)
  s:EnableMouse(true)
  local border = s:CreateTexture(nil, "BACKGROUND")
  border:SetPoint("LEFT", -1, 0)
  border:SetPoint("RIGHT", 1, 0)
  border:SetHeight(6)
  border:SetColorTexture(0.52, 0.38, 0.17, 0.9)
  local track = s:CreateTexture(nil, "BORDER")
  track:SetPoint("LEFT", 0, 0)
  track:SetPoint("RIGHT", 0, 0)
  track:SetHeight(4)
  track:SetColorTexture(0, 0, 0, 0.7)
  s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  local thumb = s:GetThumbTexture()
  if thumb and thumb.SetSize then thumb:SetSize(26, 26) end
  s:SetMinMaxValues(0, 10)
  s:SetValueStep(1)
  if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
  return s
end

local function CreatePanel(ahFrame)
  local p = ES.UI.Panel(ahFrame)
  p:SetSize(PANEL_W, PANEL_H)
  p:SetPoint("TOPLEFT", ahFrame, "TOPRIGHT", 2, -12)
  p:SetFrameStrata(ahFrame:GetFrameStrata())
  p:EnableMouse(true)

  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText(L["Crafter's Journal · Lista de compra"])

  local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function()
    ES.db.ahPanelHidden = true
    p:Hide()
  end)

  -- Selector de profesión: < Cocina (75 → 150) >
  local prev = CreateFrame("Button", nil, p)
  prev:SetSize(22, 22)
  prev:SetPoint("TOPLEFT", 8, -28)
  prev:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
  prev:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
  local nextB = CreateFrame("Button", nil, p)
  nextB:SetSize(22, 22)
  nextB:SetPoint("TOPRIGHT", -8, -28)
  nextB:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
  nextB:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
  p.prof = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  p.prof:SetPoint("LEFT", prev, "RIGHT", 4, 0)
  p.prof:SetPoint("RIGHT", nextB, "LEFT", -4, 0)
  p.prevButton, p.nextProfButton = prev, nextB
  local function Cycle(delta)
    local keys = ProfessionKeys()
    if #keys == 0 then return end
    local at = 1
    for i, k in ipairs(keys) do if k == state.profKey then at = i end end
    state.profKey = keys[(at - 1 + delta) % #keys + 1]
    ES:RefreshAuctionPlan(true)
  end
  prev:SetScript("OnClick", function() Cycle(-1) end)
  nextB:SetScript("OnClick", function() Cycle(1) end)

  p.summary = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  p.summary:SetPoint("TOPLEFT", 12, -54)
  p.summary:SetPoint("RIGHT", -12, 0)
  p.summary:SetJustifyH("LEFT")

  -- Margen: hasta cuánto oro más de lo previsto puede pagar "Comprar"
  p.budget = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  p.budget:SetPoint("TOPLEFT", 12, -72)
  p.budget:SetPoint("RIGHT", -12, 0)
  p.budget:SetJustifyH("LEFT")
  p.budget:SetWordWrap(false)
  local slider = CreateSlider(p)
  slider:SetPoint("TOPLEFT", 16, -90)
  slider:SetPoint("RIGHT", -16, 0)
  slider:SetScript("OnValueChanged", function(_, value)
    if state.settingSlider then return end
    local gold = math.floor((tonumber(value) or 0) + 0.5)
    if gold * 10000 == Tolerance() then return end
    SetTolerance(gold * 10000)
    ES:RenderAuctionPanel()
  end)
  slider:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L["Margen de Comprar"], 1, 1, 1)
    GameTooltip:AddLine(L["Hasta cuánto oro más de lo que calculó la ruta puede pagar el botón Comprar, en total para toda la ruta. Al precio previsto o menos compra siempre. Solo cuentan las compras hechas con el botón."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
  p.slider = slider

  local scroll = ES.UI.WheelScroll(p)
  scroll:SetPoint("TOPLEFT", 10, -112)
  scroll:SetPoint("BOTTOMRIGHT", -10, 70)
  p.content = CreateFrame("Frame", nil, scroll)
  p.content:SetSize(PANEL_W - 44, 1)
  scroll:SetScrollChild(p.content)
  p.rows = {}
  p.empty = p.content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  p.empty:SetPoint("TOP", 0, -20)
  p.empty:SetWidth(PANEL_W - 60)

  -- Comprar: el siguiente material con tu clic, si entra en el margen (solo AH de Forever)
  p.buyButton = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  p.buyButton:SetSize(PANEL_W - 20, 24)
  p.buyButton:SetPoint("BOTTOMLEFT", 10, 38)
  p.buyButton:SetText(L["Comprar"])
  p.buyButton:SetScript("OnClick", function() ES:AuctionBuyClick() end)
  p.buyButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L["Comprar"], 1, 1, 1)
    GameTooltip:AddLine(L["Compra con tu clic lo que falta del siguiente material, si lo que hay a la venta no pasa de lo previsto más el margen. Un material por clic: el juego solo deja comprar en la Casa de Subastas como respuesta a una pulsación."], 0.8, 0.8, 0.8, true)
    if self.why then GameTooltip:AddLine(self.why, 1, 0.6, 0.2, true) end
    if self.source then GameTooltip:AddLine(self.source, 0.6, 0.6, 0.6, true) end
    GameTooltip:Show()
  end)
  p.buyButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

  p.nextButton = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  p.nextButton:SetSize(150, 24)
  p.nextButton:SetPoint("BOTTOMLEFT", 10, 10)
  p.nextButton:SetText(L["Buscar siguiente"])
  p.nextButton:SetScript("OnClick", function()
    local id = NextToBuy()
    if id then ES:OpenAuctionBuy(id, Remaining(id)) end
  end)

  local recalc = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  recalc:SetSize(110, 24)
  recalc:SetPoint("BOTTOMRIGHT", -10, 10)
  recalc:SetText(L["Recalcular"])
  recalc:SetScript("OnClick", function() ES:RefreshAuctionPlan(true) end)
  recalc:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L["Recalcular la ruta"], 1, 1, 1)
    GameTooltip:AddLine(L["Con los precios del último escaneo y lo que tienes ahora en bolsas."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  recalc:SetScript("OnLeave", function() GameTooltip:Hide() end)

  ES.SafeRegister(p, "BAG_UPDATE_DELAYED")
  ES.SafeRegister(p, "AUCTION_ITEM_LIST_UPDATE")
  -- AH de Forever: ofertas y compra (los que el cliente no tenga, no se registran)
  for _, ev in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "COMMODITY_SEARCH_RESULTS_ADDED", "ITEM_SEARCH_RESULTS_UPDATED",
    "ITEM_SEARCH_RESULTS_ADDED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "COMMODITY_PRICE_UPDATED", "COMMODITY_PRICE_UNAVAILABLE",
    "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "AUCTION_HOUSE_PURCHASE_COMPLETED", "AUCTION_HOUSE_SHOW_ERROR",
    "UI_ERROR_MESSAGE", "CHAT_MSG_SYSTEM" }) do -- (los dos últimos: la compra clásica)
    ES.SafeRegister(p, ev)
  end
  p:SetScript("OnEvent", function(_, event, a, b)
    if event == "BAG_UPDATE_DELAYED" then
      if p:IsShown() then ES:RenderAuctionPanel() end
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
      if not ES.Scanner:IsBusy() then ReadLivePrice() end
    elseif (event == "CHAT_MSG_SYSTEM" or event == "UI_ERROR_MESSAGE") and not (state.buying and state.buying.legacy) then
      return -- (mensajes de cada momento: solo interesan con una compra clásica en marcha)
    else
      OnAuctionEvent(event, a, b)
    end
  end)
  return p
end

-- Texto y estado del botón Comprar según el material que toca y sus ofertas.
-- state.buy = { action, text } (para las pruebas)
local function RenderBuyButton()
  local b = panel.buyButton
  if not CanBuy() then
    b:Hide()
    state.buy = nil
    return
  end
  b:Show()
  b.source = nil
  local function Set(action, text, enabled, why)
    state.buy = { action = action, text = text }
    b:SetText(text)
    b:SetEnabled(enabled and true or false)
    b.why = why
  end
  local buying = state.buying
  if buying then
    if buying.step == "confirm" then
      Set("confirm", string.format(L["Confirmar: %s"], ES.Money(buying.total)), GetTime() - (buying.confirmedAt or 0) >= AUTO_CONFIRM_GRACE,
        L["El juego pide tu pulsación para confirmar la compra."])
    else
      Set("wait", L["Comprobando el precio..."], false)
    end
    return
  end
  local id = BuyTarget()
  local l = id and LineOf(id)
  if not l then Set("none", L["Comprar"], false) return end
  local q = Quote(l)
  local name = ES:DataItemName(id) or id
  local live = state.live[id]
  if live and live.ladder then
    b.source = string.format(L["Ofertas leídas: %d (%s)"], #live.ladder, live.legacy and L["lista clásica, una pila por clic"] or L["búsqueda moderna"])
  end
  -- En la AH clásica cada clic compra una pila: la más barata que no sea tuya
  local qty, cost = q and q.qty, q and q.cost
  if q and live and live.legacy and q.first then qty, cost = q.first.qty, q.first.cost end
  local over = q and not q.none and (cost - l.it.unit * qty)
  if not q then
    Set("offers", string.format(L["Ver precios: %s"], name), true, L["Aún no se han leído las ofertas de este material."])
  elseif q.none or (live.legacy and not q.first) then
    Set("empty", string.format(L["Ahora no hay %s a la venta"], name), false)
  elseif GetMoney and cost > GetMoney() then
    Set("poor", string.format(L["%d× %s: %s, no llevas tanto oro"], qty, name, ES.Money(cost)), false)
  elseif state.profKey == RECIPES then
    Set("buy", string.format(L["Comprar receta: %s por %s"], name, ES.Money(cost)), true)
  elseif Affordable(over) then
    Set("buy", string.format(L["Comprar %d× %s por %s"], qty, name, ES.Money(cost)), true)
  else
    Set("over", string.format(L["%s más de lo previsto: sube el margen"], ES.Money(over - (Tolerance() - Overspent()))), false,
      string.format(L["Ahora %d× %s cuestan %s; la ruta contaba con %s. Sube el margen o pulsa Buscar siguiente."],
        qty, name, ES.Money(cost), ES.Money(l.it.unit * qty)))
  end
end

-- Regulador y su rótulo: el tope sube con lo que la ruta gasta en la AH
local function RenderBudget(plannedAH)
  local tol, spent = Tolerance(), Overspent()
  local text = string.format(L["Comprar: hasta %s más de lo previsto"], ES.Money(tol))
  if spent >= 0.5 then
    text = text .. string.format(L[" · gastado %s de más"], ES.Money(spent))
  elseif spent <= -0.5 then
    text = text .. string.format(L[" · gastado %s de menos"], ES.Money(-spent))
  end
  panel.budget:SetText(text)
  local maxGold = math.max(10, math.ceil(plannedAH / 10000 * 0.5 / 10) * 10, math.ceil(tol / 10000))
  state.settingSlider = true
  panel.slider:SetMinMaxValues(0, maxGold)
  panel.slider:SetValue(math.floor(tol / 10000 + 0.5))
  state.settingSlider = nil
end

function ES:RenderAuctionPanel()
  if not panel or not panel:IsShown() then return end
  local plan, earn = state.plan, state.earn
  -- Flechas solo si hay más de una lista entre la que elegir
  local several = #ProfessionKeys() > 1
  panel.prevButton:SetShown(several)
  panel.nextProfButton:SetShown(several)
  if not state.profKey then
    panel.prof:SetText(GREY .. L["Ninguna ruta empezada"] .. "|r")
  elseif state.recipes then
    panel.prof:SetText(L["Recetas en la AH"])
  elseif earn then
    panel.prof:SetText(L["Ganar dinero"] .. " " .. GREY .. L["(lote de hoy)"] .. "|r")
  else
    panel.prof:SetText(string.format("%s %s(%d → %d)|r", ES:ProfLabel(state.profKey), GREY, state.from or 1, state.to or 1))
  end
  local lines = BuildLines()
  state.lines = lines

  local left, total, done, plannedAH = 0, 0, 0, 0
  for _, l in ipairs(lines) do
    if l.buy then
      total = total + 1
      plannedAH = plannedAH + l.it.unit * l.it.quantity
      local rem = Remaining(l.itemID)
      if rem == 0 then done = done + 1 else left = left + rem * l.it.unit end
    end
  end
  if not state.profKey then
    panel.summary:SetText(GREY .. L["Aquí sale lo que comprar para tus rutas empezadas.|r"])
  elseif state.recipes then
    if not state.scanned then
      panel.summary:SetText(GREY .. L["Escanea la AH para ver qué recetas que te faltan están a la venta.|r"])
    elseif total == 0 then
      panel.summary:SetText(GREY .. L["Ninguna receta que te falte está en la AH (según el último escaneo).|r"])
    else
      local learnable = 0
      for _, rec in ipairs(state.recipes) do if rec.learnable then learnable = learnable + 1 end end
      panel.summary:SetText(string.format(L["%d recetas que te faltan están en la AH · %d puedes aprender ya"], total, learnable)
        .. (done > 0 and string.format(L[" · %d compradas"], done) or ""))
    end
  elseif earn and #earn.batch == 0 then
    panel.summary:SetText(GREY .. L["Ninguna receta tuya da beneficio ahora.|r"])
  elseif not plan and not earn then
    panel.summary:SetText(GREEN .. L["Ya estás en el objetivo de esta profesión.|r"])
  elseif total == 0 then
    panel.summary:SetText(GREY .. (earn and L["Tienes todos los materiales del lote.|r"] or L["La ruta no compra nada en la AH.|r"]))
  else
    panel.summary:SetText(string.format(L["%d de %d comprados · te falta ~%s"], done, total, ES.Money(left)))
  end
  panel.empty:SetText(#lines == 0 and (not state.profKey
    and L["En Crafter's Journal, abre una profesión y pulsa Empezar ruta: su lista de la compra saldrá aquí."]
    or (plan or earn) and L["Nada que comprar ni vender aquí."] or "") or "")
  panel.nextButton:SetEnabled(total > done)
  -- Margen y botón Comprar solo con algo que comprar en la AH (las recetas van sin margen)
  panel.budget:SetShown(total > 0 and not state.recipes)
  panel.slider:SetShown(total > 0 and not state.recipes)
  RenderBudget(plannedAH)
  RenderBuyButton()
  if total == 0 then panel.buyButton:Hide() end

  local y = 0
  for i, l in ipairs(lines) do
    local row = panel.rows[i] or CreateRow(panel.content, i)
    panel.rows[i] = row
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -y)
    local isSection = l.section ~= nil
    row:SetHeight(isSection and 20 or ROW_H)
    row.section:SetText(isSection and (GOLD .. l.section .. "|r") or "")
    row.icon:SetShown(not isSection)
    row.title:SetShown(not isSection)
    row.sub:SetShown(not isSection)
    row.itemID = l.itemID
    row.check:Hide()
    row.sel:SetShown(l.itemID ~= nil and l.itemID == state.searching)
    if not isSection then
      local name, quality, texture = ES:GetItemData(l.itemID)
      row.icon:SetTexture(texture or 134400)
      local color = name and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
      local label = (name and color and color.hex) and (color.hex .. name .. "|r") or name or (L["Objeto "] .. l.itemID)
      local live = state.live[l.itemID]
      local liveText = live and (live.min and string.format(L[" · ahora %s"], ES.Money(live.min)) or L[" · ahora: no hay"]) or ""
      if l.rec then
        -- Receta que te falta: nivel (verde si ya puedes aprenderla), precio del escaneo
        -- y cuántas hay, beneficio por fabricación y si sale más barata en otro sitio
        local rec, rem = l.rec, Remaining(l.itemID)
        row.check:SetShown(rem == 0)
        row.title:SetText(rem == 0 and (GREY .. (name or rec.e.recipe.name) .. "|r") or (name and label or rec.e.recipe.name))
        local q = rem > 0 and Quote(l) or nil
        local price = string.format(L["%s · %d a la venta"], ES.Money(rec.unit), rec.listings)
        if q and q.none then
          price = ES.Money(rec.unit) .. L[" · ahora: no hay"]
        elseif q and q.cost > rec.unit * 1.25 then
          price = string.format(L["%sahora %s (en el escaneo %s)|r"], ORANGE, ES.Money(q.cost), ES.Money(rec.unit))
        elseif q then
          price = ES.Money(q.cost) -- lo leído ahora en la AH
        end
        local sub = (rec.learnable and GREEN or GREY) .. string.format(L["nivel %d"], rec.level) .. "|r · " .. price
        local profit = rec.e.profit
        if profit and profit >= 0.5 then sub = sub .. string.format(L[" · %s/fabricación"], GREEN .. "+" .. ES.Money(profit) .. "|r") end
        if rec.cheaper then
          sub = sub .. ORANGE .. string.format(rec.cheaper.kind == "trainer" and L[" · más barata en el instructor (%s)"]
            or L[" · más barata en el vendedor (%s)"], ES.Money(rec.cheaper.cost)) .. "|r"
        end
        row.sub:SetText(rem == 0 and (GREEN .. L["comprado|r"]) or sub)
        row.hint = ES:ProfLabel(rec.profKey) .. " · " .. (rec.learnable and L["Puedes aprenderla ya"] or string.format(L["A partir de nivel %d"], rec.level))
      elseif l.buy then
        local rem = Remaining(l.itemID)
        row.check:SetShown(rem == 0)
        row.title:SetText(rem == 0 and (GREY .. label .. "|r") or (rem .. "× " .. label))
        row.sub:SetText(rem == 0 and (GREEN .. L["comprado|r"])
          or string.format(L["~%s/u en el plan%s"], ES.Money(l.it.unit), liveText))
        row.hint = string.format(L["Hacen falta %d en total. Precio medio calculado: %s por unidad."], l.it.quantity, ES.Money(l.it.unit))
        -- Más caro ahora de lo que admite el margen: avisar
        local q = rem > 0 and Quote(l) or nil
        if q and not q.none and not Affordable(q.over) then
          row.sub:SetText(string.format(L["%sahora %d× cuestan %s, %s más de lo previsto|r"], ORANGE, q.qty, ES.Money(q.cost), ES.Money(q.over)))
        elseif q and q.partial then
          row.sub:SetText(row.sub:GetText() .. string.format(L[" · solo hay %d a la venta"], q.qty))
        end
      else
        local s = l.s
        local n = math.min(s.have, s.advice.ah)
        row.title:SetText(n .. "× " .. label)
        row.sub:SetText(string.format(L["a %s cada uno · %s%s"], ES.Money(s.advice.price), ES.Market.LABELS[s.advice.verdict], liveText))
        row.hint = s.advice.inflated
          and L["La más barata está inflada (quedan pocas): el precio sugerido es el de los últimos días, algo por encima."]
          or s.advice.verdict == "good"
          and L["Las alertas de mercado están bien: anúncialos al precio de la más barata menos 1 cobre."]
          or L["Anuncia solo unos pocos para probar; si se venden, pon más."]
      end
    end
    y = y + (isSection and 20 or ROW_H) + 2
    row:Show()
  end
  for i = #lines + 1, #panel.rows do panel.rows[i]:Hide() end
  panel.content:SetHeight(math.max(1, y))
end

-- Al abrir la AH: crea el panel (la ventana de la AH se carga bajo demanda)
function ES:SetupAuctionPanel(ahFrame)
  if not panel then
    panel = CreatePanel(ahFrame)
    state.panel = panel -- para las pruebas
    toggleButton = CreateFrame("Button", nil, ahFrame, "UIPanelButtonTemplate")
    toggleButton:SetSize(120, 24)
    toggleButton:SetText(L["Lista de compra"])
    if CraftersJournalAHButton then
      toggleButton:SetPoint("RIGHT", CraftersJournalAHButton, "LEFT", -4, 0)
    else
      toggleButton:SetPoint("BOTTOMRIGHT", ahFrame, "TOPRIGHT", -184, 2)
    end
    toggleButton:SetScript("OnClick", function()
      ES.db.ahPanelHidden = panel:IsShown() or nil
      if panel:IsShown() then panel:Hide() else panel:Show() ES:RefreshAuctionPlan(true) end
    end)
  end
  state.searching, state.buying = nil, nil
  if ES.db.ahPanelHidden then
    panel:Hide()
  else
    panel:Show()
    self:RefreshAuctionPlan(true)
  end
end

function ES:AuctionPanelShown()
  return panel ~= nil and panel:IsShown()
end

-- /cj ah: qué API de subastas tiene el cliente y qué devuelve cada una para el objeto
-- del panel (para afinar la compra en Forever). Se escribe en el chat y en
-- CraftersJournalDB.ahDebug (SavedVariables, tras /reload)
function ES:AuctionDebug()
  local lines = {}
  local function Add(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
  local A = C_AuctionHouse
  local function has(f) return f ~= nil and "sí" or "no" end
  Add("API clásica: QueryAuctionItems %s · GetAuctionItemInfo %s · PlaceAuctionBid %s · CanSendAuctionQuery %s",
    has(QueryAuctionItems), has(GetAuctionItemInfo), has(PlaceAuctionBid), CanSendAuctionQuery and tostring((CanSendAuctionQuery())) or "-")
  Add("C_AuctionHouse: %s · SendSearchQuery %s · GetItemSearchResultInfo %s · GetCommoditySearchResultInfo %s · StartCommoditiesPurchase %s · PlaceBid %s · ReplicateItems %s",
    has(A), has(A and A.SendSearchQuery), has(A and A.GetItemSearchResultInfo), has(A and A.GetCommoditySearchResultInfo),
    has(A and A.StartCommoditiesPurchase), has(A and A.PlaceBid), has(A and A.ReplicateItems))
  local id = state.searching
  local scan = ES.db.scans and ES.db.scans[ES:RealmKey()]
  local it = id and scan and scan.items and scan.items[id]
  Add("objeto del panel: %s %s · escaneo: minUnit %s, %s subastas", tostring(id), tostring(id and ES:DataItemName(id)),
    tostring(it and it.minUnit), tostring(it and it.listings))
  if GetNumAuctionItems and GetAuctionItemInfo then
    local n = GetNumAuctionItems("list") or 0
    Add("lista clásica: %d filas (primeras 5)", n)
    for i = 1, math.min(n, 5) do
      local name, _, count, _, _, _, _, minBid, _, buyout, bid, _, _, owner, _, _, itemID = GetAuctionItemInfo("list", i)
      Add("  %d: %s ×%s id=%s minBid=%s buyout=%s bid=%s owner=%s", i, tostring(name), tostring(count), tostring(itemID),
        tostring(minBid), tostring(buyout), tostring(bid), tostring(owner))
    end
  end
  if A and id and A.MakeItemKey then
    local key = A.MakeItemKey(id)
    local n = A.GetNumItemSearchResults and A.GetNumItemSearchResults(key) or 0
    Add("búsqueda moderna (objetos): %d resultados (primeros 5)", n)
    for i = 1, math.min(n, 5) do
      local r = A.GetItemSearchResultInfo(key, i) or {}
      Add("  %d: ×%s buyoutAmount=%s minBid=%s bidAmount=%s auctionID=%s", i, tostring(r.quantity), tostring(r.buyoutAmount),
        tostring(r.minBid), tostring(r.bidAmount), tostring(r.auctionID))
    end
    local m = A.GetNumCommoditySearchResults and A.GetNumCommoditySearchResults(id) or 0
    Add("búsqueda moderna (materiales): %d resultados (primeros 5)", m)
    for i = 1, math.min(m, 5) do
      local r = A.GetCommoditySearchResultInfo(id, i) or {}
      Add("  %d: ×%s unitPrice=%s", i, tostring(r.quantity), tostring(r.unitPrice))
    end
  end
  local live = id and state.live[id]
  Add("panel: %s", live and string.format("%d ofertas (%s), más barata %s", #(live.ladder or {}), live.legacy and "clásica" or "moderna", tostring(live.min)) or "sin ofertas leídas")
  for _, l in ipairs(lines) do print("|cff33ccffCJ|r " .. l) end
  ES.db.ahDebug = lines
  return lines
end

ES.AuctionPanelState = state -- para pruebas
