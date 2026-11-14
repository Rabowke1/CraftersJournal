local _, ES = ...
local L = ES.L

-- Pestaña "Calculadora" (Calculator.lua): a la izquierda, tus cálculos guardados con su
-- beneficio (✕ para borrar); a la derecha, la hoja del elegido: materiales en crudo,
-- cantidad, precio (casilla: se puede escribir), de dónde sale y total; venta,
-- comisión, depósito y beneficio. Arriba, un buscador para añadir recetas.

local Calc = ES.Calc
local GREY, ORANGE, GOLD = "|cff999999", "|cffff9933", "|cffffd100"
local LIST_W = 250
local BUTTON_W = 160 -- los tres botones de abajo, en una fila
local FOOTER_H = 10 + 22 + 6 -- alto de esa fila (margen, botón, hueco): las notas acaban encima
local ROW_H = 30      -- filas de material: casillas de 20 px con aire arriba y abajo
local LINE_H = 26     -- líneas de resumen (materiales, venta, comisión, depósito)
local MAX_RESULTS = 8

local function Money(c) return ES.Money(c) end

-- Nombre e icono de la receta de un cálculo
local function RecipeLabel(c)
  local data = ES.Data[c.prof]
  local r = data and data.recipes and data.recipes[c.recipe]
  if not r then return L["Receta desconocida"], ES.ICON end
  local _, _, texture = ES:GetItemData(r.out and r.out[1] or 0)
  local prof
  for _, p in ipairs(ES.PROFESSIONS) do if p.key == c.prof then prof = p end end
  return r.name or ("#" .. c.recipe), texture or (prof and prof.icon) or ES.ICON
end

local function SourceText(res, source)
  if source == "manual" then return GOLD .. L["a mano"] .. "|r" end
  if source == "ah" then return L["AH"] end
  -- (el descuento de ciudad va en la nota de abajo: "vendedor −10%" no cabía)
  if source == "vendor" then return L["vendedor"] end
  return ORANGE .. L["sin precio"] .. "|r"
end

