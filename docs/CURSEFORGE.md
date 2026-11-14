# Página de CurseForge: textos para copiar

## Datos del proyecto

- **Name:** Crafter's Journal
- **Summary** (en inglés, máx. 256 caracteres):
  `Level every profession for the least gold with step-by-step routes built on real Auction House prices, see what's profitable to craft today, and collect every recipe with exactly where to get it. Made for WoW Forever.`
- **Main category:** Professions
- **Additional categories:** Auction & Economy, Map & Minimap (por los puntos de ruta)
- **Game flavor / version:** Forever · 1.60.1
- **License:** la que elijas (por defecto, All Rights Reserved; MIT si quieres que otros reutilicen el código)
- **Source:** https://github.com/brunobasas/CraftersJournal (pestaña Source del proyecto)
- **Logo / avatar:** `docs/logo/logo-400.png` (cuadrado, 400×400; sin letras ni logos de Blizzard)
- **Donaciones:** en *Settings → Donation* del proyecto, si deja elegir Buy Me a Coffee, pon
  `https://buymeacoffee.com/brunobasas` (sale como botón en la página, fuera del juego). Si no
  lo deja, basta con el enlace al final de la descripción. **Nunca dentro del addon** (la política
  de Blizzard prohíbe pedir donaciones en el juego).

## Descripción (pegar en "Description", formato Markdown)

Las imágenes `![...](URL)` son marcadores: sube cada captura en la pestaña *Images* del proyecto,
copia su URL y ponla en su sitio (CurseForge no muestra bien imágenes de fuera).

```markdown
# Crafter's Journal

### Level your professions for the least gold — and always know what to craft next.

Crafter's Journal plans the **cheapest route** for every profession using **real Auction House prices**, tells you **what's profitable to craft today**, and keeps a **journal of every recipe** with exactly where to get it. Built for **WoW Forever**.

![Your cheapest route, step by step](URL_CAPTURA_RUTA)

---

## ✨ Why players use it

**💰 Spend less leveling.** Every route is priced with your own AH scans and the real chance of a skill-up at each level, so it picks the recipes that get you to 300 for the least gold — not the ones a static guide guessed months ago.

**🛒 Shop once, craft, done.** Start a route and your shopping list fills itself, stage by stage. At the AH, a small panel buys the cheap listings for you; at a vendor, one button buys your reagents. Click a step and it crafts.

**📈 Make gold while you level.** *Make Money* shows what's worth crafting and selling right now, how many to make, and when it's safer to sell to a vendor. Open your profession and the same list is right next to it — click to craft.

![Make Money: what's profitable to craft today](URL_CAPTURA_GANAR_DINERO)

---

## 🚀 Start in 30 seconds

1. Type **/cj** (or click the minimap button).
2. Open the **Auction House** and press **Scan** to load real prices.
3. Pick a profession → **Start route** → follow the steps. That's it.

---

## 📖 Everything inside

**Leveling routes**
- Alchemy, Blacksmithing, Enchanting, Engineering, Leatherworking, Tailoring, Cooking and First Aid, up to 300 or any target.
- Skill-up chances included: it knows when a green recipe needs 3 crafts per point.
- Uses the materials you already have first. "Fewer crafts" mode if you'd rather pay a bit more and craft less.
- Shows what each quest-reward recipe asks you to hand in, and warns about limited-stock recipe vendors. Don't like a recipe? Click the **X** and the route finds another.
- If prices change a lot after a new scan, your started route tells you.

**Trainers, vendors & waypoints**
- Real WoW Forever trainer data: who teaches each rank and recipe, and what it costs.
- One click sets a waypoint to the nearest trainer, recipe vendor or quest giver (TomTom and Shortest Path supported).

**Recipe collection**
- Every recipe of every profession in a Dungeon-Journal-style list: known, learnable now, or missing.
- Where to get each one — trainer, vendor, quest, drop, reputation, Merchant's Favor — plus its price and profit.

**Auction House, vendors & bags**
- Windows next to the AH and vendors with exactly what to buy and sell there. Each one can be turned off in the options.
- *Inventory* tab: what to sell from your bags, where, and for how much — keeping what your routes need. Right-click anything to never sell it.
- *Calculator*: the cost and profit of any recipe. Buy intermediates (like Bolts of Mageweave) ready-made or craft them, and type your own prices.

**English & Español** — switch any time, recipe and item names included.

![Your recipe collection](URL_CAPTURA_COLECCION)

---

## 💬 Feedback & support

Found a wrong trainer, a missing recipe or a bug? Tell me on **[Discord](https://discord.gg/DjT4HatsF)** or in the comments — every report makes the routes better.

If Crafter's Journal saved you some gold, you can **[☕ buy me a coffee](https://buymeacoffee.com/brunobasas)**. It's always free, and it always will be.

[![Donate](URL_BOTON_DONATE)](https://buymeacoffee.com/brunobasas) [![Discord](URL_BOTON_DISCORD)](https://discord.gg/DjT4HatsF)

<sub>Data: WoW Forever client tables (wago.tools), My Forever Recipe Book, QuestieDB and CMaNGOS, community Merchant's Favor guides. Routes are checked against the wow-professions.com Forever guides.</sub>
```

