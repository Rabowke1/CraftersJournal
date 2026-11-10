# Página de CurseForge: textos para copiar

## Datos del proyecto

- **Name:** Crafter's Journal
- **Summary** (en inglés, máx. 256 caracteres):
  `Level every profession in WoW Forever the cheapest way with step-by-step routes based on real Auction House prices, find the right trainer for each rank, and track your full recipe collection with where to get every recipe.`
- **Main category:** Professions
- **Additional categories:** Auction & Economy, Map & Minimap (por los puntos de ruta)
- **Game flavor / version:** Forever · 1.60.1
- **License:** la que elijas (por defecto, All Rights Reserved; MIT si quieres que otros reutilicen el código)
- **Source:** https://github.com/brunobasas/CraftersJournal (pestaña Source del proyecto)
- **Logo / avatar:** cuadrado (400×400), sin letras ni logos de Blizzard (nada de "W").

## Descripción (pegar en "Description", formato Markdown)

Solo lo que tiene la versión publicada (sin Ganar dinero, Subastas, Pesca ni el buscador de la cabecera).

```markdown
# Crafter's Journal

**Level every profession the cheapest way and collect every recipe — built for WoW Forever.**

Crafter's Journal tells you exactly what to craft, what to buy and where to go to level your professions for as little gold as possible, and keeps a complete journal of every recipe in the game so you always know where to get the ones you're missing.

---

## 📈 Cheapest leveling routes

- **Step-by-step route** from your current skill to the cap for **Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, Cooking and First Aid**.
- Built on **real Auction House prices** from your own scans — not guesses.
- Shows **what to craft, how many times, and what each step costs**, plus what you get back by selling the results.
- **Uses what you already have**: turn on "use bags and bank" and the route spends your own materials before buying anything.
- **Shopping list** with everything you need to buy, split between the Auction House and vendors.
- Smooth and lag-free: routes are calculated in the background.

## 🧭 Trainers, vendors and waypoints

- **Trainers by rank**: every step sends you to a trainer who really teaches that rank in Forever.
- **One click to set a waypoint** to the nearest trainer, recipe vendor or quest giver (works with TomTom and Shortest Path, or the game's own map pin).

## 📖 Your recipe collection

- Every recipe of each profession in a **journal-style list**, inspired by the Dungeon Journal.
- See at a glance which recipes **you know**, which you **can learn now** and which you're **missing** — with a progress bar to complete your collection.
- **Recipe details** on the right:
  - **Where to get it**: trainer, vendor, quest, drop (creature, level and zone), reputation or **Merchant's Favor** (cost and reputation required).
  - **Prices**: recipe on the Auction House and at the vendor, crafting cost, selling price and **profit per craft**.
  - **Materials** with their cost.
  - Warns you when the crafted item **binds on pickup** and can't be sold on the Auction House.
- **Filters** in one simple window: show learned / learnable now / missing, filter by source, and sort by level, recipe price, profit or cheapest to get.
- **Search** by recipe or material name.
- Only shows recipes **your faction** can learn.

## 🛒 At the Auction House

- **Scan the Auction House** from the addon (the server allows one full scan every 15 minutes; a countdown shows when you can scan again).
- A **shopping panel** next to the Auction House searches the materials your route needs, one by one, and **buys them with one click each** when the current offers don't exceed the route's plan plus a margin you set with a slider ("up to X gold more than planned", per route).
- The same panel lists the **recipes you're missing that are for sale** on the Auction House, per profession, with price, level and profit per craft, and buys the cheapest one with a click.

## 🌍 English, Español and Deutsch

Switch language at any time from the addon window — interface, recipe names and item names change instantly. On a German client the recipe and item names come from the game itself.

---

## How to use

1. Type **/cj** (or click the minimap button) to open the journal.
2. Open the Auction House and press **Scan** to load real prices.
3. Pick a profession to see your cheapest route, or open the **recipe collection** to hunt the recipes you're missing.

## Optional addons

- **TomTom** or **Shortest Path Forever**: arrow and route to your waypoints.
- **QuestieDB**: not required — Crafter's Journal ships with its own data — but it can fill in extra NPC locations.

## Beta notice

WoW Forever is still in beta and so is this addon. Recipe sources for some brand-new Forever recipes aren't known yet and will be added as they're discovered. **Found a wrong trainer, a missing recipe source or a bug?** Leave a comment or open an issue on [GitHub](https://github.com/brunobasas/CraftersJournal) — it really helps.

## Data sources

Recipe and item data come from the WoW Forever client tables (wago.tools); trainer, vendor, quest and drop data from CMaNGOS and QuestieDB; Merchant's Favor recipes and fishing data from community guides.
```

## Capturas recomendadas (por orden)

1. La portada con las tarjetas de profesiones.
2. Una ruta de profesión (vista Ruta) con el resumen de costes.
3. La colección: lista a la izquierda y la ficha de una receta de botín a la derecha.
4. La ventana de filtros de la colección.
5. El panel de la AH con la lista de compra.

Hazlas en **vista jugador** (botón de la cabecera), para que no salgan funciones que aún no están en la versión publicada.