-- Precio por unidad: se lee como texto con su fuente pegada ("6s 50c · AH"; a mano, en
-- dorado). Clic: se abre una sola casilla con el precio para escribirlo ("6.5" = 6s
-- 50c, "1g 20s", Calc.ParseMoney). Intro o salir de ella guarda: `commit(cobre)`;
-- vacía, commit(nil) (vuelve al automático). Escape la cierra sin cambiar nada.
-- (Antes eran tres casillas, oro/plata/cobre, en cada fila: la hoja se veía muy cargada)
local function PriceField(parent, commit)
  local f = CreateFrame("Button", nil, parent)
  f:SetHeight(20)
  local hl = f:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetColorTexture(1, 0.82, 0.25, 0.10)
  f.text = ES.UI.Label(f, "", "GameFontHighlightSmall")
  f.text:SetPoint("LEFT", 4, 0)
  f.text:SetPoint("RIGHT", -4, 0)
  f.text:SetJustifyH("LEFT")
  f.text:SetWordWrap(false)
  local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  box:SetSize(110, 20)
  box:SetPoint("LEFT", 6, 0)
  box:SetAutoFocus(false)
  box:Hide()
  f.box = box
  local function Close()
    box:Hide()
    f.text:Show()
  end
  local function Save()
    if not box:IsShown() then return end
    local text = strtrim(box:GetText() or "")
    local copper = Calc.ParseMoney(text)
    Close()
    -- (lo que no se entiende no cambia nada; vacío = automático)
    if text == "" or copper then commit(copper) else ES:RenderCalculator() end
  end
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEditFocusLost", Save)
  box:SetScript("OnEscapePressed", function(self)
    Close()
    self:ClearFocus()
  end)
  f:SetScript("OnClick", function()
    f.text:Hide()
    box:Show()
    box:SetText(f.copper and Calc.FormatMoney(f.copper) or "")
    box:SetFocus()
    box:HighlightText()
  end)
  f:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L["Clic: escribir el precio por unidad"])
    GameTooltip:AddLine(L["Por ejemplo 6.5 (6s 50c) o 1g 20s. Vacío vuelve al precio automático; Escape no cambia nada."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- Pone el precio y de dónde sale, salvo si lo estás escribiendo
  function f:SetValue(copper, sourceText)
    if box:IsShown() and box:HasFocus() == true then return end
    self.copper = copper
    self.text:SetText((copper and Money(copper) or (ORANGE .. "?|r")) .. (sourceText and (GREY .. " · |r" .. sourceText) or ""))
  end
  return f
end

---------------------------------------------------------------------------
-- Buscador: recetas de todas las profesiones; primero las que sabes
---------------------------------------------------------------------------
local function SearchRecipes(query)
  query = query:lower()
  local out = {}
  for _, prof in ipairs(ES.PROFESSIONS) do
    local data = ES.Data[prof.key]
    if data and data.recipes then
      for id, r in pairs(data.recipes) do
        if not r.conversion and ((r.name or ""):lower():find(query, 1, true) or (r.nameEN or ""):lower():find(query, 1, true)) then
          out[#out + 1] = { prof = prof.key, id = id, recipe = r, known = ES:IsRecipeKnown(id) }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.known ~= b.known then return a.known end
    if a.prof ~= b.prof then return a.prof < b.prof end
    return (a.recipe.train or 0) < (b.recipe.train or 0)
  end)
  return out
end

local function CreateSearch(page, head)
  local box = CreateFrame("EditBox", nil, head, "InputBoxTemplate")
  page.search = box
  box:SetSize(240, 22)
  box:SetPoint("RIGHT", -16, 0)
  box:SetAutoFocus(false)
  local hint = ES.UI.Label(box, L["Añadir receta: escribe su nombre"], "GameFontDisableSmall")
  hint:SetPoint("LEFT", 4, 0)

  local list = CreateFrame("Frame", nil, page, "BackdropTemplate")
  page.results = list
  list:SetPoint("TOPRIGHT", box, "BOTTOMRIGHT", 4, -2)
  list:SetWidth(320)
  list:SetFrameStrata("TOOLTIP")
  list:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 10, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  list:SetBackdropColor(0.045, 0.042, 0.037, 0.995)
  list:SetBackdropBorderColor(0.48, 0.40, 0.27, 1)
  list:Hide()
  list.rows = {}

  local function Row(i)
    local row = list.rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, list)
    row:SetHeight(22)
    row:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 22)
    row:SetPoint("TOPRIGHT", -5, -5 - (i - 1) * 22)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT", 4, 0)
    row.text = ES.UI.Label(row, "", "GameFontHighlight")
    row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.text:SetPoint("RIGHT", -80, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.sub = ES.UI.Label(row, "", "GameFontDisableSmall")
    row.sub:SetPoint("RIGHT", -6, 0)
    row:SetScript("OnClick", function(self)
      if not self.result then return end
      Calc:Add(self.result.prof, self.result.id)
      box:SetText("")
      box:ClearFocus()
      list:Hide()
      ES:RenderCalculator()
    end)
    list.rows[i] = row
    return row
  end

  local function Refresh()
    local text = strtrim(box:GetText() or "")
    hint:SetShown(text == "")
    if text:len() < 2 then list:Hide() return end
    local results = SearchRecipes(text)
    local shown = math.min(MAX_RESULTS, #results)
    for i = 1, shown do
      local res, row = results[i], Row(i)
      row.result = res
      local _, _, texture = ES:GetItemData(res.recipe.out and res.recipe.out[1] or 0)
      row.icon:SetTexture(texture or ES.ICON)
      row.text:SetText(res.recipe.name)
      row.text:SetTextColor(res.known and 1 or 0.6, res.known and 1 or 0.6, res.known and 1 or 0.6)
      row.sub:SetText(ES:ProfLabel(res.prof))
      row:Show()
    end
    for i = shown + 1, #list.rows do list.rows[i]:Hide() end
    if shown == 0 then
      local row = Row(1)
      row.result = nil
      row.icon:SetTexture(nil)
      row.text:SetText(L["Sin resultados"])
      row.text:SetTextColor(0.5, 0.5, 0.5)
      row.sub:SetText("")
      row:Show()
      shown = 1
    end
    list:SetHeight(10 + shown * 22)
    list:Show()
  end
  box:SetScript("OnTextChanged", Refresh)
  box:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() list:Hide() end)
  box:SetScript("OnEnterPressed", function(self)
    local first = list.rows[1]
    if list:IsShown() and first and first.result then first:GetScript("OnClick")(first) else self:ClearFocus() end
  end)
  box:SetScript("OnEditFocusLost", function()
    C_Timer.After(0.2, function() if box:HasFocus() ~= true then list:Hide() end end)
  end)
  page.searchRefresh = Refresh
end

---------------------------------------------------------------------------
-- Lista de cálculos guardados
---------------------------------------------------------------------------
local function SavedRow(page, i)
  local row = page.saved[i]
  if row then return row end
  row = CreateFrame("Button", nil, page.listPanel)
  row:SetHeight(36)
  row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 38)
  row:SetPoint("TOPRIGHT", -6, -6 - (i - 1) * 38)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.sel = row:CreateTexture(nil, "BACKGROUND")
  row.sel:SetAllPoints()
  row.sel:SetColorTexture(0.8, 0.6, 0.2, 0.18)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(28, 28)
  row.icon:SetPoint("LEFT", 4, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  -- Ratón sobre el icono: el tooltip de lo que fabrica (el clic sigue eligiendo el cálculo)
  row.iconHover = ES.UI.ItemIconTooltip(row, row.icon, function() return row.itemID end)
  row.name = ES.UI.Label(row, "", "GameFontHighlightSmall")
  row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
  row.name:SetPoint("RIGHT", -24, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)
  row.profit = ES.UI.Label(row, "", "GameFontHighlightSmall")
  row.profit:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
  row.del = CreateFrame("Button", nil, row)
  row.del:SetSize(16, 16)
  row.del:SetPoint("RIGHT", -4, 0)
  row.del:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
  row.del:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  row.del.row = row
  row.del:SetScript("OnClick", function(self)
    Calc:Remove(self.row.calcID)
    ES:RenderCalculator()
  end)
  row.del:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Borrar este cálculo"])
    GameTooltip:Show()
  end)
  row.del:SetScript("OnLeave", function() GameTooltip:Hide() end)
  row:SetScript("OnClick", function(self)
    Calc:Select(self.calcID)
    ES:RenderCalculator()
  end)
  page.saved[i] = row
  return row
