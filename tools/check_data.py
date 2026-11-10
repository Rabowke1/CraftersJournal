"""Comprueba Data/<Profesion>.lua contra las tablas del cliente de WoW Forever (tools/wago,
de wago.tools): nombre de cada receta, materiales, lo que fabrica, umbrales, pergamino
(y su reputación, calidad y precio), nombres de objetos y precios de compra y venta.
Las excepciones conocidas (tools/forever/sell_prices.csv y trainer_fees.csv: lo visto en
el juego) se comprueban contra su CSV, no contra el cliente.

Uso: python check_data.py [-v]   (-v: cada discrepancia; si no, el resumen por tipo)
"""
import csv
import re
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
WAGO = HERE / "wago"
PROFS = ["Leatherworking", "Enchanting", "Tailoring", "Blacksmithing", "Alchemy", "Engineering", "Cooking", "FirstAid"]
SKILL = {"Leatherworking": 165, "Enchanting": 333, "Tailoring": 197, "Blacksmithing": 164, "Alchemy": 171,
         "Engineering": 202, "Cooking": 185, "FirstAid": 129}


def rows(name):
    with open(WAGO / f"{name}.csv", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def client_tables():
    c = {}
    c["names"] = {int(r["ID"]): r["Name_lang"] for r in rows("SpellName_forever")}
    c["reagents"] = {}
    for r in rows("SpellReagents_forever"):
        c["reagents"][int(r["SpellID"])] = sorted(
            (int(r[f"Reagent_{k}"]), int(r[f"ReagentCount_{k}"])) for k in range(8)
            if int(r[f"Reagent_{k}"] or 0) and int(r[f"ReagentCount_{k}"] or 0))
    c["creates"] = {}
    for r in rows("SpellEffect_forever"):
        if r["Effect"] == "24" and r["EffectItemType"] not in ("", "0"):
            q = float(r["EffectBasePointsF"] or 1)
            c["creates"][int(r["SpellID"])] = (int(r["EffectItemType"]), q if q > 0 else 1.0)
    c["sla"] = {(int(r["SkillLine"]), int(r["Spell"])): (int(r["MinSkillLineRank"]), int(r["TrivialSkillLineRankLow"]),
                                                          int(r["TrivialSkillLineRankHigh"]))
                for r in rows("SkillLineAbility_forever")}
    c["items"] = {}
    for r in rows("ItemSparse_forever"):
        stack = max(1, int(r["VendorStackCount"] or 1))
        c["items"][int(r["ID"])] = dict(
            name=r["Display_lang"], buy=int(r["BuyPrice"] or 0) / stack, sell=int(r["SellPrice"] or 0),
            rep=(int(r["MinFactionID"] or 0), int(r["MinReputation"] or 0)),
            quality=int(r.get("OverallQualityID") or 1), bop=r.get("Bonding") == "1")
    # Herramientas que pide cada receta (SpellTotems): categorías de tótem de las
    # herramientas conocidas u objetos concretos (Flint and Tinder), en el orden del cliente
    c["tools"] = {}
    for r in rows("SpellTotems_forever"):
        lst = c["tools"].setdefault(int(r["SpellID"]), [])
        for slot in ("RequiredTotemCategoryID_0", "RequiredTotemCategoryID_1"):
            cat = int(r[slot] or 0)
            if cat in TOOL_CATEGORIES and cat not in lst:
                lst.append(cat)
        for slot in ("Totem_0", "Totem_1"):
            item = int(r[slot] or 0)
            if item in TOOL_OBJECTS and item not in lst:
                lst.append(item)
    c["tools"] = {k: v for k, v in c["tools"].items() if v}
    c["scrolls"] = {}
    for r in rows("RecipeScrolls_forever"):
        c["scrolls"].setdefault(int(r["Spell"]), set()).add(int(r["ItemID"]))
    c["sell_override"] = {}
    with open(HERE / "forever" / "sell_prices.csv", encoding="utf-8") as f:
        for r in csv.DictReader(line for line in f if not line.startswith("#")):
            c["sell_override"][int(r["item"])] = int(r["sell"])
    return c


# Herramientas que conocen los datos (tools/gen_profession.py: TOOL_ITEMS y TOTEM_ITEMS)
TOOL_CATEGORIES = {373, 374, 375, 376, 377, 162, 12, 14, 15}
TOOL_OBJECTS = {4471}

RECIPE = re.compile(r'^\s*\[(-?\d+)\] = \{ (.*) \},', re.M)


def lua_recipes(text):
    """[hechizo] -> campos de la receta tal como están en Data/<Profesion>.lua."""
    out = {}
    for m in RECIPE.finditer(text):
        sid, body = int(m.group(1)), m.group(2)
        d = {}
        nm = re.search(r'name = "((?:[^"\\]|\\.)*)"', body)
        d["name"] = nm.group(1).replace('\\"', '"') if nm else None
        t = re.search(r't = \{ (\d+), (\d+), (\d+), (\d+) \}', body)
        d["t"] = tuple(map(int, t.groups())) if t else None
        rm = re.search(r'\br = \{ ((?:\{ \d+, \d+ \}(?:, )?)+) \}', body)
        d["r"] = sorted((int(a), int(b)) for a, b in re.findall(r'\{ (\d+), (\d+) \}', rm.group(1))) if rm else []
        o = re.search(r'out = \{ (\d+), ([\d.]+) \}', body)
        d["out"] = (int(o.group(1)), float(o.group(2))) if o else None
        for key in ("scroll", "scrollPrice", "sq", "oq"):
            v = re.search(rf'\b{key} = (\d+)', body)
            d[key] = int(v.group(1)) if v else None
        rp = re.search(r'rep = \{ (\d+), (\d+) \}', body)
        d["rep"] = (int(rp.group(1)), int(rp.group(2))) if rp else None
        tl = re.search(r'\btool = (\d+|\{ [\d, ]+ \})', body)
        d["tools"] = list(map(int, re.findall(r'\d+', tl.group(1)))) if tl else []
        d["intermediate"] = "intermediate = true" in body
        d["bop"] = "bop = true" in body
        out[sid] = d
    return out


def main():
    verbose = "-v" in sys.argv
    c = client_tables()
    problems = []  # (tipo, texto)
    recipes_n = items_n = 0
    for prof in PROFS:
        text = (ROOT / "Data" / f"{prof}.lua").read_text(encoding="utf-8")
        recipes = lua_recipes(text)
        inames = {int(i): n.replace('\\"', '"')
                  for i, n in re.findall(r'ES\.Data\.ItemNames\[(\d+)\] = "((?:[^"\\]|\\.)*)"', text)}
        sells = {int(i): int(v) for i, v in re.findall(r'ES\.Data\.SellPrices\[(\d+)\] = (\d+)', text)}
        vends = {int(i): int(v) for i, v in re.findall(r'ES\.Data\.VendorPrices\[(\d+)\] = (\d+)', text)}
        used = set()
        line = SKILL[prof]
        for sid, d in recipes.items():
            if sid < 0:
                continue  # conversiones de esencias: no son recetas del cliente
            recipes_n += 1

            def bad(kind, msg):
                problems.append((kind, f"{prof} [{sid}] {d['name']}: {msg}"))
            if not d["intermediate"] and c["names"].get(sid) != d["name"]:
                bad("nombre de receta", f"{d['name']!r} != cliente {c['names'].get(sid)!r}")
            if c["reagents"].get(sid) != d["r"]:
                bad("materiales", f"{d['r']} != cliente {c['reagents'].get(sid)}")
            if c["tools"].get(sid, []) != d["tools"]:
                bad("herramientas", f"{d['tools']} != cliente {c['tools'].get(sid, [])}")
            made = c["creates"].get(sid)
            if (made is None) != (d["out"] is None) or (made and (made[0] != d["out"][0] or abs(made[1] - d["out"][1]) > 1e-6)):
                bad("lo fabricado", f"{d['out']} != cliente {made}")
            th = c["sla"].get((line, sid))
            if th is None:
                bad("receta", "no está en SkillLineAbility de esta profesión")
            elif d["t"] and not d["intermediate"]:
                orange, yellow, grey = th
                if d["t"] != (orange, yellow, (yellow + grey) // 2, grey):
                    bad("umbrales", f"{d['t']} != cliente {(orange, yellow, (yellow + grey) // 2, grey)}")
            if d["scroll"] is not None:
                if d["scroll"] not in c["scrolls"].get(sid, set()):
                    bad("pergamino", f"{d['scroll']} no enseña esta receta según RecipeScrolls ({c['scrolls'].get(sid)})")
                it = c["items"].get(d["scroll"])
                if it:
                    if d["rep"] and d["rep"] != it["rep"]:
                        bad("reputación del pergamino", f"{d['rep']} != cliente {it['rep']}")
                    if d["sq"] is not None and d["sq"] != it["quality"]:
                        bad("calidad del pergamino", f"{d['sq']} != cliente {it['quality']}")
                    if d["scrollPrice"] is not None and abs(d["scrollPrice"] - it["buy"]) > 0.51:
                        bad("precio del pergamino", f"{d['scrollPrice']} != cliente {it['buy']:.1f}")
            if d["out"]:
                used.add(d["out"][0])
                it = c["items"].get(d["out"][0])
                if not it:
                    bad("objeto fabricado ausente del cliente", f"el objeto {d['out'][0]} no está en ItemSparse (sin nombre ni precio en los datos)")
                else:
                    if d["oq"] is not None and d["oq"] != it["quality"]:
                        bad("calidad de lo fabricado", f"{d['oq']} != cliente {it['quality']}")
                    if d["bop"] != it["bop"]:
                        bad("ligado al recogerlo", f"{d['bop']} != cliente {it['bop']}")
            for i, _ in d["r"]:
                used.add(i)
                if i not in inames:
                    bad("material sin nombre", f"el material {i} no tiene nombre en ItemNames")
        for i, n in inames.items():
            items_n += 1
            it = c["items"].get(i)
            if not it:
                problems.append(("objeto ausente del cliente", f"{prof} objeto {i} {n!r}: no está en ItemSparse"))
                continue
            if it["name"] != n:
                problems.append(("nombre de objeto", f"{prof} objeto {i}: {n!r} != cliente {it['name']!r}"))
            if i in sells:
                expected = c["sell_override"].get(i, it["sell"])
                if sells[i] != expected:
                    problems.append(("precio de venta", f"{prof} objeto {i} {n}: {sells[i]} != {'override' if i in c['sell_override'] else 'cliente'} {expected}"))
            elif it["sell"] > 0 and i in used:
                problems.append(("precio de venta", f"{prof} objeto {i} {n}: sin SellPrice aunque el cliente da {it['sell']}"))
            if i in vends and abs(vends[i] - it["buy"]) > 0.51:
                problems.append(("precio de compra", f"{prof} objeto {i} {n}: {vends[i]} != cliente {it['buy']:.1f}"))

    print(f"Recetas comprobadas: {recipes_n} · nombres de objeto comprobados: {items_n} · discrepancias: {len(problems)}")
    for kind, n in sorted(Counter(k for k, _ in problems).items(), key=lambda kv: -kv[1]):
        print(f"  {n:4d}  {kind}")
    if verbose:
        for _, text in problems:
            print("  " + text)
    return 1 if any(k not in ("objeto fabricado ausente del cliente", "objeto ausente del cliente") for k, _ in problems) else 0


if __name__ == "__main__":
    sys.exit(main())
