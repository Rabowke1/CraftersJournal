local _, ES = ...
local L = ES.L

-- Pestaña "Lista de compra": las listas que has añadido (Shopping.lua), una sección
-- por cada una, con su progreso. Con la AH abierta, clic en un material (o "Comprar
-- siguiente") abre su compra de Blizzard con la cantidad puesta; confirmas tú.

local GREEN, GREY, ORANGE = "|cff40ff40", "|cff999999", "|cffff9933"

local selected -- el material cuya compra se abrió el último

local function Buy(itemID, left, unit)
  if not (itemID and ES:IsAuctionHouseOpen()) then return end
  selected = itemID
  ES:OpenAuctionBuy(itemID, left, unit)
  ES:RenderShopping()
end

function ES:ShoppingBuyNext()
  local itemID, left, unit = ES.Shopping.NextToBuy(ES.Shopping.Status(), selected)
  Buy(itemID, left, unit)
  return itemID
end

local KIND_ICON = {
  route = "Interface\\Icons\\Trade_BlackSmithing",
  money = "Interface\\Icons\\INV_Misc_Coin_02",
  calc = "Interface\\Icons\\INV_Misc_Note_02",
}

function ES:CreateShoppingPage(page)
  local Label = ES.UI.Label
  local head = ES.UI.CardHead(page) -- (fondo y colores de Subir profesiones)
  local icon = head:CreateTexture(nil, "ARTWORK")
  icon:SetSize(44, 44)
  icon:SetPoint("LEFT", 12, 0)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local name = Label(head, L["Lista de compra"], "GameFontNormalHuge")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 2)
  name:SetTextColor(0.96, 0.79, 0.25)
  page.subtitle = Label(head, "", "GameFontHighlightSmall")
  page.subtitle:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 12, 2)
  page.subtitle:SetPoint("RIGHT", -190, 0)
  page.subtitle:SetJustifyH("LEFT")

  page.nextButton = CreateFrame("Button", nil, head, "UIPanelButtonTemplate")
  page.nextButton:SetSize(170, 24)
  page.nextButton:SetPoint("RIGHT", -12, 0)
  page.nextButton:SetText(L["Comprar siguiente"])
  page.nextButton:SetMotionScriptsWhileDisabled(true)
  page.nextButton:SetScript("OnClick", function() ES:ShoppingBuyNext() end)
  page.nextButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine(L["Comprar siguiente"], 1, 1, 1)
    local itemID, left = ES.Shopping.NextToBuy(ES.Shopping.Status(), selected)
    if itemID then
      GameTooltip:AddLine(string.format("%d× %s", left, (ES.UI.ItemLabel(itemID, L["Objeto "] .. itemID))), 1, 0.82, 0)
    end
    GameTooltip:AddLine(L["Abre la compra de Blizzard con la cantidad puesta (solo las baratas). Confírmala con su botón Comprar ahora y vuelve a pulsar este para el siguiente."], 0.8, 0.8, 0.8, true)
    if not ES:IsAuctionHouseOpen() then GameTooltip:AddLine(L["Abre la Casa de Subastas para comprar."], 1, 0.6, 0.2, true) end
    GameTooltip:Show()
  end)
  page.nextButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Progreso de toda la lista
  local strip = CreateFrame("Frame", nil, page)
  strip:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 4, -6)
  strip:SetPoint("TOPRIGHT", head, "BOTTOMRIGHT", -4, -6)
  strip:SetHeight(46)
  page.progressText = Label(strip, "", "GameFontHighlight")
  page.progressText:SetPoint("TOPLEFT", 6, -2)
  page.bar = CreateFrame("StatusBar", nil, strip)
  page.bar:SetPoint("TOPLEFT", 6, -22)
  page.bar:SetPoint("RIGHT", -6, 0)
  page.bar:SetHeight(10)
  page.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  page.bar:SetStatusBarColor(0.25, 0.8, 0.25)
  page.bar:SetMinMaxValues(0, 1)
  local barBg = page.bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints()
  barBg:SetColorTexture(0, 0, 0, 0.5)
  page.status = Label(page, "", "GameFontHighlightSmall")
  page.status:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 2, -2)
  page.status:SetPoint("RIGHT", strip, "RIGHT", 0, 0)
  page.status:SetJustifyH("LEFT")
  page.status:SetWordWrap(false)

  local list = ES.UI.ListPanel(page, head, 70)
  local scroll = ES.UI.WheelScroll(list)
  scroll:SetPoint("TOPLEFT", 8, -8)
  scroll:SetPoint("BOTTOMRIGHT", -8, 8)
  page.content = CreateFrame("Frame", nil, scroll)
  page.content:SetSize(ES.UI.LIST_WIDTH, 1)
  scroll:SetScrollChild(page.content)
  page.rows = {}
  page.empty = Label(page.content, "", "GameFontDisable")
  page.empty:SetPoint("TOP", 0, -30)
  page.empty:SetWidth(600)

  -- Repintar: nombres que llegan, compras (la contabilidad las apunta al cambiar el
  -- dinero), resultados de la AH (cuántas baratas hay) y abrir o cerrar la AH
  for _, e in ipairs({ "GET_ITEM_INFO_RECEIVED", "PLAYER_MONEY", "COMMODITY_SEARCH_RESULTS_UPDATED",
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED" }) do
    ES.SafeRegister(page, e)
  end
  ES.SafeRegister(page, "BAG_UPDATE_DELAYED") -- (la lista del tramo cuenta lo que llevas)
  page:SetScript("OnEvent", function(self, event)
    if event == "GET_ITEM_INFO_RECEIVED" and not self.pendingItems then return end
    if self.refreshQueued then return end
    self.refreshQueued = true
    C_Timer.After(0.3, function()
      self.refreshQueued = false
      if self:IsVisible() then ES:RenderShopping() end
    end)
  end)
  page:SetScript("OnShow", function() ES:RenderShopping() end)
  self.shoppingPage = page
end

-- Filas de la lista (las mismas en la pestaña y en el panel pequeño de la AH)
local function BuildLines(st, ahOpen)
  local Signed = ES.UI.Signed
  local lines = {}
  for _, s in ipairs(st.lists) do
    local list = s.list
    -- (las listas guardadas antes llevan "(1 → 225)": la flecha no está en la fuente de WoW)
    lines[#lines + 1] = { section = (list.title or ""):gsub(" \226\134\146 ", " - ") } -- (U+2192, la flecha)
    for _, e in ipairs(s.items) do
      local it = e.it
      local name, texture = ES.UI.ItemLabel(it.itemID, L["Objeto "] .. it.itemID)
      local where = it.source == "ah" and string.format(L["AH ~%s/u"], ES.Money(it.unit or 0)) or string.format(L["vendedor %s/u"], ES.Money(it.unit or 0))
      local line = { icon = texture or 134400, item = it.itemID, current = it.itemID == selected and e.left > 0,
        source = it.source == "vendor" and "vendor" or "ah" }
      -- (la lista de una ruta empezada se calcula sola: no se quitan materiales a mano)
      if not list.live then
        line.onSkip = function() ES.Shopping.RemoveItem(list, it.itemID) ES:RenderShopping() end
        line.skipTitle, line.skipTip = L["Quitar de la lista"], L["Quita este material de la lista: ya no se compra."]
      end
      -- Tramo: lo que cuenta es lo que llevas; en las guardadas, lo comprado desde que la añadiste
      local progress = L["tienes %d de %d"] -- (todas las listas cuentan lo que llevas)
      -- Lo comprado en la AH que aún está en el correo ya cuenta (Ledger:OnTheWay): se dice
      local onWay = ES.Ledger and ES.Ledger.OnTheWay and ES.Ledger:OnTheWay(it.itemID) or 0
      local mail = onWay > 0 and (GREY .. " · " .. string.format(L["%d en el correo"], onWay) .. "|r") or ""
      if e.left == 0 then
        line.title = GREY .. (name or "") .. "|r"
        line.sub = GREEN .. string.format(progress, e.bought, it.need) .. "|r" .. mail
        line.value = "|TInterface\\RaidFrame\\ReadyCheck-Ready:16|t"
      else
        line.title = string.format("%d× %s", e.left, name or "")
        line.sub = where .. (e.bought > 0 and (" · " .. string.format(progress, e.bought, it.need)) or "") .. mail
        -- Abierta su compra: cuántas hay baratas ahora
        local t = it.source == "ah" and it.itemID == selected and ES.CommodityTiers and ES:CommodityTiers(it.itemID, it.unit)
        if t and t.next and t.cheap < e.left then
          line.sub = line.sub .. " · " .. ORANGE .. string.format(L["solo %d baratas; luego %s/u"], t.cheap, ES.Money(t.next)) .. "|r"
        end
        line.value = Signed(e.left * (it.unit or 0))
        if it.source == "ah" then
          line.onClick = function() Buy(it.itemID, e.left, it.unit) end
          line.tooltip = function(row)
            GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. it.itemID)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(ahOpen and L["Clic: abrir su compra en la AH con la cantidad puesta."] or L["Abre la Casa de Subastas para comprar."], 0.5, 0.8, 1, true)
            GameTooltip:Show()
          end
        end
      end
      lines[#lines + 1] = line
    end
    if list.live then
      -- Ruta empezada: se va sola al acabar la ruta (el modo se cambia en la ruta). Su
      -- ✕ la quita sin dejar la ruta (si no, no había forma de quitarla); vuelve desde
      -- la vista Materiales de la ruta. El panel pequeño de la AH no enseña los totales
      local sub
      if list.whole then
        sub = s.done == s.total and (GREEN .. L["Tienes todo lo que queda de ruta."] .. "|r")
          or L["Todo lo que queda de ruta. Se cambia a tramos en la vista Materiales de la ruta."]
      else
        sub = s.done == s.total and (GREEN .. L["Tienes lo de este tramo. Al acabarlo sale el siguiente."] .. "|r")
          or L["Solo este tramo, con un margen por si los puntos tardan en subir. Al acabarlo sale el siguiente."]
      end
      lines[#lines + 1] = { total = true, icon = KIND_ICON.route,
        title = string.format(L["%d de %d listos"], s.done, s.total), sub = sub,
        value = s.cost > 0 and Signed(s.cost) or "",
        onSkip = function()
          ES.Shopping.SetRouteListHidden(list.key, true)
          ES:Print(string.format(L["%s: quitada de la Lista de compra. Tu ruta sigue empezada; vuelve a ponerla desde la vista Materiales de la ruta."], list.title))
          ES:RenderShopping()
          if ES.RefreshProfessionPages then ES:RefreshProfessionPages() end
        end,
        skipTitle = L["Quitar de la lista"],
        skipTip = L["Quitar la lista de esta ruta. La ruta sigue empezada; se vuelve a poner desde su vista Materiales."] }
    else
    lines[#lines + 1] = { total = true, icon = KIND_ICON[list.kind],
      title = string.format(L["%d de %d listos"], s.done, s.total),
      sub = s.done == s.total and (GREEN .. L["Ya lo tienes todo: quítala con la |TInterface/Buttons/UI-GroupLoot-Pass-Up:0|t."] .. "|r")
        or L["Cuenta lo que llevas en las bolsas."],
      -- (la ✕ de la fila del total quita la lista entera)
      value = s.cost > 0 and Signed(s.cost) or "",
      onSkip = function() ES.Shopping.Remove(list) ES:RenderShopping() end,
      skipTitle = L["Quitar de la lista"], skipTip =L["Quitar esta lista. No cambia nada de lo que has comprado."] }
    end
  end
  return lines
end

local RenderMini -- (panel pequeño junto a la AH, abajo)

function ES:RenderShopping()
  local st = ES.Shopping.Status()
  local ahOpen = ES:IsAuctionHouseOpen()
  local lines = BuildLines(st, ahOpen)
  RenderMini(st, lines, ahOpen)
  local page = self.shoppingPage
  if not page or not page:IsVisible() then return end

  page.subtitle:SetText(L["Añade materiales desde una ruta (vista Materiales), Ganar dinero o la calculadora."])
  page.progressText:SetText(st.total > 0 and string.format(L["%d de %d materiales comprados · te falta ~%s"], st.done, st.total, ES.Money(st.cost)) or "")
  page.bar:SetShown(st.total > 0)
  page.progress = st.total > 0 and st.done / st.total or 0
  page.bar:SetValue(page.progress)
  local nextID = ES.Shopping.NextToBuy(st, selected)
  page.nextButton:SetEnabled(ahOpen and nextID ~= nil)
  page.status:SetText(ahOpen and (GREY .. L["Clic en un material de la AH: abre su compra con la cantidad puesta (solo las baratas). Confirmas tú con Comprar ahora.|r"])
    or (ORANGE .. L["Abre la Casa de Subastas para comprar desde aquí.|r"]))
  page.empty:SetText(#lines == 0 and L["La lista está vacía. Añade materiales con el botón \"Añadir a la lista de compra\" de una ruta (vista Materiales), de Ganar dinero o de la calculadora."] or "")
  ES.UI.RenderLines(page, lines)
end

-- Añadir y avisar (lo usan los botones de cada fuente): chat, el sonido de las
-- monedas y la pestaña Lista de compra brilla, como cuando la lista cambia sola
function ES:AddToShopping(kind, title, items, opts)
  local list = ES.Shopping.Add(kind, title, items, opts)
  if list then
    ES:Print(string.format(L["Añadido a la lista de compra: %s (%d materiales)."], title, #list.items))
    ES:FlashTab("shopping", true)
  else
    ES:Print(L["No hay nada que comprar: ya tienes todos los materiales."])
  end
  ES:RenderShopping()
  return list
end

---------------------------------------------------------------------------
-- Panel pequeño junto a la AH: la misma lista, para comprar sin la ventana grande
---------------------------------------------------------------------------
local MINI_W, MINI_H, MINI_ROW, MINI_SECTION = 300, 440, 34, 20
local mini

-- Junto a la AH solo la lista para comprar con un clic: sin ✕ de quitar ni total (eso,
-- en la pestaña Lista de compra, "Ver completa"). Las filas, de lado a lado del panel
local MINI_ROW_W = MINI_W - 20

local function MiniRow(parent)
  local row = CreateFrame("Button", nil, parent)
  row:SetSize(MINI_ROW_W, MINI_ROW)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.82, 0.25, 0.10)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(24, 24)
  row.icon:SetPoint("LEFT", 4, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.value:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -4)
  row.value:SetJustifyH("RIGHT")
  row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 5, -1)
  row.title:SetPoint("RIGHT", row.value, "LEFT", -4, 0)
  row.title:SetJustifyH("LEFT")
  row.title:SetWordWrap(false)
  row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 5, 1)
  row.sub:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  row.sub:SetJustifyH("LEFT")
  row.sub:SetWordWrap(false)
  row.sub:SetTextColor(0.75, 0.72, 0.65)
  row.section = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.section:SetPoint("LEFT", 2, 0)
  row.section:SetPoint("RIGHT", -2, 0)
  row.section:SetJustifyH("LEFT")
  row.section:SetWordWrap(false)
  row:SetScript("OnClick", function(self) if self.line and self.line.onClick then self.line.onClick() end end)
  row:SetScript("OnEnter", function(self) if self.line and self.line.tooltip then self.line.tooltip(self) end end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return row
end

local MINI_TOP, MINI_BOTTOM = 76, 42 -- alto de la cabecera (título, subtítulo, barra) y de los botones

local function CreateMini(ahFrame)
  -- El mismo aspecto que las ventanas de vender junto al vendedor y la AH
  -- (VendorUI.lua, AuctionSellUI.lua): fondo, borde, "Crafter's Journal" y subtítulo
  local p = CreateFrame("Frame", "CraftersJournalShoppingMini", ahFrame, "BackdropTemplate")
  p:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  local G = ES.UI.BROWN.group
  p:SetBackdropColor(G[1], G[2], G[3], 0.99)
  p:SetBackdropBorderColor(0.52, 0.38, 0.17, 1)
  p:SetSize(MINI_W, MINI_H)
  p:SetPoint("TOPLEFT", ahFrame, "TOPRIGHT", 2, -12)
  p:SetFrameStrata(ahFrame:GetFrameStrata())
  if p.SetClampedToScreen then p:SetClampedToScreen(true) end
  p:EnableMouse(true)

  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("Crafter's Journal")
  local sub = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  sub:SetText(L["Lista de compra:"])
  local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function()
    -- (cerrada hasta la próxima vez que abras la AH; antes se quedaba cerrada siempre)
    ES.shopMiniClosed = true
    p:Hide()
  end)

  p.progressText = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  p.progressText:SetPoint("TOPLEFT", 12, -44)
  p.progressText:SetPoint("RIGHT", -12, 0)
  p.progressText:SetJustifyH("LEFT")
  p.bar = CreateFrame("StatusBar", nil, p)
  p.bar:SetPoint("TOPLEFT", 12, -60)
  p.bar:SetPoint("RIGHT", -12, 0)
  p.bar:SetHeight(6)
  p.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  p.bar:SetStatusBarColor(0.25, 0.8, 0.25)
  p.bar:SetMinMaxValues(0, 1)
  local barBg = p.bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints()
  barBg:SetColorTexture(0, 0, 0, 0.5)

  local scroll = ES.UI.WheelScroll(p)
  scroll:SetPoint("TOPLEFT", 10, -MINI_TOP)
  scroll:SetPoint("BOTTOMRIGHT", -10, MINI_BOTTOM)
  p.content = CreateFrame("Frame", nil, scroll)
  p.content:SetSize(MINI_ROW_W, 1)
  scroll:SetScrollChild(p.content)
  p.rows = {}
  p.empty = p.content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  p.empty:SetPoint("TOP", 0, -20)
  p.empty:SetWidth(MINI_W - 60)

  -- Para quitar listas o ver el resto: la pestaña Lista de compra
  local full = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  full:SetSize(MINI_W - 20, 24)
  full:SetPoint("BOTTOM", 0, 10)
  full:SetText(L["Ver completa"])
  full:SetScript("OnClick", function() ES:OpenShoppingAtAuction(ahFrame) end)

  -- Repintar: compras (la contabilidad las apunta al cambiar el dinero), resultados
  -- de la AH (cuántas baratas hay) y nombres que llegan
  for _, e in ipairs({ "PLAYER_MONEY", "COMMODITY_SEARCH_RESULTS_UPDATED", "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED" }) do
    ES.SafeRegister(p, e)
  end
  p:SetScript("OnEvent", function(self)
    if not self:IsShown() or self.refreshQueued then return end
    self.refreshQueued = true
    C_Timer.After(0.3, function()
      self.refreshQueued = false
      ES:RenderShopping()
    end)
  end)
  p:SetScript("OnShow", function() ES:RenderShopping() end)
  return p
end

RenderMini = function(st, lines, ahOpen)
  if not mini then return end
  -- Con la AH abierta y algo por comprar, sale (p. ej. si añades materiales con la AH
  -- abierta), salvo que lo cerraras o la ventana grande esté a su lado
  local main = CraftersJournalMainFrame
  if not mini:IsShown() and ahOpen and not ES.shopMiniClosed and not (main and main:IsShown())
    and ES:AuctionWindowsOn() and ES.Shopping.HasPending(st) then
    ES:PlaceShoppingMini()
    mini:Show()
  end
  if not mini:IsShown() then return end
  -- Junto a la AH, solo lo que se compra en la AH (lo del vendedor sale en la ventana
  -- del vendedor, VendorUI.lua): la barra y el "N de M" cuentan solo eso
  local ah = st.bySource and st.bySource.ah or st
  mini.progressText:SetText(ah.total > 0 and string.format(L["%d de %d materiales comprados · te falta ~%s"], ah.done, ah.total, ES.Money(ah.cost))
    or "")
  mini.bar:SetShown(ah.total > 0)
  mini.progress = ah.total > 0 and ah.done / ah.total or 0
  mini.bar:SetValue(mini.progress)
  -- Sin las filas de total de cada lista ("0 de 3 listos", con su ✕: eso, en la
  -- pestaña), sin las de vendedor y sin el título de una lista que se queda vacía
  local shown, section, vendorOnly = {}, nil, false
  for _, line in ipairs(lines) do
    if line.section then
      section = line
    elseif line.source == "vendor" and not line.total then
      vendorOnly = true -- (lo hay, pero se compra al vendedor)
    elseif not line.total then
      if section then shown[#shown + 1] = section section = nil end
      shown[#shown + 1] = line
    end
  end
  lines = shown
  -- Sin nada de la AH: si lo que queda es de vendedor, no está vacía (antes lo decía)
  mini.empty:SetText(#lines > 0 and ""
    or vendorOnly and L["Nada que comprar en la AH. Lo de tu lista que vende un vendedor sale en su ventana al abrirlo."]
    or L["La lista está vacía. Añade materiales con \"Añadir a la lista de compra\" en Ganar dinero, la calculadora o la vista Materiales de una ruta."])
  local y = 0
  for i, line in ipairs(lines) do
    local row = mini.rows[i] or MiniRow(mini.content)
    mini.rows[i] = row
    row.line = line
    local isSection = line.section ~= nil
    local h = isSection and MINI_SECTION or MINI_ROW
    row:SetHeight(h)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -y)
    row.section:SetText(isSection and ("|cffffd100" .. line.section .. "|r") or "")
    row.icon:SetShown(not isSection and line.icon ~= nil)
    if line.icon then row.icon:SetTexture(line.icon) end
    row.title:SetText(not isSection and line.title or "")
    row.sub:SetText(not isSection and line.sub or "")
    row.value:SetText(not isSection and line.value or "")
    -- (los mismos tonos que las filas de la ruta: total, actual y normal)
    local R = ES.UI.BROWN.row
    if line.total then row.bg:SetColorTexture(0.20, 0.14, 0.06, 0.95)
    elseif line.current then row.bg:SetColorTexture(0.30, 0.23, 0.08, 0.96)
    elseif isSection then row.bg:SetColorTexture(0, 0, 0, 0)
    else row.bg:SetColorTexture(R[1], R[2], R[3], R[4]) end
    y = y + h + 2
    row:Show()
  end
  for i = #lines + 1, #mini.rows do mini.rows[i]:Hide() end
  mini.content:SetHeight(math.max(1, y))
  -- Tan alto como su contenido (como las ventanas de vender), hasta MINI_H con scroll
  mini:SetHeight(math.min(MINI_H, MINI_TOP + math.max(y, 30) + MINI_BOTTOM))
  -- Sin nada pendiente, fuera (salvo que lo abrieras tú con el botón de la AH)
  if not ES.shopMiniForced and not ES.Shopping.HasPending(st) then mini:Hide() end
end

-- ¿Queda algo por comprar en la lista de compra? (en la AH: lo que sale en su panel)
function ES.Shopping.HasPending(st)
  st = st or ES.Shopping.Status()
  local ah = st.bySource and st.bySource.ah or st
  return (ah.total or 0) > (ah.done or 0)
end

-- Dónde va el panel de la lista de compra junto a la AH: a la derecha de la ventana de
-- vender en la AH si se ve (AuctionSellUI.lua); si no, pegado a la AH
function ES:PlaceShoppingMini()
  if not mini then return end
  local ah = AuctionHouseFrame or AuctionFrame
  local sell = CraftersJournalAuctionSellPanel
  mini:ClearAllPoints()
  if sell and sell:IsShown() then
    mini:SetPoint("TOPLEFT", sell, "TOPRIGHT", 4, 0)
  elseif ah then
    mini:SetPoint("TOPLEFT", ah, "TOPRIGHT", 2, -12)
  end
end

-- Al abrir la AH: si tenías la ventana grande abierta, se queda (al lado de la AH) y no
-- sale el panel pequeño (dos listas a la vez sobran); antes se cerraba siempre y
-- perdías lo que estabas mirando. Si estaba cerrada, el panel pequeño (salvo que lo
-- cerraras)
function ES:SetupShoppingMini(ahFrame)
  if not mini then mini = CreateMini(ahFrame) end
  -- Cada vez que abres la AH sale si hay algo que comprar (la X lo cierra solo hasta
  -- la próxima: antes se quedaba cerrado para siempre y no volvía a salir)
  ES.shopMiniClosed, ES.shopMiniForced = nil, nil
  ES.db.shopMiniHidden = nil -- (lo de versiones anteriores)
  local main = CraftersJournalMainFrame
  if main and main:IsShown() then
    main:ClearAllPoints()
    main:SetPoint("TOPLEFT", ahFrame, "TOPRIGHT", 4, 0) -- (se queda dentro de la pantalla: SetClampedToScreen)
    mini:Hide()
    ES:MiniOnMainHide() -- (y al cerrarla, con la AH abierta, sale el panel pequeño)
    return
  end
  ES:PlaceShoppingMini()
  -- (desactivada en las opciones, no sale sola: el botón de la AH la abre a mano)
  mini:SetShown(ES:AuctionWindowsOn() and ES.Shopping.HasPending())
  ES:RenderShopping()
end

-- El botón sobre la AH: enseñar u ocultar el panel pequeño (a mano: sale aunque no
-- quede nada por comprar)
function ES:ToggleShoppingMini(ahFrame)
  if not mini then return self:SetupShoppingMini(ahFrame) end
  local show = not mini:IsShown()
  ES.shopMiniClosed = not show or nil
  ES.shopMiniForced = show or nil
  ES:PlaceShoppingMini()
  mini:SetShown(show)
  if show then ES:RenderShopping() end
end

-- "Ver completa": la pestaña grande al lado de la AH, en lugar del panel pequeño
-- (que vuelve al cerrar la ventana grande, con la AH aún abierta)
function ES:ShowFullShopping()
  if mini and mini:IsShown() then
    mini:Hide()
    self:MiniOnMainHide()
  end
end

-- Al cerrar la ventana grande con la AH abierta, vuelve el panel pequeño
function ES:MiniOnMainHide()
  local main = self:GetMainFrame()
  if not main.cjMiniHook then
    main.cjMiniHook = true
    main:HookScript("OnHide", function()
      if ES:IsAuctionHouseOpen() and mini and not ES.shopMiniClosed and ES:AuctionWindowsOn() and ES.Shopping.HasPending() then
        ES:PlaceShoppingMini()
        mini:Show()
        ES:RenderShopping()
      end
    end)
  end
end

ES.ShoppingMini = function() return mini end -- para pruebas
