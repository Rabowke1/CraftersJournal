"""¿Es la ruta del planificador la más barata? Carga el addon con la API simulada de
test_ui.py, calcula la ruta de cada escenario y busca rutas alternativas (varias
programaciones dinámicas independientes y una búsqueda local); todas se valoran con el
propio Planner:Plan forzado (mismo modelo de costes: materiales, reventa al vendedor,
instructor, herramientas, intermedios reutilizados, redondeo por paso).
Uso: python route_check.py --ah [--seed N] [--walks N] [--only Prof] [--ranges a-b,c-d]
  --ah     precios de AH sintéticos (sin ellos casi ninguna profesión tiene materiales de vendedor)
  --walks  recorridos de la búsqueda local por escenario (250 por defecto)
Necesita lupa (pip install lupa). PEOR = hay una ruta más de 1s más barata que la del planificador
(las que fabrican mucho más suelen ser el tope deliberado al beneficio de recetas casi grises).
"""
import random, re, sys, time
from pathlib import Path
from lupa import lua51

ROOT = Path(__file__).resolve().parent.parent
AH = "--ah" in sys.argv
WALKS = int(sys.argv[sys.argv.index("--walks") + 1]) if "--walks" in sys.argv else 250
ONLY = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
RANGES = [(1, 75), (1, 150), (75, 150), (150, 225), (225, 300), (1, 300)]
if "--ranges" in sys.argv:
    RANGES = [tuple(int(x) for x in r.split("-")) for r in sys.argv[sys.argv.index("--ranges") + 1].split(",")]
PROFS = ["Alchemy", "Blacksmithing", "Enchanting", "Engineering", "Leatherworking", "Tailoring", "Cooking", "FirstAid"]
if ONLY: PROFS = [ONLY]

