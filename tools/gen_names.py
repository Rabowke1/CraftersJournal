"""Genera Data/Names_<locale>.lua: nombres de las recetas y objetos del addon en los
idiomas del addon distintos del inglés (español, alemán).

Lee tools/wago/SpellName_forever_<locale>.csv e ItemSparse_forever_<locale>.csv (ver
fetch_names.py) y guarda solo los que cambian respecto al inglés. El addon los usa cuando
su idioma es ese y el cliente está en otro (ES.Data.Names[idioma], ver Core.lua); con el
cliente en el mismo idioma toma los nombres del propio juego. Si falta el CSV de un
idioma se salta: en ese idioma, con un cliente de otro, recetas y objetos salen en inglés.
Uso: python gen_names.py [esES deDE ...]   (por defecto, todos los idiomas con CSV)
"""
import csv
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ADDON = HERE.parent
WAGO = HERE / "wago"
TOC = ADDON / "CraftersJournal.toc"
PROFS = ["Leatherworking", "Enchanting", "Tailoring", "Blacksmithing", "Alchemy", "Engineering", "Cooking", "FirstAid",
         "Fishing"]
# locale del cliente -> clave del idioma en el addon (ES.LANGS, Locale.lua) y su nombre
LOCALES = {"esES": ("es", "español"), "deDE": ("de", "alemán")}


def read(name):
    path = WAGO / name
    if not path.exists():
        return {}
    with open(path, encoding="utf-8") as f:
        return {int(r["ID"]): r["Name"] for r in csv.DictReader(f)}


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def used_names():
    """Recetas (hechizo -> nombre en inglés) y objetos (id -> nombre en inglés, o None) que usa el addon."""
    spells, items = {}, {}
    for prof in PROFS:
        text = (ADDON / "Data" / f"{prof}.lua").read_text(encoding="utf-8")
        for sid, name in re.findall(r'^\s*\[(\d+)\] = \{ name = "((?:[^"\\]|\\.)*)"', text, re.M):
            spells[int(sid)] = name
        used = {int(x) for x in re.findall(r"\{ (\d+), [\d.]+ \}", text)}  # materiales y lo fabricado
        used |= {int(x) for x in re.findall(r"scroll = (\d+)", text)}
        used |= {int(x) for x in re.findall(r"ES\.Data\.ItemNames\[(\d+)\]", text)}
        en = dict((int(i), n) for i, n in re.findall(r'ES\.Data\.ItemNames\[(\d+)\] = "((?:[^"\\]|\\.)*)"', text))
        for iid in used:
            items[iid] = en.get(iid, items.get(iid))
    return spells, items


def ensure_toc(entry):
    """El .toc carga el archivo de nombres: tras el último Data\\Names_*.lua (o tras Data\\Sources.lua)."""
    lines = TOC.read_text(encoding="utf-8").splitlines()
    if entry in lines:
        return
    at = max((i for i, l in enumerate(lines) if l.startswith("Data\\Names_") or l == "Data\\Sources.lua"), default=None)
    if at is None:
        sys.exit(f"{TOC.name}: no encuentro dónde poner {entry}")
    lines.insert(at + 1, entry)
    TOC.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"{TOC.name}: añadido {entry}")


def generate(locale):
    lang, label = LOCALES[locale]
    spells_l, items_l = read(f"SpellName_forever_{locale}.csv"), read(f"ItemSparse_forever_{locale}.csv")
    if not spells_l and not items_l:
        print(f"{locale}: sin CSV en tools/wago (descárgalos con: python fetch_names.py {locale})")
        return False
    spells_en, items_en = used_names()
    spells = {sid: spells_l[sid] for sid, en in spells_en.items() if spells_l.get(sid) and spells_l[sid] != en}
    items = {iid: items_l[iid] for iid, en in items_en.items() if items_l.get(iid) and items_l[iid] != en}
    out = [f"-- Generado por tools/gen_names.py (cliente de Forever en {locale}, wago.tools). No editar a mano.",
           "local _, ES = ...", "ES.Data = ES.Data or {}", "ES.Data.Names = ES.Data.Names or {}", "",
           f"-- Nombres en {label} (solo los que cambian respecto al inglés)",
           f"ES.Data.Names.{lang} = {{ spells = {{}}, items = {{}} }}",
           f"local S, I = ES.Data.Names.{lang}.spells, ES.Data.Names.{lang}.items"]
    out += [f"S[{k}] = {lua_str(v)}" for k, v in sorted(spells.items())]
    out += [f"I[{k}] = {lua_str(v)}" for k, v in sorted(items.items())]
    out.append("")
    dest = ADDON / "Data" / f"Names_{locale}.lua"
    dest.write_text("\n".join(out), encoding="utf-8")
    ensure_toc(f"Data\\Names_{locale}.lua")
    print(f"{dest}: {len(spells)} recetas y {len(items)} objetos en {label}, {dest.stat().st_size // 1024} KB")
    return True


def main():
    locales = sys.argv[1:] or list(LOCALES)
    for locale in locales:
        if locale not in LOCALES:
            sys.exit(f"idioma desconocido: {locale} (conocidos: {', '.join(LOCALES)})")
        generate(locale)


if __name__ == "__main__":
    main()
