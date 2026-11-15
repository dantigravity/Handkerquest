using System;
using System.IO;
using System.Text;
using System.Collections.Generic;

// "Runecut": the dwarven runestone's lettering (user request, Nov 2026: "runes were carved and carving straight is
// much more effective in stone ... the letters don't really have curves ... viking like runes"). Our own font, drawn
// here from straight strokes only and written out as a TrueType file (fonts\Runecut.ttf). Latin letters shaped
// after the runes where they still read (R like raido, P like thurisaz, F like fehu, X like gebo, H with a slanted
// bar, O cut as an octagon); no case in runes, so lowercase are small capitals.
//
// Each glyph is polylines on a grid: x from 0, y 0 (baseline) to 10 (cap height). Every segment becomes a
// rectangle of the stroke's width and every point a small diamond (a chisel-cut joint, no curves); all contours
// run clockwise, so the overlaps fill as one shape (non-zero winding).
//
// V-grooved (user request: "make the letters look chiselled with a V shaped tool/groove"): a V-cut has two walls
// meeting along the middle of the stroke. Lit from the top-left, the wall on a stroke's upper-left side faces away
// from the light (shade) and the lower-right wall faces it (lit). BuildGrooved writes the two walls as two fonts with
// the same advances (fonts\RunecutShade.ttf, fonts\RunecutLit.ttf, heavier strokes so each wall is wide enough to
// see at tally size); the runestone draws one over the other in dark and pale stone (P.SetCarve). The joints are
// square pits split into four triangles: top and left walls in shade, bottom and right lit.
//
// Build from PowerShell:  Add-Type -Path tools\RuneFont.cs ; [RuneFont]::Build("fonts\Runecut.ttf")
//                         [RuneFont]::BuildGrooved("fonts\RunecutShade.ttf", "fonts\RunecutLit.ttf")
public static class RuneFont
{
    const int UPM = 1000;
    const double U = 78;            // font units per grid unit, up (cap height 780: big for its size, like the game's faces)
    const double UX = 64;           // ...and across: runes are tall and narrow
    const double STROKE = 122;      // stroke width: one firm chisel cut
    const double GROOVE = 196;      // the V-grooved fonts' stroke: two walls, each wide enough to read at ~14 px
    static double Stroke = STROKE;  // the stroke being built
    static int Mode = 0;            // 0 = whole strokes, 1 = the shaded walls only, 2 = the lit walls only
    const double SIDE = 44;         // side bearing each side
    const int ASC = 1000, DESC = 260;

    // char -> (grid width, polylines "x,y x,y ...; x,y ...")
    static readonly Dictionary<char, KeyValuePair<double, string>> G = new Dictionary<char, KeyValuePair<double, string>>();
    static void D(char c, double w, string s) { G[c] = new KeyValuePair<double, string>(w, s); }

