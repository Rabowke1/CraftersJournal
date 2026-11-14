local _, ES = ...
local L = ES.L

-- Al abrir la ventana de una profesión sale al lado una ventana (como las del vendedor
-- y la AH) con lo que la pestaña Ganar dinero propone fabricar de ESA profesión: las
-- líneas del lote de hoy y las de venta segura al vendedor, con las mismas cantidades
-- y beneficios (Earn:Ideas, una sola fuente). Clic en una fila: fabrica las que tocan
-- (ES:CraftRecipe, como en la pestaña y en los pasos de la ruta). Sin nada que
-- fabricar, no sale. Se quita en las opciones (ES.db.noCraftWindow, Options.lua) o
-- con su ✕ hasta la próxima vez que abras la profesión.

local Craft = {}
ES.CraftWindow = Craft

local ROW_H, MAX_ROWS = 34, 10
local WIDTH = 300
-- Separación del borde derecho de la ventana de la profesión: por ahí asoman sus
-- pestañas laterales (una por profesión) y, pegada, la ventana las tapaba
local SIDE_TABS_GAP = 44
local COST_W = 74
local GREEN, GREY = "|cff40ff40", "|cff999999"

local panel

local function ProfFrame()
  if ProfessionsFrame and ProfessionsFrame:IsShown() then return ProfessionsFrame end
  if TradeSkillFrame and TradeSkillFrame:IsShown() then return TradeSkillFrame end
  return nil
end

-- Qué profesión está abierta (su clave en ES.Data) o nil. Primero lo que dice el
-- juego (C_TradeSkillUI); si no, cuál de nuestras profesiones tiene más recetas en la
-- ventana (vale con cualquier versión de la API)
function Craft.OpenProfession()
  local T = C_TradeSkillUI
  if T and T.GetBaseProfessionInfo then
    local ok, info = pcall(T.GetBaseProfessionInfo)
    local line = ok and type(info) == "table" and (info.professionID or info.skillLineID)
    if line then
      for _, p in ipairs(ES.PROFESSIONS) do
        if ES.Data[p.key] and ES.Data[p.key].skillLine == line then return p.key end
      end
    end
  end
  if T and T.GetAllRecipeIDs then
    local ok, ids = pcall(T.GetAllRecipeIDs)
    if ok and type(ids) == "table" then
      local best, bestN
      for _, p in ipairs(ES.PROFESSIONS) do
        local recipes = ES.Data[p.key] and ES.Data[p.key].recipes or {}
        local n = 0
        for _, id in ipairs(ids) do if recipes[id] then n = n + 1 end end
        if n > 0 and (not bestN or n > bestN) then best, bestN = p.key, n end
      end
      return best
    end
  end
  return nil
end