end

---------------------------------------------------------------------------
-- Hoja del cálculo elegido
---------------------------------------------------------------------------
-- Columnas (x desde la izquierda del panel; el total, pegado a la derecha). La hoja
-- mide ~610 px con la ventana de 840: nombre 130, cantidad 36 (14 de aire), el precio
-- con su fuente ("6s 50c · AH") hasta el total, ~100 a la derecha
local COL_NAME, COL_QTY_RIGHT = 36, 196
local COL_PRICE = COL_QTY_RIGHT + 14
-- El total va pegado a la derecha y crece con el oro ("1g 48s 80c" ~90 px): el precio
-- acaba siempre TOTAL_W antes del borde, así nunca se pisan
local TOTAL_W = 104
local INDENT = 18 -- sangría de lo que va dentro de un intermedio

local function SheetRow(page, i)
  local row = page.sheetRows[i]
  if row then return row end
  local p = page.sheet
  row = CreateFrame("Frame", nil, p)
  row:SetHeight(ROW_H)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(20, 20)
  row.icon:SetPoint("LEFT", 10, 0)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.iconHover = ES.UI.ItemIconTooltip(row, row.icon, function() return row.itemID end) -- (el material)
  row.name = ES.UI.Label(row, "", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", COL_NAME, 0)
  row.name:SetWidth(COL_QTY_RIGHT - 42 - COL_NAME)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)
  row.qty = ES.UI.Label(row, "", "GameFontHighlightSmall")
  row.qty:SetPoint("RIGHT", row, "LEFT", COL_QTY_RIGHT, 0)
  row.qty:SetWidth(36)
  row.qty:SetJustifyH("RIGHT")
  row.price = PriceField(row, function(copper)
    local c = Calc:Selected()
    if not c or not row.itemID then return end
    c.prices[row.itemID] = copper -- nil: vuelve al automático
    -- (cuándo: vale hasta que un escaneo posterior traiga ese objeto; ver Calc:Compute)
    c.priceTimes = c.priceTimes or {}
    c.priceTimes[row.itemID] = copper and time() or nil
    ES:RenderCalculator()
  end)
  row.price:SetPoint("LEFT", COL_PRICE, 0)
  row.price:SetPoint("RIGHT", -TOTAL_W, 0)
  row.total = ES.UI.Label(row, "", "GameFontHighlightSmall")
  row.total:SetPoint("RIGHT", -14, 0)
  row.total:SetJustifyH("RIGHT")
  page.sheetRows[i] = row
  return row
end