    static void Design()
    {
        D('A', 7, "0,0 3.5,10 7,0; 1.3,3.4 5.6,4.6");
        D('B', 4.8, "0,0 0,10 4.8,7.5 0,5 4.8,2.5 0,0");
        D('C', 5.2, "5.2,8.4 3.6,10 1.8,10 0,8.2 0,1.8 1.8,0 3.6,0 5.2,1.6");
        D('D', 5.6, "0,0 0,10 2.6,10 5.6,7 5.6,3 2.6,0 0,0");
        D('E', 4.8, "4.8,10 0,10 0,0 4.8,0; 0,5 3.8,5.9");
        D('F', 4.8, "0,0 0,10; 0,6.6 4.8,10; 0,3.2 4.8,6.6");
        D('G', 5.6, "5.6,8.4 4,10 1.8,10 0,8.2 0,1.8 1.8,0 4,0 5.6,1.6 5.6,4.6 3,4.6");
        D('H', 5.2, "0,0 0,10; 5.2,0 5.2,10; 0,6.2 5.2,3.8");
        D('I', 0, "0,0 0,10");
        D('J', 4.2, "4.2,10 4.2,1.8 2.4,0 0,1.4");
        D('K', 4.8, "0,0 0,10; 4.8,10 0,5 4.8,0");
        D('L', 4.4, "0,10 0,0 4.4,1.4");
        D('M', 7, "0,0 0,10 3.5,5 7,10 7,0");
        D('N', 5.4, "0,0 0,10 5.4,0 5.4,10");
        D('O', 6, "1.9,10 4.1,10 6,8.1 6,1.9 4.1,0 1.9,0 0,1.9 0,8.1 1.9,10");
        D('P', 4.8, "0,0 0,10 4.8,7.4 0,4.8");
        D('Q', 6.4, "1.9,10 4.1,10 6,8.1 6,1.9 4.1,0 1.9,0 0,1.9 0,8.1 1.9,10; 3.4,3.2 6.4,-1.4");
        D('R', 5, "0,0 0,10 5,7.5 0,5 5,0");
        D('S', 5.2, "5.2,8.4 3.6,10 1.6,10 0,8.4 0,6.6 5.2,3.4 5.2,1.6 3.6,0 1.6,0 0,1.6");
        D('T', 5.6, "2.8,0 2.8,10; 0,8.4 2.8,10 5.6,8.4");
        D('U', 5.2, "0,10 0,1.8 1.8,0 3.4,0 5.2,1.8 5.2,10");
        D('V', 6, "0,10 3,0 6,10");
        D('W', 8.4, "0,10 2.1,0 4.2,6.4 6.3,0 8.4,10");
        D('X', 5.6, "0,0 5.6,10; 0,10 5.6,0");
        D('Y', 5.6, "0,10 2.8,5 5.6,10; 2.8,5 2.8,0");
        D('Z', 5.2, "0,10 5.2,10 0,0 5.2,0");
        D('0', 4.8, "1.6,10 3.2,10 4.8,8.4 4.8,1.6 3.2,0 1.6,0 0,1.6 0,8.4 1.6,10");
        D('1', 2.4, "0,8 2.4,10 2.4,0");
        D('2', 4.8, "0,8.4 1.6,10 3.2,10 4.8,8.4 4.8,6.6 0,0 4.8,0");
        D('3', 4.8, "0,8.4 1.6,10 3.2,10 4.8,8.4 4.8,6.6 3.2,5 4.8,3.4 4.8,1.6 3.2,0 1.6,0 0,1.6; 1.4,5 3.2,5");
        D('4', 4.8, "3.6,0 3.6,10 0,3.2 4.8,3.2");
        D('5', 4.8, "4.8,10 0,10 0,5.6 3.2,5.6 4.8,4 4.8,1.6 3.2,0 0,0");
        D('6', 4.8, "4.4,10 1.6,10 0,8.4 0,1.6 1.6,0 3.2,0 4.8,1.6 4.8,4 3.2,5.6 0,5.6");
        D('7', 4.8, "0,10 4.8,10 1.6,0");
        D('8', 4.8, "1.6,5 0,6.6 0,8.4 1.6,10 3.2,10 4.8,8.4 4.8,6.6 3.2,5 1.6,5 0,3.4 0,1.6 1.6,0 3.2,0 4.8,1.6 4.8,3.4 3.2,5");
        D('9', 4.8, "0.4,0 3.2,0 4.8,1.6 4.8,8.4 3.2,10 1.6,10 0,8.4 0,6 1.6,4.4 4.8,4.4");
        D('.', 0, "0,0.1 0,1.1");
        D(',', 1.2, "1.2,1.2 1.2,0.2 0,-1.8");
        D(':', 0, "0,0.1 0,1.1; 0,5.2 0,6.2");
        D(';', 1.2, "1.2,5.2 1.2,6.2; 1.2,1.2 1.2,0.2 0,-1.8");
        D('!', 0, "0,3.2 0,10; 0,0.1 0,1.1");
        D('?', 4.6, "0,8.4 1.6,10 3,10 4.6,8.4 4.6,6.8 2.3,4.8 2.3,3.2; 2.3,0.1 2.3,1.1");
        D('\'', 0, "0,10 0,7.2");
        D('"', 2, "0,10 0,7.2; 2,10 2,7.2");
        D('-', 3, "0,4.6 3,4.6");
        D('–', 5, "0,4.6 5,4.6");
        D('—', 8, "0,4.6 8,4.6");
        D('(', 2, "2,11 0,8 0,2 2,-1");
        D(')', 2, "0,11 2,8 2,2 0,-1");
        D('[', 2, "2,11 0,11 0,-1 2,-1");
        D(']', 2, "0,11 2,11 2,-1 0,-1");
        D('/', 4, "0,-1 4,11");
        D('\\', 4, "0,11 4,-1");
        D('+', 4, "0,4.6 4,4.6; 2,2.6 2,6.6");
        D('=', 4, "0,3.4 4,3.4; 0,5.8 4,5.8");
        D('%', 5.2, "0,0 5.2,10; 0.5,9.4 0.5,7.6; 4.7,2.4 4.7,0.6");
        D('&', 5.6, "5.6,0 1,6.2 1,8.6 2.3,10 3.6,8.6 3.6,7.2 0,3.6 0,1.6 1.6,0 3.4,0 5.6,3.2");
        D('#', 6, "1.6,0 2.6,10; 3.8,0 4.8,10; 0,3.4 5.6,3.4; 0.4,6.6 6,6.6");
        D('*', 3.6, "1.8,10 1.8,6; 0,9 3.6,7; 0,7 3.6,9");
        D('<', 4, "4,8 0,5 4,2");
        D('>', 4, "0,8 4,5 0,2");
        D('_', 5, "0,-1.4 5,-1.4");
        D('|', 0, "0,-1 0,11");
        D('@', 7, "5,3 5,7 2,7 2,3 5,3 7,3 7,8.4 5.4,10 1.6,10 0,8.4 0,1.6 1.6,0 6,0");
        D('$', 5.2, "5.2,8.4 3.6,10 1.6,10 0,8.4 0,6.6 5.2,3.4 5.2,1.6 3.6,0 1.6,0 0,1.6; 2.6,-1 2.6,11");
        D('^', 4, "0,7 2,10 4,7");
        D('~', 5, "0,4.4 1.6,5.6 3.4,4.4 5,5.6");
        D('`', 1, "0,10 1,8.6");
        D('·', 0, "0,4.4 0,5.4");                      // middle dot (the tally's "Near me · Valley")
        D('×', 4, "0,2.6 4,6.6; 0,6.6 4,2.6");         // multiplication sign
        D('…', 4.4, "0,0.1 0,1.1; 2.2,0.1 2.2,1.1; 4.4,0.1 4.4,1.1");
        D('‘', 0, "0,10 0,7.2");
        D('’', 0, "0,10 0,7.2");
        D('“', 2, "0,10 0,7.2; 2,10 2,7.2");
        D('”', 2, "0,10 0,7.2; 2,10 2,7.2");
        D('•', 0, "0,4.2 0,5.6");
    }