-- Las líneas de Ganar dinero de esa profesión que hay que fabricar: { idea }
function Craft:List(profKey)
  local list = {}
  if not (profKey and ES.Earn) then return list end
  local ok, res = pcall(ES.Earn.Ideas, ES.Earn)
  if not ok or not res then return list end
  for _, idea in ipairs(res.batch or {}) do
    if idea.profKey == profKey and (idea.crafts or 0) > 0 then list[#list + 1] = idea end
  end
  for _, idea in ipairs(res.vendor or {}) do
    if idea.profKey == profKey and (idea.crafts or 0) > 0 then list[#list + 1] = idea end
  end
  return list
end

local function RowClick(self, button)
  local idea = self.idea
  if not idea then return end
  if button == "RightButton" then
    -- (como en la pestaña: las de venta al vendedor añaden sus materiales a la lista)
    if idea.shopping then
      local name = ES.UI.ItemLabel(idea.e.itemID, idea.e.recipe.name)
      local day = date and date("%d/%m") or ""
      ES:AddToShopping("money", string.format(L["Ganar dinero: %d× %s"], idea.crafts, name or idea.e.recipe.name), idea.shopping,
        { key = idea.e.id .. ":" .. day, minusBags = true })
    end
    return
  end
  ES:CraftRecipe(idea.e.id, idea.crafts)
end

local function RowEnter(self)
  if not self.idea then return end
  if ES.UI.EarnTooltip then ES.UI.EarnTooltip(self.idea)(self) end
end

local function CreatePanel(parent)
  local f = CreateFrame("Frame", "CraftersJournalCraftPanel", parent or UIParent, "BackdropTemplate")
  f:SetWidth(WIDTH)
  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  local G = ES.UI.BROWN.group
  f:SetBackdropColor(G[1], G[2], G[3], 0.99)
  f:SetBackdropBorderColor(0.52, 0.38, 0.17, 1)
  if f.SetClampedToScreen then f:SetClampedToScreen(true) end
  f:EnableMouse(true)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 12, -10)
  f.title:SetText("Crafter's Journal")
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)
  close:SetScript("OnClick", function()
    Craft.closed = true -- (hasta la próxima vez que abras la profesión)
    f:Hide()
  end)
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
  f.sub:SetWidth(WIDTH - 24)
  f.sub:SetJustifyH("LEFT")
  f.rows = {}
  for i = 1, MAX_ROWS do
    local row = CreateFrame("Button", nil, f)
    row:SetSize(WIDTH - 16, ROW_H)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 0.82, 0.25, 0.1)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(26, 26)
    row.icon:SetPoint("LEFT", 2, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
    row.name:SetPoint("RIGHT", row, "RIGHT", -COST_W, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.cost:SetPoint("TOP", row.name, "TOP", 0, 0)
    row.cost:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.cost:SetJustifyH("RIGHT")
    row.qty = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.qty:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
    row.qty:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.qty:SetJustifyH("LEFT")
    row.qty:SetWordWrap(false)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", RowClick)
    row:SetScript("OnEnter", RowEnter)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.rows[i] = row
  end
  f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.hint:SetJustifyH("LEFT")
  f:Hide()
  return f
end

-- Cuánto separarla: lo que asoman por la derecha las pestañas u otros marcos pegados a
-- la ventana de la profesión (medido; como mínimo SIDE_TABS_GAP)
function Craft.SideTabsGap(frame)
  local gap = SIDE_TABS_GAP
  local right = frame.GetRight and frame:GetRight()
  if not right or not frame.GetChildren then return gap end
  for _, child in ipairs({ frame:GetChildren() }) do
    if child ~= panel and child.IsShown and child:IsShown() and child.GetRight then
      local r = child:GetRight()
      if type(r) == "number" and r > right and r - right < 120 then gap = math.max(gap, math.ceil(r - right) + 6) end
    end
  end
  return gap
end

function Craft:Refresh()
  local frame = ProfFrame()
  local profKey = frame and Craft.OpenProfession()
  if not frame or not profKey or self.closed or not ES:CraftWindowOn() then
    if panel then panel:Hide() end
    return
  end
  local list = self:List(profKey)
  if #list == 0 then
    if panel then panel:Hide() end
    return
  end
  panel = panel or CreatePanel(frame)
  panel:ClearAllPoints()
  panel:SetPoint("TOPLEFT", frame, "TOPRIGHT", Craft.SideTabsGap(frame), -12)
  if panel.SetFrameStrata and frame.GetFrameStrata then panel:SetFrameStrata(frame:GetFrameStrata()) end
  panel.sub:SetText(string.format(L["Ganar dinero · %s: lo que da beneficio fabricar"], ES:ProfLabel(profKey)))
  local function H(fs) return math.min(tonumber(fs:GetStringHeight()) or 12, 40) end
  local y = -(10 + H(panel.title) + 3 + H(panel.sub) + 8)
  local shown = math.min(#list, MAX_ROWS)
  for i = 1, shown do
    local row, idea = panel.rows[i], list[i]
    row.idea = idea
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 8, y)
    y = y - ROW_H
    local e = idea.e
    local name, texture = ES.UI.ItemLabel(e.itemID, e.recipe.name)
    row.icon:SetTexture(texture or 134400)
    row.name:SetText(string.format("%d× %s", idea.crafts, name or e.recipe.name))
    row.qty:SetText(idea.sellWhere == "ah" and string.format(L["vender en la AH · invierte %s"], ES.Money(idea.invest or 0))
      or string.format(L["vender al vendedor · invierte %s"], ES.Money(idea.invest or 0)))
    row.cost:SetText(GREEN .. "+" .. ES.Money(idea.profit or 0) .. "|r")
    row:Show()
  end
  for k = shown + 1, MAX_ROWS do
    panel.rows[k].idea = nil
    panel.rows[k]:Hide()
  end
  panel.hint:ClearAllPoints()
  panel.hint:SetPoint("TOPLEFT", 12, y - 4)
  panel.hint:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
  panel.hint:SetText(L["Clic: fabricar las de la fila (como mucho, las que dan tus materiales)."]
    .. (#list > shown and ("\n" .. GREY .. string.format(L["(%d más en la pestaña Ganar dinero)"], #list - shown) .. "|r") or ""))
  y = y - 4 - math.max(14, math.min(tonumber(panel.hint:GetStringHeight()) or 0, 40))
  panel:SetHeight(-y + 10)
  panel:Show()
end

do
  local f = CreateFrame("Frame")
  for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "BAG_UPDATE_DELAYED" }) do
    ES.SafeRegister(f, e)
  end
  local queued = false
  f:SetScript("OnEvent", function(_, event)
    if not ES.db then return end
    if event == "TRADE_SKILL_CLOSE" then
      Craft.closed = nil
      if panel then panel:Hide() end
      return
    end
    if event == "TRADE_SKILL_SHOW" then Craft.closed = nil end
    -- (agrupado: al abrirla el juego aún está cargando sus recetas)
    if not queued then
      queued = true
      C_Timer.After(0.3, function()
        queued = false
        Craft:Refresh()
      end)
    end
  end)
end
