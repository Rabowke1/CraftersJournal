"""Ganar dinero: cantidad elegida por ti en el lote (botones − y + de la fila).

Con tus datos guardados reales (harness.py): Sastrería y Peletería al 150 con las
recetas de instructor. Comprueba que la cantidad se aplica y recalcula, que al volver
a la recomendada deja de ser tuya, que con 1 no se sale del lote, que la fila enseña
los botones y que un escaneo nuevo la olvida.
Uso:  python pilot_earn_qty.py
"""
exec(open(__file__.replace("pilot_earn_qty.py", "harness.py"), encoding="utf-8").read())
print(run(r"""
local out = {}
local function g(c) return string.format("%.2fg", (c or 0) / 10000) end
ES.GetProfessionSkill = function(_, line)
  if line == ES.Data.Leatherworking.skillLine or line == ES.Data.Tailoring.skillLine then return 150, 225 end
end
ES.IsRecipeKnown = function(_, id)
  local r = ES.Data.Leatherworking.recipes[id] or ES.Data.Tailoring.recipes[id]
  return r ~= nil and (r.fee ~= nil or r.basic) and (r.train or 1) <= 150
end
ES.db.earnMinProfit, ES.db.earnQty = 0, nil
local function Ideas() ES.Earn:Clear() return ES.Earn:Ideas() end
local function Find(res, name) for _, i in ipairs(res.batch) do if i.e.recipe.name == name then return i end end end
local res = Ideas()
local first = res.batch[1]
assert(first, "sin lote con tus datos: escanea la AH")
local name, n0, cost0 = first.e.recipe.name, first.crafts, first.invest
out[#out+1] = string.format("%s: %d recomendadas, invierte %s", name, n0, g(cost0))
ES.Earn.StepQuantity(first, 5)
local more = Find(Ideas(), name)
assert(more and more.custom and more.crafts == n0 + 5 and more.recommended == n0, "+5 no aplicó la cantidad")
assert(more.invest > cost0, "con más fabricaciones no sube lo que inviertes")
out[#out+1] = string.format("   +5: %d, invierte %s", more.crafts, g(more.invest))
-- La fila: botones y aviso naranja; pulsar − baja una
ES:GetMainFrame()
ES:SelectPage("money")
local page = ES.earnPage
ES:RenderEarn()
local row
for _, r in ipairs(page.rows) do if r.stepper and r.stepper._shown ~= false and r.onStep then row = r break end end
assert(row, "la fila del lote no tiene los botones")
local sub = tostring(row.sub._text)
assert(sub:find("recomendado") or sub:find("recommended"), "la fila no avisa de que pasa de lo recomendado")
row.stepper.minus._scripts.OnClick(row.stepper.minus)
assert(Find(ES.Earn:Ideas(), name).crafts == n0 + 4, "el botón − no bajó una")
out[#out+1] = "   la fila: botones, aviso naranja y − baja una"
-- Clic en la fila: abre la receta y fabrica las de la fila (como los pasos de la ruta)
ES:RenderEarn()
local crafted
local savedCraft = ES.CraftRecipe
ES.CraftRecipe = function(_, id, n) crafted = { id, n } end
for _, r in ipairs(page.rows) do
  if r.onStep and r.onClick then r._scripts.OnClick(r, "LeftButton") break end
end
ES.CraftRecipe = savedCraft
local now = Find(ES.Earn:Ideas(), name)
assert(crafted and crafted[1] == now.e.id and crafted[2] == now.crafts, "el clic no fabrica la receta de la fila")
out[#out+1] = string.format("   clic: fabrica %d de la receta %d", crafted[2], crafted[1])
-- Ventana junto a la profesión: al abrir Sastrería, sus líneas de Ganar dinero; clic = fabricar
do
  local savedPF, savedT, savedCraft = ProfessionsFrame, C_TradeSkillUI, ES.CraftRecipe
  ProfessionsFrame = CreateFrame("Frame")
  ProfessionsFrame.IsShown = function() return true end
  C_TradeSkillUI = { GetBaseProfessionInfo = function() return { professionID = ES.Data.Tailoring.skillLine } end }
  assert(ES.CraftWindow.OpenProfession() == "Tailoring", "no detecta la profesión abierta")
  ES.CraftWindow.closed = nil
  ES.CraftWindow:Refresh()
  local cp = CraftersJournalCraftPanel
  assert(cp and cp._shown ~= false, "al abrir Sastrería no sale la ventana de Ganar dinero")
  local r1 = cp.rows[1]
  assert(r1.idea and r1.idea.profKey == "Tailoring", "la ventana enseña líneas de otra profesión")
  local crafted
  ES.CraftRecipe = function(_, id, n) crafted = { id, n } end
  r1._scripts.OnClick(r1, "LeftButton")
  assert(crafted and crafted[1] == r1.idea.e.id and crafted[2] == r1.idea.crafts, "el clic en la ventana no fabrica")
  out[#out+1] = string.format("   ventana de la profesión: %s (clic fabrica %d)", tostring(r1.name._text), crafted[2])
  -- Otra profesión sin nada que fabricar (Cocina, que no tienes): no sale
  C_TradeSkillUI = { GetBaseProfessionInfo = function() return { professionID = ES.Data.Cooking.skillLine } end }
  ES.CraftWindow:Refresh()
  assert(cp._shown == false, "sin nada que fabricar de esa profesión, la ventana sale")
  -- La opción la quita
  C_TradeSkillUI = { GetBaseProfessionInfo = function() return { professionID = ES.Data.Tailoring.skillLine } end }
  ES:SetOption("noCraftWindow", false)
  assert(cp._shown == false, "con la opción desactivada, la ventana sale")
  ES:SetOption("noCraftWindow", true)
  assert(cp._shown ~= false, "activada otra vez, la ventana no vuelve")
  ProfessionsFrame, C_TradeSkillUI, ES.CraftRecipe = savedPF, savedT, savedCraft
  cp:Hide()
end
-- Aprender una receta de "Recetas que puedes aprender" la saca de ahí al momento
-- (antes la caché de Ganar dinero seguía hasta el siguiente escaneo)
do
  local before = ES.Earn:Ideas()
  local learn = before.learnable[1]
  if learn then
    local baseKnown, learnedID = ES.IsRecipeKnown, learn.e.id
    ES.IsRecipeKnown = function(self, id) return id == learnedID or baseKnown(self, id) end
    ES:RefreshAfterLearn()
    local after = ES.Earn:Ideas()
    for _, i in ipairs(after.learnable) do assert(i.e.id ~= learnedID, "aprendida, sigue en Recetas que puedes aprender") end
    out[#out+1] = string.format("   aprender %s la saca de Recetas que puedes aprender: OK", learn.e.recipe.name)
    ES.IsRecipeKnown = baseKnown
    ES.Earn:Clear()
  end
end
-- Volver a la recomendada: deja de ser tuya
ES.Earn.StepQuantity(Find(ES.Earn:Ideas(), name), -4)
local back = Find(Ideas(), name)
assert(back and not back.custom and back.crafts == n0, "al volver a la recomendada sigue marcada como tuya")
-- Bajar hasta 1 no la saca del lote
ES.Earn.StepQuantity(back, -100)
local one = Find(Ideas(), name)
assert(one and one.custom and one.crafts == 1, "con 1 fabricación se salió del lote")
-- Un escaneo nuevo la olvida
local key = ES:RealmKey()
ES.db.scans[key].time = ES.db.scans[key].time + 60
local fresh = Find(Ideas(), name)
assert(fresh and not fresh.custom, "la cantidad elegida sobrevivió a un escaneo nuevo")
out[#out+1] = "   vuelve a la recomendada, con 1 sigue en el lote y un escaneo nuevo la olvida: OK"
return table.concat(out, "\n")
"""))