    // Latin-1 letters with accents share the plain letter's runes (runes have no accents)
    static readonly string Accented = "ÀÁÂÃÄÅàáâãäåÇçÈÉÊËèéêëÌÍÎÏìíîïÑñÒÓÔÕÖØòóôõöøÙÚÛÜùúûüÝýÿ";
    static readonly string AccentBase = "AAAAAAaaaaaaCcEEEEeeeeIIIIiiiiNnOOOOOOooooooUUUUuuuuYyy";

    class Glyph { public int Adv; public List<int[][]> Contours = new List<int[][]>(); }

    static void AddQuad(Glyph g, double[] xs, double[] ys)
    {
        // clockwise in font space (y up): negative shoelace area
        double a = 0;
        for (int i = 0; i < xs.Length; i++) { int j = (i + 1) % xs.Length; a += xs[i] * ys[j] - xs[j] * ys[i]; }
        var pts = new int[xs.Length][];
        for (int i = 0; i < xs.Length; i++)
        {
            int k = a > 0 ? xs.Length - 1 - i : i;
            pts[i] = new[] { (int)Math.Round(xs[k]), (int)Math.Round(ys[k]) };
        }
        g.Contours.Add(pts);
    }

    // a wall is in shade when it lies on the side of the stroke the light comes from (up-left: -x, +y)
    static bool ShadeSide(double nx, double ny)
    {
        double d = -nx + ny;
        if (Math.Abs(d) < 1e-9) return ny > 0 || (ny == 0 && nx < 0);
        return d > 0;
    }

