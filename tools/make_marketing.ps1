<#
Imágenes de la página de CurseForge, todas con el mismo estilo (1920x1080, fondo oscuro
como el del logo, marco dorado):
  01-portada.png        póster: logo, nombre y frase a la izquierda; la ruta a la derecha
  02..06-*.png          una por función: título grande, una línea y la captura enmarcada
Las capturas salen de docs\marketing\shots (cámbialas por otras y vuelve a generar).
Solo usa Windows (System.Drawing).

Uso (desde la carpeta del repositorio):
  powershell -File tools\make_marketing.ps1
Sale en docs\marketing\ (docs no va en el paquete del addon).
#>
param(
  [string]$Shots = "docs\marketing\shots",
  [string]$OutDir = "docs\marketing",
  [string]$Logo = "docs\logo\logo-sin-borde-1000.png"
)
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
public static class Marketing {
  const int W = 1920, H = 1080;
  static readonly Color GoldLight = Color.FromArgb(255, 242, 184);
  static readonly Color Gold = Color.FromArgb(240, 197, 90);
  static readonly Color GoldDark = Color.FromArgb(184, 130, 31);
  static readonly Color Cream = Color.FromArgb(245, 236, 216);
  static readonly Color Muted = Color.FromArgb(200, 214, 178);
  static readonly string[] Serif = { "Palatino Linotype", "Book Antiqua", "Georgia" };
  static readonly string[] Sans = { "Segoe UI Semibold", "Segoe UI" };

  static GraphicsPath Rounded(RectangleF r, float rad) {
    var p = new GraphicsPath();
    float d = rad * 2;
    p.AddArc(r.X, r.Y, d, d, 180, 90);
    p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
    p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
    p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
    p.CloseFigure();
    return p;
  }

  static Font Pick(string[] names, float size, FontStyle style) {
    foreach (var n in names) {
      try { var f = new Font(n, size, style, GraphicsUnit.Pixel); if (f.Name == n) return f; f.Dispose(); } catch { }
    }
    return new Font(FontFamily.GenericSerif, size, style, GraphicsUnit.Pixel);
  }

  static Graphics Canvas(Bitmap bmp, PointF light) {
    var g = Graphics.FromImage(bmp);
    g.SmoothingMode = SmoothingMode.AntiAlias;
    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
    g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
    g.Clear(Color.FromArgb(8, 7, 10));
    using (var path = new GraphicsPath()) {
      path.AddEllipse(-500, -500, W + 1000, H + 1000);
      using (var br = new PathGradientBrush(path)) {
        br.CenterPoint = light;
        br.CenterColor = Color.FromArgb(48, 43, 52);
        br.SurroundColors = new[] { Color.FromArgb(8, 7, 10) };
        g.FillRectangle(br, 0, 0, W, H);
      }
    }
    using (var pen = new Pen(Color.FromArgb(120, Gold), 2)) {
      g.DrawLine(pen, 60, 34, W - 60, 34);
      g.DrawLine(pen, 60, H - 34, W - 60, H - 34);
    }
    return g;
  }

  // La captura, escalada para caber en `box`, con sombra, esquinas redondeadas y marco dorado
  static RectangleF Shot(Graphics g, string path, RectangleF box) {
    using (var shot = Image.FromFile(path)) {
      float s = Math.Min(box.Width / shot.Width, box.Height / shot.Height);
      float sw = shot.Width * s, sh = shot.Height * s;
      var rect = new RectangleF(box.X + (box.Width - sw) / 2, box.Y + (box.Height - sh) / 2, sw, sh);
      for (int i = 22; i >= 1; i--) {
        using (var p = Rounded(new RectangleF(rect.X - i + 8, rect.Y - i + 16, rect.Width + 2 * i, rect.Height + 2 * i), 14 + i))
        using (var br = new SolidBrush(Color.FromArgb(9, 0, 0, 0))) g.FillPath(br, p);
      }
      using (var clip = Rounded(rect, 12)) {
        var state = g.Save();
        g.SetClip(clip);
        g.DrawImage(shot, rect);
        g.Restore(state);
        using (var lg = new LinearGradientBrush(rect, GoldLight, GoldDark, 45f))
        using (var pen = new Pen(lg, 4)) g.DrawPath(pen, clip);
      }
      return rect;
    }
  }

  static void GoldText(Graphics g, string text, Font font, float x, float y, StringFormat fmt, float width) {
    var r = new RectangleF(x, y, width, font.Size * 1.5f);
    using (var sh = new SolidBrush(Color.FromArgb(170, 0, 0, 0)))
      g.DrawString(text, font, sh, new RectangleF(r.X + 3, r.Y + 4, r.Width, r.Height), fmt);
    using (var tg = new LinearGradientBrush(new RectangleF(r.X, r.Y, r.Width, font.Size * 1.2f), GoldLight, GoldDark, 90f))
      g.DrawString(text, font, tg, r, fmt);
  }

  static void Save(Bitmap bmp, string outPath) {
    var dir = System.IO.Path.GetDirectoryName(outPath);
    if (!string.IsNullOrEmpty(dir)) System.IO.Directory.CreateDirectory(dir);
    bmp.Save(outPath, ImageFormat.Png);
    Console.WriteLine("ok " + outPath);
  }