-- Fila de un intermedio (Bolt of Mageweave...): cómo se consigue, lo que cuesta, y clic
-- para cambiar entre fabricarlo y comprarlo hecho (Calc:ToggleVia). Va encima de los
-- materiales: si lo fabricas, sus materiales salen debajo; si lo compras, sale él
local function MadeRow(page, i)
  page.madeRows = page.madeRows or {}
  local row = page.madeRows[i]
  if row then return row end
  row = CreateFrame("Button", nil, page.sheet)
  row:SetHeight(ROW_H)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(20, 20)
  row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  row.iconHover = ES.UI.ItemIconTooltip(row, row.icon, function() return row.m and row.m.itemID end)
  row.name = ES.UI.Label(row, "", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetPoint("RIGHT", row, "LEFT", COL_PRICE - 6, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)
  row.source = ES.UI.Label(row, "", "GameFontHighlightSmall")
  row.source:SetPoint("LEFT", COL_PRICE + 4, 0)
  row.source:SetPoint("RIGHT", -TOTAL_W, 0)
  row.source:SetJustifyH("LEFT")
  row.source:SetWordWrap(false)
  row.total = ES.UI.Label(row, "", "GameFontDisableSmall")
  row.total:SetPoint("RIGHT", -14, 0)
  row.total:SetJustifyH("RIGHT")
  row:SetScript("OnClick", function(self)
    local c = Calc:Selected()
    if not (c and self.m) then return end
    Calc:ToggleVia(c, self.m)
    ES:RenderCalculator()
    if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
  end)
  row:SetScript("OnEnter", function(self)
    local m = self.m
    if not m then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine((ES.UI.ItemLabel(m.itemID, "#" .. m.itemID)))
    local W = { 1, 1, 1, 1, 1, 1 }
    GameTooltip:AddDoubleLine(L["Fabricarlo (sus materiales)"], m.craftCost and ES.Money(m.craftCost) or (ORANGE .. L["sin precio"] .. "|r"), unpack(W))
    GameTooltip:AddDoubleLine(L["Comprarlo hecho"], m.buyCost and ES.Money(m.buyCost) or (ORANGE .. L["sin precio"] .. "|r"), unpack(W))
    local cheapest = (m.buyCost and (not m.craftCost or m.buyCost < m.craftCost)) and "buy" or "craft"
    GameTooltip:AddLine(cheapest == "buy" and L["Lo más barato: comprarlo hecho."] or L["Lo más barato: fabricarlo."], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(m.mode == "craft" and L["Clic: comprarlo hecho en vez de fabricarlo."] or L["Clic: fabricarlo en vez de comprarlo hecho."], 0.5, 0.8, 1, true)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  page.madeRows[i] = row
  return row
end

-- Línea de resumen (etiqueta a la izquierda, importe a la derecha)
local function SummaryLine(p, template)
  local line = CreateFrame("Frame", nil, p)
  line:SetHeight(LINE_H)
  line.label = ES.UI.Label(line, "", template or "GameFontHighlightSmall")
  line.label:SetPoint("LEFT", COL_NAME, 0)
  line.label:SetJustifyH("LEFT")
  line.value = ES.UI.Label(line, "", template or "GameFontHighlightSmall")
  line.value:SetPoint("RIGHT", -14, 0)
  line.value:SetJustifyH("RIGHT")
  return line
end

local function CreateSheet(page)
  local p = page.sheet
  page.title = ES.UI.Label(p, "", "GameFontNormalLarge")
  page.title:SetPoint("TOPLEFT", 14, -12)
  page.title:SetPoint("RIGHT", -170, 0)
  page.title:SetJustifyH("LEFT")
  page.title:SetWordWrap(false)
  page.titleSub = ES.UI.Label(p, "", "GameFontDisableSmall")
  page.titleSub:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -3)

  -- Fabricaciones
  local qtyLabel = ES.UI.Label(p, L["Fabricaciones"], "GameFontNormalSmall")
  qtyLabel:SetPoint("TOPRIGHT", -84, -14)
  page.qty = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
  page.qty:SetSize(50, 20)
  page.qty:SetPoint("LEFT", qtyLabel, "RIGHT", 8, 0)
  page.qty:SetAutoFocus(false)
  page.qty:SetNumeric(true)
  page.qty:SetJustifyH("CENTER")
  local function SaveQty(self)
    local c, n = Calc:Selected(), tonumber(self:GetText())
    if c and n and n >= 1 then c.qty = math.min(n, 9999) end
    ES:RenderCalculator()
  end
  page.qty:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  page.qty:SetScript("OnEditFocusLost", SaveQty)

  -- Cabecera de columnas
  local head = CreateFrame("Frame", nil, p)
  head:SetHeight(18)
  head:SetPoint("TOPLEFT", 6, -54)
  head:SetPoint("TOPRIGHT", -6, -54)
  for _, col in ipairs({ { L["Material"], COL_NAME, "LEFT" }, { L["Cantidad"], COL_QTY_RIGHT, "RIGHT" },
    { L["Precio por unidad"], COL_PRICE + 4, "LEFT" } }) do
    local fs = ES.UI.Label(head, col[1], "GameFontNormalSmall")
    fs:SetPoint(col[3], head, "LEFT", col[2], 0)
  end
  local totalHead = ES.UI.Label(head, L["Total"], "GameFontNormalSmall")
  totalHead:SetPoint("RIGHT", -14, 0)
  page.colHead = head

  page.sheetRows = {}
  page.matTotal = SummaryLine(p)
  -- Venta: casilla del precio por unidad
  page.saleLine = SummaryLine(p)
  page.saleLine.label:SetWidth(COL_PRICE - COL_NAME - 8)
  page.saleLine.label:SetWordWrap(false)
  page.saleBox = PriceField(page.saleLine, function(copper)
    local c = Calc:Selected()
    if not c then return end
    c.sale = copper -- nil: vuelve al automático
    c.saleTime = copper and time() or nil
    ES:RenderCalculator()
  end)
  page.saleBox:SetPoint("LEFT", COL_PRICE, 0)
  page.saleBox:SetPoint("RIGHT", -TOTAL_W, 0)
  page.cutLine = SummaryLine(p) -- (solo al vender en la AH)
  page.profitLine = SummaryLine(p, "GameFontNormalLarge")
  -- Ratón sobre el beneficio: lo que darían las otras formas de vender y el depósito
  -- (antes en una línea y una fila propias: la hoja se veía muy cargada)
  page.profitLine:EnableMouse(true)
  page.profitLine:SetScript("OnEnter", function(self)
    local res = page.lastRes
    if not res then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L["Beneficio"])
    if res.canChoose then
      local W = { 0.8, 0.8, 0.8, 1, 1, 1 }
      GameTooltip:AddDoubleLine(L["En la AH"], ES.UI.Signed(-res.profitAH), unpack(W))
      GameTooltip:AddDoubleLine(L["Por el chat de comercio (sin comisión)"], ES.UI.Signed(-res.profitTrade), unpack(W))
      if res.profitVendor then GameTooltip:AddDoubleLine(L["Al vendedor"], ES.UI.Signed(-res.profitVendor), unpack(W)) end
    end
    if res.deposit and res.deposit > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine(string.format(L["Depósito: %s (%d subastas de %d h). Se devuelve si se vende: no resta del beneficio; lo pierdes si caduca."],
        ES.Money(res.deposit), res.listings or 0, res.hours or 24), 0.8, 0.8, 0.8, true)
    end
    GameTooltip:Show()
  end)
  page.profitLine:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Dónde se vende, en un solo selector: "Vender en: AH · 24 h". Clic: un menú con la
  -- AH (2, 8 o 24 h), el chat de comercio y el vendedor (antes, dos filas de botones)
  page.sellOnLine = SummaryLine(p)
  page.sellOnLine.label:SetText(L["Vender en:"])
  local sellOn = CreateFrame("Button", nil, page.sellOnLine, "BackdropTemplate")
  page.sellOn = sellOn
  sellOn:SetSize(170, 20)
  sellOn:SetPoint("LEFT", page.sellOnLine.label, "RIGHT", 8, 0)
  sellOn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  sellOn:SetBackdropColor(0.10, 0.08, 0.06, 0.95)
  sellOn:SetBackdropBorderColor(0.52, 0.38, 0.17, 1)
  sellOn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  sellOn.text = ES.UI.Label(sellOn, "", "GameFontHighlightSmall")
  sellOn.text:SetPoint("LEFT", 8, 0)
  sellOn.text:SetPoint("RIGHT", -18, 0)
  sellOn.text:SetJustifyH("LEFT")
  local caret = sellOn:CreateTexture(nil, "OVERLAY")
  caret:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
  caret:SetSize(12, 12)
  caret:SetPoint("RIGHT", -4, -2)
  local OPTIONS = {
    { channel = "ah", hours = 24 }, { channel = "ah", hours = 8 }, { channel = "ah", hours = 2 },
    { channel = "trade" }, { channel = "vendor" },
  }
  local function OptionLabel(o)
    if o.channel == "ah" then return string.format(L["AH · %d h"], o.hours) end
    return o.channel == "vendor" and L["Vendedor"] or L["Chat de comercio"]
  end
  page.SellOnLabel = OptionLabel
  local menu = CreateFrame("Frame", nil, sellOn, "BackdropTemplate")
  page.sellOnMenu = menu
  menu:SetSize(190, #OPTIONS * 20 + 8)
  menu:SetPoint("TOPLEFT", sellOn, "BOTTOMLEFT", 0, -2)
  menu:SetFrameStrata("TOOLTIP")
  menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  menu:SetBackdropColor(0.055, 0.05, 0.043, 0.99)
  menu:SetBackdropBorderColor(0.57, 0.43, 0.20, 1)
  menu:Hide()
  menu.options = {}
  for i, o in ipairs(OPTIONS) do
    local b = CreateFrame("Button", nil, menu)
    b:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 20)
    b:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * 20)
    b:SetHeight(20)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.text = ES.UI.Label(b, OptionLabel(o), "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 8, 0)
    b.option = o
    b:SetScript("OnClick", function(self)
      local c = Calc:Selected()
      if c then
        c.channel = self.option.channel
        if self.option.hours then c.hours = self.option.hours end
      end
      page.CloseSellOn()
      ES:RenderCalculator()
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      local opt = self.option
      if opt.channel == "ah" then
        GameTooltip:AddLine(string.format(L["Subasta de %d h"], opt.hours))
        GameTooltip:AddLine(string.format(L["Depósito: el %d%% del precio de vendedor, mínimo %s por subasta. Se devuelve si se vende; lo pierdes si caduca o la cancelas."],
          Calc.DepositPct(opt.hours), ES.Money(Calc.MIN_DEPOSIT)), 0.8, 0.8, 0.8, true)
      elseif opt.channel == "vendor" then
        GameTooltip:AddLine(L["Vender al vendedor"])
        GameTooltip:AddLine(L["Al precio que paga el vendedor: venta segura, sin comisión ni depósito."], 0.8, 0.8, 0.8, true)
      else
        GameTooltip:AddLine(L["Vender por el chat de comercio"])
        GameTooltip:AddLine(L["Cara a cara (comercio): sin comisión de la AH ni depósito."], 0.8, 0.8, 0.8, true)
      end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    menu.options[i] = b
  end
  local function SetOpen(open)
    sellOn.open = open or nil
    menu:SetShown(open and true or false)
  end
  sellOn:SetScript("OnClick", function() SetOpen(not sellOn.open) end)
  sellOn:SetScript("OnHide", function() SetOpen(false) end)
  page.CloseSellOn = function() SetOpen(false) end
  page.note = ES.UI.Label(p, "", "GameFontDisableSmall")
  page.note:SetJustifyH("LEFT")

  -- Abajo: el botón principal, "Añadir a la lista de compra", a la derecha y más
  -- grande; "Precios automáticos", pequeño a la izquierda (antes tres botones iguales)
  page.reset = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  page.reset:SetSize(BUTTON_W - 30, 20)
  page.reset:SetPoint("BOTTOMLEFT", 12, 11)
  page.reset:SetText(L["Precios automáticos"])
  page.reset:SetScript("OnClick", function()
    local c = Calc:Selected()
    if c then c.prices, c.sale, c.priceTimes, c.saleTime = {}, nil, nil, nil end
    ES:RenderCalculator()
  end)
  page.reset:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L["Borra los precios que has escrito en este cálculo y vuelve a los del último escaneo y el vendedor."], 1, 1, 1, true)
    GameTooltip:Show()
  end)
  page.reset:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Los materiales de este cálculo a la Lista de compra (ShoppingUI.lua)
  page.addShopping = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  page.addShopping:SetSize(BUTTON_W + 60, 24)
  -- (los botones en una fila abajo: las notas acaban encima, ver FOOTER_H)
  page.addShopping:SetPoint("BOTTOMRIGHT", -12, 10)
  page.addShopping:SetText(L["Añadir a la lista de compra"])
  page.addShopping:SetScript("OnClick", function()
    local c = Calc:Selected()
    local res = c and Calc:Compute(c)
    if not res then return end
    local items = {}
    for _, r in ipairs(res.rows or {}) do
      items[#items + 1] = { itemID = r.itemID, quantity = r.qty, unit = r.price or 0, source = r.source == "vendor" and "vendor" or "ah" }
    end
    ES:AddToShopping("calc", string.format(L["Calculadora: %s ×%d"], (RecipeLabel(c)), c.qty or 1), items,
      { key = "calc:" .. tostring(c.id), minusBags = true })
  end)
  page.addShopping:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L["Añadir a la lista de compra"])
    GameTooltip:AddLine(L["Los materiales de este cálculo que te faltan (descontando lo que llevas) pasan a la pestaña Lista de compra, desde donde los compras con la AH abierta."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
  end)
  page.addShopping:SetScript("OnLeave", function() GameTooltip:Hide() end)

end

function ES:CreateCalculatorPage(page)
  local UI = ES.UI
  page.group = UI.GroupPanel(page)
  local head = UI.Panel(page, UI.BROWN.card[1], UI.BROWN.card[2], UI.BROWN.card[3], UI.BROWN.card[4])
  head:SetPoint("TOPLEFT", UI.PAD, -UI.PAD + 2)
  head:SetPoint("TOPRIGHT", -UI.PAD, -UI.PAD + 2)
  head:SetHeight(66)
  local icon = head:CreateTexture(nil, "ARTWORK")
  icon:SetSize(44, 44)
  icon:SetPoint("LEFT", 12, 0)
  icon:SetTexture("Interface\\Icons\\INV_Misc_Note_02")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local title = UI.Label(head, L["Calculadora"], "GameFontNormalHuge")
  title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, 2)
  title:SetTextColor(0.96, 0.79, 0.25)
  local sub = UI.Label(head, L["Cuánto ganas con una receta: materiales en crudo, venta, comisión y depósito. Escribe tus precios si la AH ha cambiado."], "GameFontHighlightSmall")
  sub:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 12, 2)
  sub:SetPoint("RIGHT", -270, 0)
  sub:SetJustifyH("LEFT")
  CreateSearch(page, head)

  page.listPanel = UI.Panel(page, UI.BROWN.list[1], UI.BROWN.list[2], UI.BROWN.list[3], UI.BROWN.list[4])
  page.listPanel:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
  page.listPanel:SetPoint("BOTTOMLEFT", UI.PAD, UI.PAD)
  page.listPanel:SetWidth(LIST_W)
  page.saved = {}
  page.listEmpty = UI.Label(page.listPanel, L["Aún no tienes cálculos. Busca una receta arriba a la derecha para añadir el primero."], "GameFontDisable")
  page.listEmpty:SetPoint("TOPLEFT", 12, -14)
  page.listEmpty:SetPoint("RIGHT", -12, 0)
  page.listEmpty:SetJustifyH("LEFT")

  page.sheet = UI.Panel(page, UI.BROWN.list[1], UI.BROWN.list[2], UI.BROWN.list[3], UI.BROWN.list[4])
  page.sheet:SetPoint("TOPLEFT", page.listPanel, "TOPRIGHT", 8, 0)
  page.sheet:SetPoint("BOTTOMRIGHT", -UI.PAD, UI.PAD)
  CreateSheet(page)

  page:SetScript("OnShow", function() ES:RenderCalculator() end)
  -- Llegan nombres e iconos que faltaban: se repinta
  ES.SafeRegister(page, "GET_ITEM_INFO_RECEIVED")
  page:SetScript("OnEvent", function(self)
    if self.pendingItems and not self.refreshQueued then
      self.refreshQueued = true
      C_Timer.After(0.5, function()
        self.refreshQueued = false
        if self:IsVisible() then ES:RenderCalculator() end
      end)
    end
  end)
  self.calculatorPage = page
