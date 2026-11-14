local _, ES = ...
local L = ES.L

---------------------------------------------------------------------------
-- Opciones del addon, en las opciones del juego (Opciones > AddOns > Crafter's
-- Journal) y con /cj opciones: si salen solas las ventanas junto al vendedor y junto
-- a la Casa de Subastas, y si se propone vender tu equipo (ligado o en un conjunto).
--   ES.db.protectGear      = true: tu equipo (ligado o en un conjunto) no se propone
--                            vender (InventoryUI.lua). Por defecto no: se propone todo
--   ES.db.noChatAlerts     = true: sin los avisos del chat tras un escaneo (recetas
--                            de botín en la AH, ruta que cuesta más con precios nuevos)
--   ES.db.minimap.hide     = true: sin botón del minimapa (LibDBIcon)
--   ES.db.noVendorWindow   = true: no sale la ventana junto al vendedor
--   ES.db.noAuctionWindows = true: no salen solas las de junto a la AH (lista de
--                            compra y vender en la AH); el botón de la AH sigue
--                            abriendo la lista de compra a mano
---------------------------------------------------------------------------

function ES:VendorWindowOn() return not (self.db and self.db.noVendorWindow) end
function ES:AuctionWindowsOn() return not (self.db and self.db.noAuctionWindows) end

-- Cambia una opción (on: la casilla marcada) y lo aplica al momento: la pestaña
-- Inventario y las ventanas del vendedor y la AH, si están abiertos
function ES:SetOption(key, on)
  self.db[key] = (not on) or nil
  self:ApplyOptions(key, on)
end

function ES:ApplyOptions(key, on)
  if self.RenderInventory then self:RenderInventory() end
  if self.VendorShop and self.VendorShop.Refresh then self.VendorShop:Refresh() end
  if self.AuctionSell and self.AuctionSell.Refresh then self.AuctionSell:Refresh() end
  -- (la lista de compra: desactivada se quita; activada sale la próxima vez que
  -- abras la AH, o ya con el botón de encima de la AH)
  local mini = self.ShoppingMini and self.ShoppingMini()
  if key == "noAuctionWindows" and not on and mini then mini:Hide() end
end

local OPTIONS = {
  { key = "noVendorWindow", label = "Ventana junto al vendedor",
    desc = "Al abrir un vendedor: lo que te falta de la lista de compra y lo que puedes venderle, con los botones Comprar todo y Vender todo." },
  { key = "noAuctionWindows", label = "Ventanas junto a la Casa de Subastas",
    desc = "Al abrir la AH: tu lista de compra y lo que puedes vender en la AH. Desactivadas, la lista de compra se sigue pudiendo abrir con el botón de encima de la AH." },
  -- (por defecto desactivada: se propone todo y lo tuyo lo apartas con clic derecho)
  { key = "protectGear", label = "No vender tu equipo",
    desc = "Activado, el equipo ligado a ti (tu otro equipo, lo de las misiones) y el de los conjuntos del gestor de equipo no se propone vender (ni Vender todo lo vende); los verdes sin ligar de botín, lo que fabricas y lo gris, sí. Desactivado, se propone todo: lo que quieras guardar, clic derecho y no se vende nunca.",
    get = function() return ES.db.protectGear == true end,
    set = function(on) ES.db.protectGear = on or nil ES:ApplyOptions("protectGear", on) end },
  { key = "noChatAlerts", label = "Avisos en el chat",
    desc = "Tras un escaneo: recetas de botín que te faltan y están en la AH, y si tu ruta empezada cuesta bastante más con los precios nuevos. Desactivados, la ruta lo sigue diciendo en su línea de estado." },
  -- (se guarda en ES.db.minimap.hide, el sitio de LibDBIcon: también /cj minimap)
  { key = "minimap", label = "Botón del minimapa", desc = "El botón de Crafter's Journal junto al minimapa. También con /cj minimap.",
    get = function() return not (ES.db.minimap and ES.db.minimap.hide) end,
    set = function(on) ES:SetMinimapShown(on) end },
}

local panel
local function CreatePanel()
  local p = CreateFrame("Frame", "CraftersJournalOptionsPanel", UIParent)
  p.name = "Crafter's Journal"
  p:Hide()
  p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  p.title:SetPoint("TOPLEFT", 16, -16)
  p.title:SetText("Crafter's Journal")
  p.checks = {}
  local y = -56
  for i, o in ipairs(OPTIONS) do
    local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", 16, y)
    cb.label = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    cb.desc = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cb.desc:SetPoint("TOPLEFT", cb.label, "BOTTOMLEFT", 0, -4)
    cb.desc:SetWidth(520)
    cb.desc:SetJustifyH("LEFT")
    cb.option = o
    cb:SetScript("OnClick", function(self)
      local on = self:GetChecked() and true or false
      if o.set then o.set(on) else ES:SetOption(o.key, on) end
    end)
    p.checks[i] = cb
    y = y - 70
  end
  -- Textos y casillas al mostrarse: el idioma o las opciones pueden haber cambiado
  p:SetScript("OnShow", function(self)
    self.sub = self.sub or self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -6)
    self.sub:SetText(L["Ventanas, qué se propone vender, avisos y botón del minimapa."])
    for _, cb in ipairs(self.checks) do
      cb.label:SetText(L[cb.option.label])
      cb.desc:SetText(L[cb.option.desc])
      local o = cb.option
      if o.get then cb:SetChecked(o.get()) else cb:SetChecked(not ES.db[o.key]) end
    end
  end)
  -- Opciones del juego: la API nueva (Settings) o la de antes
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(p, p.name)
    Settings.RegisterAddOnCategory(category)
    ES.optionsCategory = category
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(p)
  end
  return p
end

function ES:OptionsPanel()
  panel = panel or CreatePanel()
  return panel
end

function ES:OpenOptions()
  local p = self:OptionsPanel()
  if Settings and Settings.OpenToCategory and self.optionsCategory then
    local id = self.optionsCategory.GetID and self.optionsCategory:GetID() or self.optionsCategory.ID
    Settings.OpenToCategory(id)
  elseif InterfaceOptionsFrame_OpenToCategory then
    -- (la primera vez a veces abre la página general: se repite)
    InterfaceOptionsFrame_OpenToCategory(p)
    InterfaceOptionsFrame_OpenToCategory(p)
  else
    p:Show()
  end
end

-- Se registra al entrar (con ES.db ya cargada), para que salga en las opciones del juego
do
  local f = CreateFrame("Frame")
  ES.SafeRegister(f, "PLAYER_LOGIN")
  f:SetScript("OnEvent", function() if ES.db then ES:OptionsPanel() end end)
end
