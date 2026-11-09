"""Compara Data/<Profesion>.lua con Wowhead (rama Forever): nombre en inglés y alemán,
precio de venta y ligado de cada objeto; nombre, materiales, herramienta y objeto
fabricado de cada receta. Usa los tooltips de nether.wowhead.com/forever (JSON), que
salen de las mismas tablas del cliente que publica Wowhead.

Uso: python check_wowhead.py [--cache CARPETA] [--limit N] [--workers N] [-v]
  --cache   dónde guardar las respuestas (por defecto, la carpeta temporal del sistema)
  --limit   solo los N primeros objetos y recetas (para probar)
  -v        cada discrepancia (si no, el resumen por tipo)
Las respuestas se guardan en caché: volver a ejecutarlo no vuelve a descargar nada.
"""
import argparse
import html
import json
import re
import sys
import tempfile
import time
import urllib.error
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PROFS = ["Leatherworking", "Enchanting", "Tailoring", "Blacksmithing", "Alchemy", "Engineering", "Cooking", "FirstAid"]
BASE = "https://nether.wowhead.com/forever/tooltip/{kind}/{id}?locale={locale}"
LOCALES = {"en": 0, "de": 3}
UA = "Mozilla/5.0 (CraftersJournal data check; +https://github.com/brunobasas/CraftersJournal)"


def fetch(kind, wid, locale, cache):
    """JSON del tooltip (o {"error": ...}); en caché por archivo."""
    path = cache / f"{kind}_{wid}_{locale}.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    url = BASE.format(kind=kind, id=wid, locale=locale)
    for attempt in range(5):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = json.loads(r.read().decode("utf-8"))
            break
        except urllib.error.HTTPError as e:
            if e.code == 404:
                data = {"error": "not found"}
                break
            if attempt == 4:
                return {"error": f"http {e.code}"}
            time.sleep(2 ** attempt)
        except Exception as e:  # red: reintentar
            if attempt == 4:
                return {"error": str(e)}
            time.sleep(2 ** attempt)
    path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    time.sleep(0.05)
    return data


def money(tooltip):
    """Precio de venta en cobre del tooltip, o None."""
    m = re.search(r'whtt-sellprice">(.*?)</div>', tooltip)
    if not m:
        return None
    total = 0
    for unit, n in re.findall(r'class="money(gold|silver|copper)">(\d+)</span>', m.group(1)):
        total += int(n) * {"gold": 10000, "silver": 100, "copper": 1}[unit]
    return total


def items_in(block):
    """{objeto: cantidad} de un bloque de enlaces 'Nombre (2), Otro'."""
    out = {}
    for wid, qty in re.findall(r'href="/forever/item=(\d+)[^"]*"[^>]*>[^<]*</a>(?:\s|&nbsp;)*(?:\((\d+)\))?', block):
        out[int(wid)] = int(qty) if qty else 1
    return out


def tools_in(block):
    """Herramientas de un bloque: categorías (enlace items?filter=91;CAT;0, como el martillo de
    herrero o los bastones) y objetos concretos (enlace item=ID, como Flint and Tinder)."""
    cats = {int(c) for c in re.findall(r'href="/forever/items\?filter=91;(\d+);0"', block)}
    return cats, set(items_in(block))


def parse_spell(d):
    t = d.get("tooltip", "")
    reagents = re.search(r'Reagents:<br />\s*<div class="indent q1">(.*?)</div>', t)
    tools = re.search(r'Tools:<br />\s*<div class="indent q1">(.*?)</div>', t)
    rest = t
    for m in (reagents, tools):
        if m:
            rest = rest.replace(m.group(0), "")
    created = re.search(r'<span class="q\d"><a href="/forever/item=(\d+)/', rest)
    cats, tool_items = tools_in(tools.group(1)) if tools else (set(), set())
    return {"name": d.get("name"), "reagents": items_in(reagents.group(1)) if reagents else {},
            "toolCats": cats, "toolItems": tool_items,
            "created": int(created.group(1)) if created else None}


def parse_item(d):
    t = d.get("tooltip", "")
    return {"name": d.get("name"), "sell": money(t), "bop": "Binds when picked up" in t or "Wird beim Aufheben gebunden" in t}


