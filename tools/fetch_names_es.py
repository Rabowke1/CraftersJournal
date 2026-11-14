"""Nombres de recetas y objetos en otro idioma del cliente de WoW Forever (esES, deDE).

Descarga SpellName e ItemSparse de wago.tools con locale=<locale> y los recorta a las
recetas y objetos que usa el addon -> tools/wago/SpellName_forever_<locale>.csv e
ItemSparse_forever_<locale>.csv (ID, nombre). Luego gen_names.py genera Data/Names_<locale>.lua.
Uso: python fetch_names_es.py [locale ...]   (por defecto esES; p. ej. python fetch_names_es.py deDE)
     (solo hace falta al cambiar de versión del cliente)
"""
import csv
import io
import sys
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
WAGO = HERE / "wago"
BUILD = "1.60.1.70862"
LOCALES = ("esES", "deDE")


def download(table, locale):
    url = f"https://wago.tools/db2/{table}/csv?build={BUILD}&locale={locale}"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    return urllib.request.urlopen(req, timeout=120).read().decode("utf-8")


def ids(name, col):
    with open(WAGO / name, encoding="utf-8") as f:
        return {r[col] for r in csv.DictReader(f)}


def fetch(locale):
    spells = ids("SpellName_forever.csv", "ID")
    items = ids("ItemSparse_forever.csv", "ID")
    for table, keep, name_col, out in (("SpellName", spells, "Name_lang", f"SpellName_forever_{locale}.csv"),
                                       ("ItemSparse", items, "Display_lang", f"ItemSparse_forever_{locale}.csv")):
        rows = [r for r in csv.DictReader(io.StringIO(download(table, locale))) if r["ID"] in keep]
        with open(WAGO / out, "w", encoding="utf-8", newline="") as f:
            w = csv.writer(f)
            w.writerow(["ID", "Name"])
            for r in rows:
                w.writerow([r["ID"], r[name_col]])
        print(out, len(rows), "filas")


def main():
    for locale in sys.argv[1:] or ["esES"]:
        if locale not in LOCALES:
            sys.exit(f"Idioma desconocido: {locale} (hay {', '.join(LOCALES)})")
        fetch(locale)


if __name__ == "__main__":
    sys.exit(main())