    static void AddWall(Glyph g, bool shade, double[] xs, double[] ys)
    {
        if ((Mode == 1 && shade) || (Mode == 2 && !shade)) AddQuad(g, xs, ys);
    }

    static Glyph Make(double gw, string spec, double scale)
    {
        var g = new Glyph();
        double h = Stroke / 2;
        double ox = SIDE + h;
        g.Adv = (int)Math.Round(gw * UX * scale + Stroke + SIDE * 2);
        foreach (var line in spec.Split(';'))
        {
            var pts = new List<double[]>();
            foreach (var tok in line.Trim().Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries))
            {
                var xy = tok.Split(',');
                pts.Add(new[] { ox + double.Parse(xy[0], System.Globalization.CultureInfo.InvariantCulture) * UX * scale,
                                double.Parse(xy[1], System.Globalization.CultureInfo.InvariantCulture) * U * scale });
            }
            for (int i = 0; i < pts.Count; i++)
            {
                double px = pts[i][0], py = pts[i][1];
                if (Mode == 0)
                {
                    // a diamond at every point: the chisel's joint, filling the corner between two strokes
                    double r = h * 1.08;
                    AddQuad(g, new[] { px, px + r, px, px - r }, new[] { py + r, py, py - r, py });
                }
                else
                {
                    // a square pit at every joint, its four walls meeting in the middle: top and left in shade
                    double r = h;
                    AddWall(g, true, new[] { px, px - r, px + r }, new[] { py, py + r, py + r });
                    AddWall(g, true, new[] { px, px - r, px - r }, new[] { py, py - r, py + r });
                    AddWall(g, false, new[] { px, px + r, px + r }, new[] { py, py + r, py - r });
                    AddWall(g, false, new[] { px, px + r, px - r }, new[] { py, py - r, py - r });
                }
                if (i == 0) continue;
                double x0 = pts[i - 1][0], y0 = pts[i - 1][1], x1 = px, y1 = py;
                double dx = x1 - x0, dy = y1 - y0, len = Math.Sqrt(dx * dx + dy * dy);
                if (len < 1e-6) continue;
                double nx = -dy / len * h, ny = dx / len * h;
                if (Mode == 0)
                    AddQuad(g, new[] { x0 + nx, x1 + nx, x1 - nx, x0 - nx }, new[] { y0 + ny, y1 + ny, y1 - ny, y0 - ny });
                else
                {
                    // the two walls of the V, meeting along the stroke's middle
                    bool plusShade = ShadeSide(nx, ny);
                    AddWall(g, plusShade, new[] { x0, x1, x1 + nx, x0 + nx }, new[] { y0, y1, y1 + ny, y0 + ny });
                    AddWall(g, !plusShade, new[] { x0, x1, x1 - nx, x0 - nx }, new[] { y0, y1, y1 - ny, y0 - ny });
                }
            }
        }
        return g;
    }

    // ---------------------------------------------------------------- the TrueType file
    static void U16(List<byte> b, int v) { b.Add((byte)((v >> 8) & 0xFF)); b.Add((byte)(v & 0xFF)); }
    static void U32(List<byte> b, long v) { U16(b, (int)((v >> 16) & 0xFFFF)); U16(b, (int)(v & 0xFFFF)); }
    static void Tag(List<byte> b, string t) { foreach (char c in t) b.Add((byte)c); }
    static void Pad4(List<byte> b) { while (b.Count % 4 != 0) b.Add(0); }
    static uint Sum(List<byte> b)
    {
        uint s = 0;
        for (int i = 0; i < b.Count; i += 4)
        {
            uint v = 0;
            for (int k = 0; k < 4; k++) v = (v << 8) | (i + k < b.Count ? b[i + k] : (byte)0);
            s = unchecked(s + v);
        }
        return s;
    }

    public static string Build(string path) { Stroke = STROKE; Mode = 0; return Write(path, "Handkerquest Runecut"); }

    public static string BuildGrooved(string shadePath, string litPath)
    {
        Stroke = GROOVE;
        Mode = 1; string a = Write(shadePath, "Handkerquest Runecut Shade");
        Mode = 2; string b = Write(litPath, "Handkerquest Runecut Lit");
        Mode = 0; Stroke = STROKE;
        return a + " / " + b;
    }

    static string Write(string path, string family)
    {
        G.Clear();
        Design();
        // glyph order: .notdef, space, then every designed char, then lowercase small caps
        var glyphs = new List<Glyph>();
        var cmap = new SortedDictionary<int, int>();
        var nd = new Glyph { Adv = 500 };
        nd.Contours.Add(new[] { new[] { 60, 0 }, new[] { 60, 780 }, new[] { 440, 780 }, new[] { 440, 0 } });
        nd.Contours.Add(new[] { new[] { 120, 60 }, new[] { 380, 60 }, new[] { 380, 720 }, new[] { 120, 720 } });
        glyphs.Add(nd);
        glyphs.Add(new Glyph { Adv = 300 });
        cmap[32] = 1; cmap[0xA0] = 1;
        var index = new Dictionary<char, int>();
        foreach (var kv in G)
        {
            index[kv.Key] = glyphs.Count;
            cmap[kv.Key] = glyphs.Count;
            glyphs.Add(Make(kv.Value.Key, kv.Value.Value, 1.0));
        }
        for (char c = 'a'; c <= 'z'; c++)
        {
            var up = G[char.ToUpperInvariant(c)];
            index[c] = glyphs.Count;
            cmap[c] = glyphs.Count;
            glyphs.Add(Make(up.Key, up.Value, 0.78));       // small capitals
        }
        for (int i = 0; i < Accented.Length; i++) cmap[Accented[i]] = index[AccentBase[i]];

        // glyf + loca
        var glyf = new List<byte>();
        var loca = new List<long>();
        int xMinAll = 0, yMinAll = 0, xMaxAll = 0, yMaxAll = 0, maxPts = 0, maxCont = 0;
        bool first = true;
        foreach (var g in glyphs)
        {
            loca.Add(glyf.Count);
            if (g.Contours.Count == 0) continue;
            int xMin = int.MaxValue, yMin = int.MaxValue, xMax = int.MinValue, yMax = int.MinValue, n = 0;
            foreach (var c in g.Contours) foreach (var p in c)
            {
                xMin = Math.Min(xMin, p[0]); yMin = Math.Min(yMin, p[1]); xMax = Math.Max(xMax, p[0]); yMax = Math.Max(yMax, p[1]); n++;
            }
            if (first) { xMinAll = xMin; yMinAll = yMin; xMaxAll = xMax; yMaxAll = yMax; first = false; }
            xMinAll = Math.Min(xMinAll, xMin); yMinAll = Math.Min(yMinAll, yMin); xMaxAll = Math.Max(xMaxAll, xMax); yMaxAll = Math.Max(yMaxAll, yMax);
            maxPts = Math.Max(maxPts, n); maxCont = Math.Max(maxCont, g.Contours.Count);
            U16(glyf, g.Contours.Count); U16(glyf, xMin); U16(glyf, yMin); U16(glyf, xMax); U16(glyf, yMax);
            int end = -1;
            foreach (var c in g.Contours) { end += c.Length; U16(glyf, end); }
            U16(glyf, 0);                                               // no instructions
            for (int i = 0; i < n; i++) glyf.Add(0x01);                 // on-curve, 16-bit deltas
            int lx = 0, ly = 0;
            foreach (var c in g.Contours) foreach (var p in c) { U16(glyf, p[0] - lx); lx = p[0]; }
            foreach (var c in g.Contours) foreach (var p in c) { U16(glyf, p[1] - ly); ly = p[1]; }
            Pad4(glyf);
        }
        loca.Add(glyf.Count);
        var locaB = new List<byte>();
        foreach (var o in loca) U32(locaB, o);

        // hmtx (lsb = the outline's left edge)
        var hmtx = new List<byte>();
        int advMax = 0, minLsb = int.MaxValue;
        foreach (var g in glyphs)
        {
            int lsb = 0;
            if (g.Contours.Count > 0) { lsb = int.MaxValue; foreach (var c in g.Contours) foreach (var p in c) lsb = Math.Min(lsb, p[0]); }
            U16(hmtx, g.Adv); U16(hmtx, lsb);
            advMax = Math.Max(advMax, g.Adv); minLsb = Math.Min(minLsb, lsb);
        }

        // head
        var head = new List<byte>();
        U32(head, 0x00010000); U32(head, 0x00010000); U32(head, 0); U32(head, 0x5F0F3CF5);
        U16(head, 0x000B); U16(head, UPM);
        long secs = (long)(new DateTime(2026, 11, 15) - new DateTime(1904, 1, 1)).TotalSeconds;
        U32(head, 0); U32(head, secs); U32(head, 0); U32(head, secs);
        U16(head, xMinAll); U16(head, yMinAll); U16(head, xMaxAll); U16(head, yMaxAll);
        U16(head, 0); U16(head, 8); U16(head, 2); U16(head, 1); U16(head, 0);

        // hhea
        var hhea = new List<byte>();
        U32(hhea, 0x00010000); U16(hhea, ASC); U16(hhea, -DESC); U16(hhea, 0);
        U16(hhea, advMax); U16(hhea, minLsb); U16(hhea, 0); U16(hhea, xMaxAll);
        U16(hhea, 1); U16(hhea, 0); U16(hhea, 0);
        for (int i = 0; i < 4; i++) U16(hhea, 0);
        U16(hhea, 0); U16(hhea, glyphs.Count);

        // maxp
        var maxp = new List<byte>();
        U32(maxp, 0x00010000); U16(maxp, glyphs.Count); U16(maxp, maxPts); U16(maxp, maxCont);
        U16(maxp, 0); U16(maxp, 0); U16(maxp, 2);
        for (int i = 0; i < 8; i++) U16(maxp, 0);

        // OS/2 (version 4)
        var os2 = new List<byte>();
        U16(os2, 4); U16(os2, 520); U16(os2, 700); U16(os2, 5); U16(os2, 0);
        U16(os2, 650); U16(os2, 600); U16(os2, 0); U16(os2, 75);          // subscript
        U16(os2, 650); U16(os2, 600); U16(os2, 0); U16(os2, 350);         // superscript
        U16(os2, 60); U16(os2, 300); U16(os2, 0);                         // strikeout, family class
        for (int i = 0; i < 10; i++) os2.Add(0);                           // panose
        U32(os2, 3); U32(os2, 0); U32(os2, 0); U32(os2, 0);               // Basic Latin, Latin-1
        Tag(os2, "HKQ ");
        U16(os2, 0x0040);                                                 // regular
        int firstCp = 0xFFFF, lastCp = 0;
        foreach (var k in cmap.Keys) { firstCp = Math.Min(firstCp, k); lastCp = Math.Max(lastCp, k); }
        U16(os2, firstCp); U16(os2, Math.Min(lastCp, 0xFFFF));
        U16(os2, ASC); U16(os2, -DESC); U16(os2, 0); U16(os2, ASC); U16(os2, DESC);
        U32(os2, 1); U32(os2, 0);                                         // code page: Latin 1
        U16(os2, (int)(10 * U * 0.78)); U16(os2, (int)(10 * U)); U16(os2, 0); U16(os2, 32); U16(os2, 1);

        // cmap: format 4, one segment per character (+ the end marker)
        var sub = new List<byte>();
        var codes = new List<int>(cmap.Keys);
        int segs = codes.Count + 1;
        int sr = 2; int es = 0; while (sr * 2 <= segs * 2) { sr *= 2; es++; }
        sr = 1; es = 0; while (sr * 2 <= segs) { sr *= 2; es++; } sr *= 2;
        U16(sub, 4); U16(sub, 16 + segs * 8); U16(sub, 0);
        U16(sub, segs * 2); U16(sub, sr); U16(sub, es); U16(sub, segs * 2 - sr);
        foreach (var c in codes) U16(sub, c); U16(sub, 0xFFFF);
        U16(sub, 0);
        foreach (var c in codes) U16(sub, c); U16(sub, 0xFFFF);
        foreach (var c in codes) U16(sub, (cmap[c] - c) & 0xFFFF); U16(sub, 1);
        foreach (var c in codes) U16(sub, 0); U16(sub, 0);
        var cmapT = new List<byte>();
        U16(cmapT, 0); U16(cmapT, 2);
        U16(cmapT, 0); U16(cmapT, 3); U32(cmapT, 4 + 8 * 2);
        U16(cmapT, 3); U16(cmapT, 1); U32(cmapT, 4 + 8 * 2);
        cmapT.AddRange(sub);

        // name
        string ps = family.Replace(" ", "");
        string[] names = { null, family, "Regular", family + " Regular 1.000", family, "Version 1.000", ps + "-Regular" };
        var recs = new List<byte>(); var strs = new List<byte>();
        int count = 0;
        for (int id = 1; id < names.Length; id++)
        {
            byte[] s = Encoding.BigEndianUnicode.GetBytes(names[id]);
            U16(recs, 3); U16(recs, 1); U16(recs, 0x409); U16(recs, id); U16(recs, s.Length); U16(recs, strs.Count);
            strs.AddRange(s); count++;
        }
        var name = new List<byte>();
        U16(name, 0); U16(name, count); U16(name, 6 + count * 12);
        name.AddRange(recs); name.AddRange(strs);

        // post (version 3: no glyph names)
        var post = new List<byte>();
        U32(post, 0x00030000); U32(post, 0); U16(post, -100); U16(post, 50);
        for (int i = 0; i < 5; i++) U32(post, 0);

        // the file: table directory sorted by tag, each table 4-byte aligned, then the head checksum adjustment
        var tables = new SortedDictionary<string, List<byte>>(StringComparer.Ordinal)
        {
            { "OS/2", os2 }, { "cmap", cmapT }, { "glyf", glyf }, { "head", head }, { "hhea", hhea },
            { "hmtx", hmtx }, { "loca", locaB }, { "maxp", maxp }, { "name", name }, { "post", post },
        };
        int nt = tables.Count, srT = 1, esT = 0;
        while (srT * 2 <= nt) { srT *= 2; esT++; }
        srT *= 16;
        var file = new List<byte>();
        U32(file, 0x00010000); U16(file, nt); U16(file, srT); U16(file, esT); U16(file, nt * 16 - srT);
        int offset = 12 + nt * 16;
        var dir = new List<byte>(); var body = new List<byte>();
        int headOffset = 0;
        foreach (var kv in tables)
        {
            var t = new List<byte>(kv.Value);
            int len = t.Count;
            Pad4(t);
            Tag(dir, kv.Key); U32(dir, Sum(t)); U32(dir, offset + body.Count); U32(dir, len);
            if (kv.Key == "head") headOffset = offset + body.Count;
            body.AddRange(t);
        }
        file.AddRange(dir); file.AddRange(body);
        uint adj = unchecked(0xB1B0AFBA - Sum(file));
        file[headOffset + 8] = (byte)(adj >> 24); file[headOffset + 9] = (byte)(adj >> 16);
        file[headOffset + 10] = (byte)(adj >> 8); file[headOffset + 11] = (byte)adj;
        File.WriteAllBytes(path, file.ToArray());
        return string.Format("{0} glyphs, {1} characters, {2} bytes", glyphs.Count, cmap.Count, file.Count);
    }
}