RECIPE = re.compile(r'^\s*\[(\d+)\] = \{ (.*) \},', re.M)


def load_data():
    recipes, item_names, sells, names_de = {}, {}, {}, {"spells": {}, "items": {}}
    for prof in PROFS:
        text = (ROOT / "Data" / f"{prof}.lua").read_text(encoding="utf-8")
        for m in RECIPE.finditer(text):
            sid, body = int(m.group(1)), m.group(2)
            if "intermediate = true" in body or "conversion = true" in body:
                continue
            d = {"prof": prof}
            d["name"] = re.search(r'name = "((?:[^"\\]|\\.)*)"', body).group(1).replace('\\"', '"')
            rm = re.search(r'\br = \{ ((?:\{ \d+, \d+ \}(?:, )?)+) \}', body)
            d["r"] = {int(a): int(b) for a, b in re.findall(r'\{ (\d+), (\d+) \}', rm.group(1))} if rm else {}
            o = re.search(r'out = \{ (\d+), ([\d.]+) \}', body)
            d["out"] = int(o.group(1)) if o else None
            tl = re.search(r'\btool = (\d+)', body)
            d["tool"] = int(tl.group(1)) if tl else None  # categoría de herramienta (TotemCategory) u objeto concreto
            sc = re.search(r'\bscroll = (\d+)', body)
            d["scroll"] = int(sc.group(1)) if sc else None
            d["bop"] = "bop = true" in body
            recipes[sid] = d
        for i, n in re.findall(r'ES\.Data\.ItemNames\[(\d+)\] = "((?:[^"\\]|\\.)*)"', text):
            item_names[int(i)] = n.replace('\\"', '"')
        for i, v in re.findall(r'ES\.Data\.SellPrices\[(\d+)\] = (\d+)', text):
            sells[int(i)] = int(v)
    de = ROOT / "Data" / "Names_deDE.lua"
    if de.exists():
        text = de.read_text(encoding="utf-8")
        for k, v in re.findall(r'^S\[(\d+)\] = "((?:[^"\\]|\\.)*)"', text, re.M):
            names_de["spells"][int(k)] = v.replace('\\"', '"')
        for k, v in re.findall(r'^I\[(\d+)\] = "((?:[^"\\]|\\.)*)"', text, re.M):
            names_de["items"][int(k)] = v.replace('\\"', '"')
    return recipes, item_names, sells, names_de


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=str(Path(tempfile.gettempdir()) / "craftersjournal-wowhead"))
    ap.add_argument("--limit", type=int)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("-v", action="store_true")
    a = ap.parse_args()
    cache = Path(a.cache)
    cache.mkdir(parents=True, exist_ok=True)

    recipes, item_names, sells, names_de = load_data()
    # Objetos: los nombrados en los datos, los pergaminos y lo fabricado (también lo que
    # el cliente exportado no traía: así se sabe qué son)
    item_ids = set(item_names) | {d["scroll"] for d in recipes.values() if d["scroll"]} \
        | {d["out"] for d in recipes.values() if d["out"]}
    item_ids = sorted(item_ids)
    spell_ids = sorted(recipes)
    if a.limit:
        item_ids, spell_ids = item_ids[:a.limit], spell_ids[:a.limit]
    jobs = [("item", i, loc) for i in item_ids for loc in LOCALES.values()] + \
           [("spell", s, loc) for s in spell_ids for loc in LOCALES.values()]
    print(f"{len(item_ids)} objetos y {len(spell_ids)} recetas en {len(LOCALES)} idiomas: {len(jobs)} tooltips "
          f"(caché en {cache})", flush=True)
    results = {}
    done = 0
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        for job, data in zip(jobs, ex.map(lambda j: fetch(j[0], j[1], j[2], cache), jobs)):
            results[job] = data
            done += 1
            if done % 500 == 0:
                print(f"  {done}/{len(jobs)}", flush=True)

    problems = []  # (tipo, texto)
    missing_items, missing_spells = [], []

    def item_label(i):
        return item_names.get(i) or (results.get(("item", i, 0)) or {}).get("name") or str(i)

    for i in item_ids:
        en, de = results[("item", i, 0)], results[("item", i, 3)]
        if "error" in en:
            missing_items.append(i)
            continue
        w = parse_item(en)
        if i in item_names and w["name"] != item_names[i]:
            problems.append(("nombre de objeto (inglés)", f"objeto {i}: datos {item_names[i]!r}, Wowhead {w['name']!r}"))
        if "error" not in de:
            expected = names_de["items"].get(i, item_names.get(i))
            if expected and de.get("name") != expected:
                problems.append(("nombre de objeto (alemán)", f"objeto {i} {item_label(i)}: datos {expected!r}, Wowhead {de.get('name')!r}"))
        if i in sells and w["sell"] is not None and w["sell"] != sells[i]:
            problems.append(("precio de venta", f"objeto {i} {item_label(i)}: datos {sells[i]}c, Wowhead {w['sell']}c"))
        if i in sells and w["sell"] is None:
            problems.append(("precio de venta", f"objeto {i} {item_label(i)}: datos {sells[i]}c, Wowhead no da precio de venta"))
    for sid in spell_ids:
        d = recipes[sid]
        en, de = results[("spell", sid, 0)], results[("spell", sid, 3)]
        if "error" in en:
            missing_spells.append(sid)
            continue
        w = parse_spell(en)
        tag = f"{d['prof']} [{sid}] {d['name']}"
        if w["name"] != d["name"]:
            problems.append(("nombre de receta (inglés)", f"{tag}: Wowhead {w['name']!r}"))
        if "error" not in de:
            expected = names_de["spells"].get(sid, d["name"])
            if de.get("name") != expected:
                problems.append(("nombre de receta (alemán)", f"{tag}: datos {expected!r}, Wowhead {de.get('name')!r}"))
        if w["reagents"] != d["r"]:
            def show(m):
                return ", ".join(f"{item_label(k)} x{v}" for k, v in sorted(m.items()))
            problems.append(("materiales", f"{tag}: datos [{show(d['r'])}], Wowhead [{show(w['reagents'])}]"))
        if w["created"] != d["out"]:
            # Sin enlace al objeto en Wowhead: casi siempre un objeto que el cliente no trae
            # (lo manda el servidor) y Wowhead tampoco tiene; se cuenta aparte
            known = d["out"] and ("item", d["out"], 0) in results and "error" not in results[("item", d["out"], 0)]
            kind = "objeto fabricado" if (w["created"] or known) else "objeto fabricado (sin ficha en Wowhead)"
            problems.append((kind, f"{tag}: datos {d['out']}, Wowhead {w['created']}"))
        # En los datos la herramienta es la categoría de tótem o, si la receta pide un objeto
        # concreto (Flint and Tinder), el propio objeto: Wowhead enlaza una u otro
        wh_tools = w["toolCats"] | w["toolItems"]
        if (d["tool"] and d["tool"] not in wh_tools) or (wh_tools and not d["tool"]):
            problems.append(("herramienta", f"{tag}: datos {d['tool']}, Wowhead categorías {sorted(w['toolCats'])}"
                             + (f" y objetos {sorted(w['toolItems'])}" if w["toolItems"] else "")))
        if d["out"] and ("item", d["out"], 0) in results and "error" not in results[("item", d["out"], 0)]:
            bop = parse_item(results[("item", d["out"], 0)])["bop"]
            if bop != d["bop"]:
                problems.append(("ligado al recogerlo", f"{tag}: datos {d['bop']}, Wowhead {bop}"))

    print(f"\nObjetos comprobados: {len(item_ids) - len(missing_items)} (sin ficha en Wowhead: {len(missing_items)}) · "
          f"recetas comprobadas: {len(spell_ids) - len(missing_spells)} (sin ficha: {len(missing_spells)}) · "
          f"discrepancias: {len(problems)}")
    for kind, n in sorted(Counter(k for k, _ in problems).items(), key=lambda kv: -kv[1]):
        print(f"  {n:4d}  {kind}")
    if a.v:
        for _, text in problems:
            print("  " + text)
        if missing_items:
            print("  objetos sin ficha en Wowhead: " + ", ".join(str(i) for i in missing_items))
        if missing_spells:
            print("  recetas sin ficha en Wowhead: " + ", ".join(str(s) for s in missing_spells))
    return 1 if any(k != "objeto fabricado (sin ficha en Wowhead)" for k, _ in problems) else 0


if __name__ == "__main__":
    sys.exit(main())
