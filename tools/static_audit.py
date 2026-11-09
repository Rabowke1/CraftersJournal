"""Auditoría estática simple: locales sin usar y globales escritas sin querer."""
import re
from pathlib import Path
A = Path(__file__).resolve().parent.parent  # el repositorio
toc = (A / "CraftersJournal.toc").read_text(encoding="utf-8")
files = [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("#") and not l.startswith("Data")]

KNOWN_GLOBALS = {"CraftersJournalDB", "SLASH_CRAFTERSJOURNAL1", "SLASH_CRAFTERSJOURNAL2", "CraftersJournal_OnAddonCompartmentClick"}


def strip(text):
    text = re.sub(r"--\[\[.*?\]\]", "", text, flags=re.S)
    text = re.sub(r"--[^\n]*", "", text)
    text = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', text)
    return text


for f in files:
    p = A / f.replace("\\", "/")
    code = strip(p.read_text(encoding="utf-8"))
    # locales declaradas
    for m in re.finditer(r"\blocal\s+(?:function\s+)?([A-Za-z_][\w]*(?:\s*,\s*[A-Za-z_]\w*)*)", code):
        for name in [n.strip() for n in m.group(1).split(",")]:
            if name == "_" or not name:
                continue
            uses = len(re.findall(r"(?<![\w.:])" + re.escape(name) + r"\b", code))
            if uses <= 1:
                line = code[:m.start()].count("\n") + 1
                print(f"{f}:{line}: local sin usar: {name}")
    # asignaciones a nombres no declarados al nivel de línea (posibles globales)
    declared = set(re.findall(r"\blocal\s+(?:function\s+)?([A-Za-z_]\w*)", code))
    for m in re.finditer(r"^\s*([A-Za-z_]\w*)\s*=[^=]", code, re.M):
        name = m.group(1)
        if name not in declared and name not in KNOWN_GLOBALS and not name.startswith("ES"):
            # puede ser una local declarada en una lista "local a, b"
            if not re.search(r"\blocal\s+[\w\s,]*\b" + name + r"\b", code):
                line = code[:m.start()].count("\n") + 1
                print(f"{f}:{line}: ¿global?: {name}")