end

local function Qty(n)
  if math.abs(n - math.floor(n + 0.5)) < 0.01 then return tostring(math.floor(n + 0.5)) end
  return string.format("%.1f", n)
end

function ES:RenderCalculator()
  local page = self.calculatorPage
  if not page or not page:IsVisible() then return end
  page.pendingItems = false
  local Signed = ES.UI.Signed

  -- Lista de guardados
  local list = Calc:List()
  local selected = Calc:Selected()
  for i, c in ipairs(list) do
    local row = SavedRow(page, i)
    row.calcID = c.id
    local name, texture = RecipeLabel(c)
    row.icon:SetTexture(texture)
    local data = ES.Data[c.prof]
    local r = data and data.recipes and data.recipes[c.recipe]
    row.itemID = r and r.out and r.out[1] or nil -- (lo que fabrica: su tooltip en el icono)
    row.name:SetText(string.format("%s %s×%d|r", name, GREY, c.qty or 1))
    local res = Calc:Compute(c)
    row.profit:SetText(res and (Signed(-res.profit) .. (res.missing and (ORANGE .. " *|r") or "")) or "")
    row.sel:SetShown(selected and selected.id == c.id or false)
    row:Show()
  end
  for i = #list + 1, #page.saved do page.saved[i]:Hide() end
  page.listEmpty:SetShown(#list == 0)

  -- Hoja
  local res = selected and Calc:Compute(selected)
  local showSheet = res ~= nil
  for _, w in ipairs({ page.title, page.titleSub, page.qty, page.colHead, page.matTotal, page.saleLine, page.cutLine,
    page.profitLine, page.sellOnLine, page.note, page.reset, page.addShopping }) do w:SetShown(showSheet) end
  page.lastRes = res -- (el tooltip del beneficio)
  if not showSheet then
    for _, row in ipairs(page.sheetRows) do row:Hide() end
    for _, row in ipairs(page.madeRows or {}) do row:Hide() end
    return
  end

  local name = RecipeLabel(selected)
  page.title:SetText(name)
  page.titleSub:SetText(ES:ProfLabel(selected.prof)
    .. (ES:IsRecipeKnown(selected.recipe) and "" or (ORANGE .. " · " .. L["no la sabes"] .. "|r")))
  if page.qty:HasFocus() ~= true then page.qty:SetText(tostring(selected.qty or 1)) end

  local y = -78
  -- La hoja como un árbol (Calc:Compute, res.display): cada intermedio con su fila
  -- (cómo se consigue; clic para cambiarlo) y lo suyo debajo, un poco más adentro
  local rowOf = {}
  for _, r in ipairs(res.rows) do rowOf[r.itemID] = r end
  local nMade, nRows = 0, 0
  local function Place(row)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 6, y)
    row:SetPoint("TOPRIGHT", -6, y)
    y = y - ROW_H
  end
  for _, node in ipairs(res.display or {}) do
    local indent = INDENT * (node.depth or 0)
    if node.made then
      local m = node.made
      nMade = nMade + 1
      local row = MadeRow(page, nMade)
      row.m = m
      Place(row)
      row.icon:ClearAllPoints()
      row.icon:SetPoint("LEFT", 10 + indent, 0)
      local label, texture, pending = ES.UI.ItemLabel(m.itemID, L["Objeto "] .. m.itemID)
      if pending then page.pendingItems = true end
      row.icon:SetTexture(texture or 134400)
      row.name:SetText(Qty(m.qty) .. "× " .. label)
      local cheapest = (m.buyCost and (not m.craftCost or m.buyCost < m.craftCost)) and "buy" or "craft"
      row.source:SetText((m.mode == "craft" and L["lo fabricas"] or L["lo compras hecho"])
        .. (m.mode ~= cheapest and (ORANGE .. L[" · no es lo más barato"] .. "|r") or (GREY .. L[" · clic para cambiar"] .. "|r")))
      local cost = m.mode == "craft" and m.craftCost or m.buyCost
      row.total:SetText(cost and Money(cost) or (ORANGE .. "?|r"))
      row:Show()
    else
      local r = rowOf[node.item]
      if r then
        nRows = nRows + 1
        local row = SheetRow(page, nRows)
        Place(row)
        row.itemID = r.itemID
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", 10 + indent, 0)
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", COL_NAME + indent, 0)
        row.name:SetWidth(COL_QTY_RIGHT - 42 - COL_NAME - indent)
        local label, texture, pending = ES.UI.ItemLabel(r.itemID, L["Objeto "] .. r.itemID)
        if pending then page.pendingItems = true end
        row.icon:SetTexture(texture or 134400)
        -- (lo de dentro de un intermedio, más apagado: es parte de él)
        row.name:SetText(indent > 0 and (GREY .. (label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) .. "|r") or label)
        row.qty:SetText(Qty(r.qty))
        row.price:SetValue(r.price, SourceText(res, r.source))
        row.total:SetText(r.total and Money(r.total) or (ORANGE .. "?|r"))
        row:Show()
      end
    end
  end
  for i = nMade + 1, #(page.madeRows or {}) do page.madeRows[i]:Hide() end
  for i = nRows + 1, #page.sheetRows do page.sheetRows[i]:Hide() end

  local function Place(line, gap)
    y = y - (gap or 0)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", 6, y)
    line:SetPoint("TOPRIGHT", -6, y)
    y = y - LINE_H
  end
  Place(page.matTotal, 8)
  page.matTotal.label:SetText(L["Materiales"])
  page.matTotal.value:SetText(Signed(res.cost))

  Place(page.saleLine, 4)
  if res.outID then
    local outLabel = ES.UI.ItemLabel(res.outID, L["Objeto "] .. res.outID)
    page.saleLine.label:SetText(string.format(L["Venta: %s × %s"], Qty(res.outN), outLabel))
    page.saleBox:SetValue(res.sale, SourceText(res, res.saleSource))
    page.saleBox:Show()
    page.saleLine.value:SetText(Signed(-res.revenue))
  else
    page.saleLine.label:SetText(L["No fabrica un objeto que se pueda vender (encantamiento)."])
    page.saleBox:Hide()
    page.saleLine.value:SetText("")
  end

  -- Comisión: solo al vender en la AH (por el chat o al vendedor no hay)
  local ahCut = res.cut > 0
  page.cutLine:SetShown(ahCut)
  if ahCut then
    Place(page.cutLine)
    page.cutLine.label:SetText(string.format(L["Comisión de la AH (%d%%)"], math.floor(res.cutRate * 100 + 0.5)))
    page.cutLine.value:SetText(Signed(res.cut))
  end
  -- El beneficio, en grande (el depósito y lo que darían las otras formas de vender,
  -- en su tooltip)
  Place(page.profitLine, 8)
  page.profitLine.label:SetText(L["Beneficio"])
  page.profitLine.value:SetText(Signed(-res.profit))
  -- Dónde se vende (solo si se puede elegir: lo que se liga al recogerlo, no)
  page.sellOnLine:SetShown(res.canChoose)
  if res.canChoose then
    Place(page.sellOnLine)
    page.sellOn.text:SetText(page.SellOnLabel({ channel = res.channel, hours = res.hours }))
  end

  -- Notas cortas: si no, no caben bajo la hoja
  local notes = {}
  if res.missing then notes[#notes + 1] = ORANGE .. L["Algún material no tiene precio (ni en el escaneo ni en el vendedor): escríbelo para que cuente."] .. "|r" end
  if res.discount > 0 then
    notes[#notes + 1] = string.format(L["Precios de vendedor con el descuento de tu reputación con %s (-%d%%)."], res.city or "", math.floor(res.discount * 100 + 0.5))
  end
  -- Las notas van del beneficio hasta la fila de botones, nunca debajo de ellos: si
  -- no caben, se recortan (antes se metían por detrás de los botones)
  page.note:ClearAllPoints()
  page.note:SetPoint("TOPLEFT", 14, y - 6)
  page.note:SetPoint("BOTTOMRIGHT", -14, FOOTER_H)
  page.note:SetJustifyV("TOP")
  page.note:SetText(table.concat(notes, "\n"))
end
