"""Genera Data/Names_esES.lua y Data/Names_deDE.lua: nombres en español y en alemán
de las recetas y objetos del addon.

Lee tools/wago/SpellName_forever_<locale>.csv e ItemSparse_forever_<locale>.csv (ver
fetch_names_es.py) y guarda solo los que cambian respecto al inglés. El addon los
usa cuando su idioma es ese y el cliente está en otro idioma (y al revés usa
los ingleses de ES.Data.ItemNames y el nombre de cada receta).
Uso: python gen_names.py [esES] [deDE]   (sin argumentos, todos los idiomas)
"""
import csv
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ADDON = HERE.parent
WAGO = HERE / "wago"
PROFS = ["Leatherworking", "Enchanting", "Tailoring", "Blacksmithing", "Alchemy", "Engineering", "Cooking", "FirstAid"]
# locale del cliente -> (tabla de Lua, idioma en el comentario)
LOCALES = {"esES": ("NamesES", "español"), "deDE": ("NamesDE", "alemán")}


def read(name):
    path = WAGO / name
    if not path.exists():
        return {}
    with open(path, encoding="utf-8") as f:
        return {int(r["ID"]): r["Name"] for r in csv.DictReader(f)}


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def generate(locale):
    table, language = LOCALES[locale]
    spells_loc, items_loc = read(f"SpellName_forever_{locale}.csv"), read(f"ItemSparse_forever_{locale}.csv")
    if not spells_loc and not items_loc:
        print(f"{locale}: faltan los CSV de tools/wago (python fetch_names_es.py {locale}); no se genera")
        return
    spells, items = {}, {}
    for prof in PROFS:
        text = (ADDON / "Data" / f"{prof}.lua").read_text(encoding="utf-8")
        for sid, name in re.findall(r'^\s*\[(\d+)\] = \{ name = "((?:[^"\\]|\\.)*)"', text, re.M):
            loc = spells_loc.get(int(sid))
            if loc and loc != name:
                spells[int(sid)] = loc
        used = {int(x) for x in re.findall(r"\{ (\d+), [\d.]+ \}", text)}  # materiales y lo fabricado
        used |= {int(x) for x in re.findall(r"scroll = (\d+)", text)}
        used |= {int(x) for x in re.findall(r"ES\.Data\.ItemNames\[(\d+)\]", text)}
        en = dict((int(i), n) for i, n in re.findall(r'ES\.Data\.ItemNames\[(\d+)\] = "((?:[^"\\]|\\.)*)"', text))
        for iid in used:
            loc = items_loc.get(iid)
            if loc and loc != en.get(iid):
                items[iid] = loc
    out = [f"-- Generado por tools/gen_names.py (cliente de Forever en {locale}, wago.tools). No editar a mano.",
           "local _, ES = ...", "ES.Data = ES.Data or {}", "",
           f"-- Nombres en {language} (solo los que cambian respecto al inglés)",
           f"ES.Data.{table} = {{ spells = {{}}, items = {{}} }}",
           f"local S, I = ES.Data.{table}.spells, ES.Data.{table}.items"]
    out += [f"S[{k}] = {lua_str(v)}" for k, v in sorted(spells.items())]
    out += [f"I[{k}] = {lua_str(v)}" for k, v in sorted(items.items())]
    out.append("")
    dest = ADDON / "Data" / f"Names_{locale}.lua"
    dest.write_text("\n".join(out), encoding="utf-8")
    print(f"{dest}: {len(spells)} recetas y {len(items)} objetos en {language}, {dest.stat().st_size // 1024} KB")


def main():
    locales = sys.argv[1:] or list(LOCALES)
    for locale in locales:
        if locale not in LOCALES:
            sys.exit(f"Idioma desconocido: {locale} (hay {', '.join(LOCALES)})")
        generate(locale)


if __name__ == "__main__":
    main()