  // Póster: a la izquierda logo, nombre, frase y una línea pequeña; a la derecha la captura
  public static void Poster(string shot, string logo, string outPath, string line1, string line2, string small) {
    var bmp = new Bitmap(W, H, PixelFormat.Format32bppArgb);
    using (var g = Canvas(bmp, new PointF(560, 470))) {
      Shot(g, shot, new RectangleF(800, 120, 1030, 840));
      float x = 110;
      using (var img = Image.FromFile(logo)) {
        float ls = 290f / Math.Max(img.Width, img.Height);
        g.DrawImage(img, new RectangleF(x - 10, 130, img.Width * ls, img.Height * ls));
      }
      var left = new StringFormat();
      using (var title = Pick(Serif, 72, FontStyle.Bold))
      using (var big = Pick(Serif, 52, FontStyle.Regular))
      using (var sm = Pick(Sans, 25, FontStyle.Regular)) {
        float y = 450;
        GoldText(g, "Crafter's Journal", title, x, y, left, 680);
        y += 110;
        using (var cream = new SolidBrush(Cream)) {
          g.DrawString(line1, big, cream, x, y);
          g.DrawString(line2, big, cream, x, y + 64);
        }
        y += 160;
        using (var pen = new Pen(Color.FromArgb(200, Gold), 3)) g.DrawLine(pen, x + 4, y, x + 120, y);
        using (var muted = new SolidBrush(Muted)) g.DrawString(small, sm, muted, new RectangleF(x, y + 22, 660, 90));
      }
    }
    Save(bmp, outPath);
    bmp.Dispose();
  }

  // Botón para la descripción (Donate, Discord): texto en negrita sobre una píldora de
  // color, a doble tamaño para que se vea nítido. Fondo transparente alrededor
  public static void Badge(string outPath, string text, Color back, Color fore) {
    using (var font = Pick(new[] { "Segoe UI Black", "Segoe UI" }, 52, FontStyle.Bold))
    using (var measure = new Bitmap(1, 1))
    using (var mg = Graphics.FromImage(measure)) {
      mg.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
      var size = mg.MeasureString(text, font, 2000, StringFormat.GenericTypographic);
      int w = (int)Math.Ceiling(size.Width) + 64, h = 92;
      var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
      using (var g = Graphics.FromImage(bmp)) {
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        g.Clear(Color.Transparent);
        using (var p = Rounded(new RectangleF(1, 1, w - 2, h - 2), 14))
        using (var br = new SolidBrush(back)) g.FillPath(br, p);
        var fmt = new StringFormat(StringFormat.GenericTypographic) { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
        using (var tb = new SolidBrush(fore)) g.DrawString(text, font, tb, new RectangleF(0, 2, w, h), fmt);
      }
      Save(bmp, outPath);
      bmp.Dispose();
    }
  }

  // Imagen de una función: título y una línea arriba, captura grande, marca pequeña abajo
  public static void Card(string shot, string logo, string outPath, string title, string subtitle) {
    var bmp = new Bitmap(W, H, PixelFormat.Format32bppArgb);
    using (var g = Canvas(bmp, new PointF(W / 2f, 140))) {
      var center = new StringFormat { Alignment = StringAlignment.Center };
      using (var tf = Pick(Serif, 66, FontStyle.Bold))
      using (var sf = Pick(Sans, 30, FontStyle.Regular)) {
        GoldText(g, title, tf, 0, 62, center, W);
        using (var cream = new SolidBrush(Cream)) g.DrawString(subtitle, sf, cream, new RectangleF(0, 160, W, 50), center);
      }
      Shot(g, shot, new RectangleF(150, 232, W - 300, 770));
      // Marca, abajo a la izquierda (sobre la línea dorada)
      using (var img = Image.FromFile(logo)) {
        float ls = 44f / Math.Max(img.Width, img.Height);
        g.DrawImage(img, new RectangleF(70, H - 92, img.Width * ls, img.Height * ls));
      }
      using (var bf = Pick(Serif, 24, FontStyle.Bold))
      using (var gold = new SolidBrush(Gold)) g.DrawString("Crafter's Journal", bf, gold, 124, H - 84);
    }
    Save(bmp, outPath);
    bmp.Dispose();
  }
}
"@
$root = (Get-Location).Path
function Full($p) { if ([System.IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $root $p } }
$dot = [string][char]0x00B7
$shotDir, $out, $logo = (Full $Shots), (Full $OutDir), (Full $Logo)

[Marketing]::Poster("$shotDir\ruta.png", $logo, "$out\01-portada.png",
  "Level every profession", "for the least gold",
  "Real Auction House prices  $dot  Step-by-step routes`nMade for WoW Forever")

$cards = @(
  @("ruta.png",         "02-ruta.png",         "Your cheapest route, step by step",
    "Real AH prices and skill-up chances  $dot  Click a step to craft it"),
  @("ganar-dinero.png", "03-ganar-dinero.png", "What's profitable to craft today",
    "How many to make, what you invest and what you earn  $dot  Adjust with - and +"),
  @("calculadora.png",  "04-calculadora.png",  "The cost and profit of any recipe",
    "Buy intermediates or craft them  $dot  Type your own prices"),
  @("coleccion.png",    "05-coleccion.png",    "Every recipe, and where to get it",
    "Known, learnable now or missing  $dot  Trainer, vendor, quest or drop"),
  @("inventario.png",   "06-inventario.png",   "Sell the right things in the right place",
    "AH or vendor, net after the cut  $dot  What went up in price, first")
)
foreach ($c in $cards) { [Marketing]::Card("$shotDir\$($c[0])", $logo, "$out\$($c[1])", $c[2], $c[3]) }

# Botones de la descripción (se suben a la galería y se enlazan: ver docs\CURSEFORGE.md)
$C = [System.Drawing.Color]
[Marketing]::Badge("$out\boton-donate.png", "Donate", $C::White, $C::Black)
[Marketing]::Badge("$out\boton-coffee.png", "Buy me a coffee", $C::FromArgb(255, 221, 0), $C::Black)   # amarillo de Buy Me a Coffee
[Marketing]::Badge("$out\boton-discord.png", "Discord", $C::FromArgb(88, 101, 242), $C::White)        # azul de Discord