src = (ROOT / "tools/test_ui.py").read_text(encoding="utf-8")
pre = re.search(r'lua\.execute\(r"""(.*?)"""\)', src, re.S).group(1)
lua = lua51.LuaRuntime(unpack_returned_tuples=True)
lua.execute(pre)
toc = (ROOT / "CraftersJournal.toc").read_text(encoding="utf-8")
files = [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")]
ES = lua.eval("{}")
loader = lua.eval("function(src, name, ES) assert(loadstring(src, '@' .. name))('CraftersJournal', ES) end")
for f in files:
    loader((ROOT / f.replace("\\", "/")).read_text(encoding="utf-8"), f, ES)
lua.globals().ES = ES
lua.execute(r"""
CraftersJournalDB = { scans = {} }
ES.db = CraftersJournalDB
ES.db.minimap = { angle = 225 }
local Planner = ES.Planner
function OPTS(prof, from, to, noAH)
  return { from = from, to = to, hours = 24, neutral = false, ignoreSupply = true, includeScrolls = false,
    reuseCrafted = true, sourcedScrolls = true, noAH = noAH or nil }
end
function PLAN(prof, from, to, noAH) return Planner:Plan(ES.Data[prof], OPTS(prof, from, to, noAH)) end
function WALK(prof, from, to, noAH, choice)
  local o = OPTS(prof, from, to, noAH)
  o.forced = choice
  return Planner:Plan(ES.Data[prof], o)
end
function CANDIDATES(prof, from, to, noAH)
  local data, opts = ES.Data[prof], OPTS(prof, from, to, noAH)
  local ctx = Planner.NewContext(data, opts)
  local out = {}
  for id, r in pairs(data.recipes) do
    if not r.conversion and id > 0 then
      local learn = Planner.LearnSkill(r, opts)
      if learn and learn < to and r.t[4] > from then
        local fee = Planner.LearnCost(ctx, r)
        local cost = Planner.RecipeCost(ctx, r, 1, {})
        local sale = Planner.SaleInfo(ctx, r)
        local toolCost, toolItem = 0, 0
        if r.tool and ES.Data.Tools[r.tool] then
          toolItem = ES.Data.Tools[r.tool].item
          toolCost = ES.Data.VendorPrices[toolItem] or Planner.CraftUnitCost(ctx, toolItem) or 0
        end
        out[#out + 1] = { id = id, name = r.name, learn = learn, fee = fee or 0, cost = cost or -1,
          value = sale and sale.qty * sale.vendor or 0, t2 = r.t[2], t4 = r.t[4], tool = toolItem, toolCost = toolCost }
      end
    end
  end
  return out
end
function ROUTE(p)
  local s = {}
  for _, st in ipairs(p.steps) do s[#s + 1] = string.format("%s %d-%d x%d", st.recipe.name, st.from, st.to, st.crafts) end
  return table.concat(s, " | ")
end
function CRAFTS(p) return Planner.TotalCrafts(p) end
function CHOICE(p) return p.choice end
-- AH sintética: cada material y producto, a 1,5-5,5 veces su precio de vendedor, en tres escalones
function SYNTH_AH(seed)
  math.randomseed(seed)
  local items = {}
  for _, data in pairs(ES.Data) do
    if type(data) == "table" and data.recipes then
      for _, r in pairs(data.recipes) do
        for _, rq in ipairs(r.r) do items[rq[1]] = true end
        if r.out then items[r.out[1]] = true end
      end
    end
  end
  local scan = { time = time(), total = 0, unique = 0, items = {} }
  for id in pairs(items) do
    local sell = ES.Data.SellPrices[id] or 100
    local base = math.max(1, math.floor(sell * (1.5 + math.random() * 4) + 0.5))
    scan.items[id] = { listings = 30, quantity = 270, minUnit = base, median = math.floor(base * 1.1 + 0.5),
      ladder = { base, 20, math.floor(base * 1.1 + 0.5), 50, math.floor(base * 1.25 + 0.5), 200 } }
    scan.total, scan.unique = scan.total + 30, scan.unique + 1
  end
  ES.db.scans[ES:RealmKey()] = scan
end
""")
SEED = int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else 7
if AH:
    lua.globals().SYNTH_AH(SEED)
noAH = not AH

def chance(c, s):
    if s < c["t2"]: return 1.0
    if s >= c["t4"]: return 0.0
    return (c["t4"] - s) / (c["t4"] - c["t2"])

def point_cost(c, s):
    return (c["cost"] - c["value"]) / chance(c, s)

def usable(c, s):
    return c["cost"] >= 0 and c["learn"] <= s and chance(c, s) > 0

def dp_switch(cands, frm, to, fee_factor=1.0, per_point_fee=None):
    """Ruta más barata pagando el instructor (y la herramienta) cada vez que se empieza una
    receta (fee_factor) o repartido por punto (per_point_fee); sin estado de lo ya aprendido."""
    INF = float("inf")
    prev = {c["id"]: INF for c in cands}
    back = []
    best_prev, best_prev_id = 0.0, None
    for s in range(frm, to):
        cur, b = {}, {}
        for c in cands:
            cid = c["id"]
            if not usable(c, s):
                cur[cid] = INF; continue
            pc = point_cost(c, s)
            once = (c["fee"] + c["toolCost"])
            if per_point_fee is not None:
                v, b[cid] = best_prev + pc + once / per_point_fee, best_prev_id
            else:
                stay = prev[cid] + pc
                switch = best_prev + once * fee_factor + pc
                if stay <= switch: v, b[cid] = stay, cid
                else: v, b[cid] = switch, best_prev_id
            cur[cid] = v
        back.append(b)
        ok = [(v, k) for k, v in cur.items() if v < INF]
        if not ok: break
        best_prev, best_prev_id = min(ok)
        prev = cur
    choice = {}
    i = best_prev_id
    for idx in range(len(back) - 1, -1, -1):
        s = frm + idx
        if i is None: break
        choice[s] = i
        i = back[idx].get(i)
    return choice

def dp_exact(cands, frm, to, max_bits=12):
    """Óptimo exacto del modelo fraccionario pagando cada instructor/herramienta una vez
    (estado: nivel + conjunto de lo ya pagado); solo si hay pocas cosas que pagar."""
    once = sorted({("f", c["id"]) for c in cands if c["fee"] > 0} | {("t", c["tool"]) for c in cands if c["toolCost"] > 0})
    if len(once) > max_bits: return None
    bit = {k: 1 << i for i, k in enumerate(once)}
    INF = float("inf")
    states = {0: (0.0, None)}  # mask -> (cost, backpointer)
    hist = []
    for s in range(frm, to):
        nxt = {}
        for mask, (cost, _) in states.items():
            for c in cands:
                if not usable(c, s): continue
                add, m = point_cost(c, s), mask
                fb = bit.get(("f", c["id"]))
                if fb and not m & fb: add += c["fee"]; m |= fb
                tb = bit.get(("t", c["tool"]))
                if tb and not m & tb: add += c["toolCost"]; m |= tb
                v = cost + add
                if v < nxt.get(m, (INF,))[0]: nxt[m] = (v, (mask, c["id"]))
        if not nxt: break
        hist.append(nxt); states = nxt
    if not hist: return None
    mask = min(states, key=lambda m: states[m][0])
    choice = {}
    for idx in range(len(hist) - 1, -1, -1):
        cost, bp = hist[idx][mask]
        choice[frm + idx] = bp[1]
        mask = bp[0]
    return choice

def walk(prof, frm, to, choice):
    t = lua.table_from({int(k): int(v) for k, v in choice.items()})
    p = lua.globals().WALK(prof, frm, to, noAH, t)
    return p

def info(p):
    return dict(net=p.net, reached=p.reached, crafts=lua.globals().CRAFTS(p), steps=len(list(p.steps)), route=lua.globals().ROUTE(p))

def local_search(prof, frm, to, cands, start_choice, base, walks, rnd):
    best_choice, best = dict(start_choice), base
    tried = 0
    ids_by_level = {s: [c for c in cands if usable(c, s)] for s in range(frm, to)}
    while tried < walks:
        a = rnd.randrange(frm, to)
        b = min(to, a + rnd.choice([1, 2, 3, 5, 8, 13, 20, 30]))
        pool = [c for c in ids_by_level[a] if all(usable(c, s) for s in range(a, b))]
        if not pool: continue
        c = rnd.choice(pool)
        cand = dict(best_choice)
        for s in range(a, b): cand[s] = c["id"]
        if cand == best_choice: continue
        tried += 1
        p = walk(prof, frm, to, cand)
        if p.reached >= best["reached"] and p.net < best["net"] - 0.5:
            best_choice, best = cand, info(p)
    return best, best_choice

rnd = random.Random(1)
print(f"Modo: {'AH sintética (semilla ' + str(SEED) + ')' if AH else 'solo vendedor (sin AH)'} · {WALKS} recorridos de búsqueda local por escenario", flush=True)
worse = []
for prof in PROFS:
    for frm, to in RANGES:
        t0 = time.time()
        p0 = lua.globals().PLAN(prof, frm, to, noAH)
        base = info(p0)
        t_plan = time.time() - t0
        if base["steps"] == 0:
            print(f"{prof} {frm}-{to}: sin ruta ({base['route']})"); continue
        cands = [dict(c) for c in lua.globals().CANDIDATES(prof, frm, to, noAH).values()]
        cands = [{k: (v if k == "name" else v) for k, v in c.items()} for c in cands]
        alts = {}
        for name, ch in [("dp fee/switch", dp_switch(cands, frm, to)), ("dp fee x0.5", dp_switch(cands, frm, to, 0.5)),
                         ("dp fee/10pts", dp_switch(cands, frm, to, per_point_fee=10)), ("dp fee/30pts", dp_switch(cands, frm, to, per_point_fee=30)),
                         ("dp sin fee", dp_switch(cands, frm, to, 0.0))]:
            if ch: alts[name] = ch
        ex = dp_exact(cands, frm, to)
        if ex: alts["dp exacto"] = ex
        results = {}
        for name, ch in alts.items():
            p = walk(prof, frm, to, ch)
            results[name] = info(p)
        planner_choice = {int(k): int(v) for k, v in dict(lua.globals().CHOICE(p0)).items()}
        ls, ls_choice = local_search(prof, frm, to, cands, planner_choice, base, WALKS, rnd)
        results["búsqueda local"] = ls
        ok = {k: v for k, v in results.items() if v["reached"] >= base["reached"]}
        best_name, best = min(ok.items(), key=lambda kv: kv[1]["net"]) if ok else (None, base)
        gap = base["net"] - best["net"]
        flag = "PEOR" if gap > 100 else ("~" if gap > 0.5 else "OK")
        exact_note = f" · exacto {results['dp exacto']['net'] / 10000:.2f}g" if "dp exacto" in results else ""
        print(f"{flag:4s} {prof:14s} {frm:3d}-{to:3d}: planificador {base['net'] / 10000:8.2f}g ({base['crafts']} fabr., {base['steps']} pasos, {t_plan:4.1f}s)"
              f" · mejor alternativa {best['net'] / 10000:8.2f}g [{best_name}] ({best['crafts']} fabr.){exact_note}", flush=True)
        if gap > 0.5:
            print(f"       planificador: {base['route']}")
            print(f"       alternativa : {best['route']}")
            worse.append((prof, frm, to, gap))
print(f"\nEscenarios con una alternativa más barata que la del planificador: {len(worse)}")
for w in worse: print(f"  {w[0]} {w[1]}-{w[2]}: {w[3] / 10000:.2f}g más barata")