## Botones Donate y Discord

`docs/marketing/boton-donate.png` (blanco), `boton-coffee.png` (amarillo de Buy Me a Coffee) y
`boton-discord.png` (azul de Discord). Súbelos también en *Images* (al final, para que no salgan
los primeros de la galería) y en la descripción cambia `URL_BOTON_DONATE` y `URL_BOTON_DISCORD`
por sus direcciones. Si prefieres el amarillo, usa la de `boton-coffee.png` en el de donar.
Cada botón es una imagen con enlace: `[![texto](URL de la imagen)](a dónde lleva)`. Están a
doble tamaño; si salen grandes, el editor visual de CurseForge deja reducirlos.

## Imágenes (ya hechas)

Están en `docs/marketing/` (1920×1080, mismo estilo). Súbelas en la pestaña *Images* en este
orden; la primera es la que sale en las búsquedas. Pon el título y la descripción de la tabla.

| Archivo | Título en CurseForge | Descripción |
|---|---|---|
| `01-portada.png` | Crafter's Journal | Level every profession for the least gold, with real Auction House prices. |
| `02-ruta.png` | Your cheapest route, step by step | Real AH prices and skill-up chances. Click a step to craft it. |
| `03-ganar-dinero.png` | What's profitable to craft today | How many to make, what you invest and what you earn. Adjust with - and +. |
| `04-calculadora.png` | The cost and profit of any recipe | Buy intermediates or craft them, and type your own prices. |
| `05-coleccion.png` | Every recipe, and where to get it | Known, learnable now or missing: trainer, vendor, quest or drop. |
| `06-inventario.png` | Sell the right things in the right place | AH or vendor, net after the cut, and what went up in price first. |

En la descripción: `URL_CAPTURA_RUTA` → la URL de `02-ruta.png`, `URL_CAPTURA_GANAR_DINERO` →
`03-ganar-dinero.png`, `URL_CAPTURA_COLECCION` → `05-coleccion.png`.

**Para rehacerlas** (con capturas nuevas o cambiando los textos): cambia los archivos de
`docs/marketing/shots/` (mismos nombres) o los textos al final de `tools/make_marketing.ps1`, y:

    powershell -File tools\make_marketing.ps1

## Guía para que las capturas vendan

**Antes de capturar**
- **Resolución 1920×1080** (o más) y la escala de la interfaz normal: que el texto del addon se lea sin ampliar.
- **Calidad máxima:** `/console screenshotQuality 10`. La tecla Imprimir Pantalla guarda en la carpeta `Screenshots` del juego.
- **Pantalla limpia:** desactiva los demás addons (un personaje de prueba va bien), cierra el chat o déjalo vacío, quita las placas de nombre (Ctrl+V) y aléjate de otros jugadores.
- **Fondo bonito y del tema:** la AH de Ventormenta u Orgrimmar, un taller, o un sitio con luz. Siempre el mismo personaje y la misma ropa, para que las capturas parezcan de una serie.
- **Datos que cuenten una historia:** un escaneo reciente, una ruta empezada a mitad (con pasos hechos y el actual resaltado), beneficios en verde. Nada de "—" ni listas vacías.

**Al capturar**
- **Una idea por imagen:** la ventana del addon grande y centrada, con algo del juego alrededor para que se vea que es WoW. Mejor que la pantalla entera con el addon pequeño.
- **En las de AH, vendedor o profesión,** que se vean las dos ventanas juntas: la del juego y la del addon. Eso es lo que vende ("está justo ahí cuando lo necesitas").

**Después (Photopea gratis en el navegador, Canva o Figma)**
- **Recorta a 16:9** (1920×1080 o 1600×900), todas igual.
- **Una franja con el título arriba o abajo,** con los colores del addon (marrón oscuro y dorado), en letra grande: "What's profitable to craft today". Que se entienda sin leer la descripción.
- **Una sola flecha o un recuadro dorado** en lo importante (el paso actual, el beneficio, el botón). No más de uno por imagen.
- **Exporta en PNG** (o JPG al 90 %); CurseForge las reduce, así que el texto tiene que verse grande.

**Imagen principal (la 1): ya hecha, `01-portada.png` (ver arriba)**

**Si prefieres hacerla a mano**
- Es la que se ve en las búsquedas: hazla como un póster. A la izquierda el logo sin bordes
  (`docs/logo/logo-sin-borde-1000.png`) y la frase "Level every profession for the least
  gold"; a la derecha, la captura de la ruta un poco inclinada o con sombra.
- Mismo fondo oscuro que el logo, para que todo parezca de la misma marca.

**Bonus: un GIF corto (5-8 s)**
- Clic en un paso de la ruta → se fabrica → el paso se marca hecho. O abrir la profesión y que aparezca la ventana de Ganar dinero. Con ShareX o ScreenToGif (gratis), a 15 fps y unos 800 px de ancho. Va arriba en la descripción, debajo de la primera frase.
