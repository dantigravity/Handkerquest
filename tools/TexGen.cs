using System;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;

// Procedural textures for the Handkerquest tally: crumpled paper, a torn rag, a flat stone, a bark slab,
// a pipe-weed leaf, a piece of soft hide, the arcane haze and rune circle, chalk grain.
public static class TexGen
{
    // ---------------------------------------------------------------- noise
    static int Seed = 1337;
    static double Hash(int x, int y, int s)
    {
        unchecked
        {
            int h = x * 374761393 + y * 668265263 + s * 1442695041 + Seed * 2147483647;
            h = (h ^ (h >> 13)) * 1274126177;
            h ^= h >> 16;
            return (h & 0x7fffffff) / (double)0x7fffffff;
        }
    }
    static double Smooth(double t) { return t * t * (3 - 2 * t); }
    static double Value(double x, double y, int s)
    {
        int xi = (int)Math.Floor(x), yi = (int)Math.Floor(y);
        double xf = x - xi, yf = y - yi;
        double a = Hash(xi, yi, s), b = Hash(xi + 1, yi, s), c = Hash(xi, yi + 1, s), d = Hash(xi + 1, yi + 1, s);
        double u = Smooth(xf), v = Smooth(yf);
        return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v;
    }
    static double Fbm(double x, double y, int oct, int s)
    {
        double sum = 0, amp = 0.5, f = 1, norm = 0;
        for (int i = 0; i < oct; i++) { sum += amp * Value(x * f, y * f, s + i * 17); norm += amp; amp *= 0.5; f *= 2; }
        return sum / norm;
    }
    static double Clamp(double v, double a, double b) { return v < a ? a : (v > b ? b : v); }

    // ---------------------------------------------------------------- output
    static void Save(double[,,] img, string tgaPath, string pngPath)
    {
        int w = img.GetLength(0), h = img.GetLength(1);
        using (var fs = new FileStream(tgaPath, FileMode.Create))
        using (var bw = new BinaryWriter(fs))
        {
            bw.Write((byte)0); bw.Write((byte)0); bw.Write((byte)2);       // id length, no colour map, true colour
            bw.Write(new byte[5]);                                          // colour map spec
            bw.Write((short)0); bw.Write((short)0);                         // origin
            bw.Write((short)w); bw.Write((short)h);
            bw.Write((byte)32); bw.Write((byte)0x28);                       // 32 bpp, 8 alpha bits, top-left origin
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    bw.Write((byte)(Clamp(img[x, y, 2], 0, 1) * 255 + 0.5));
                    bw.Write((byte)(Clamp(img[x, y, 1], 0, 1) * 255 + 0.5));
                    bw.Write((byte)(Clamp(img[x, y, 0], 0, 1) * 255 + 0.5));
                    bw.Write((byte)(Clamp(img[x, y, 3], 0, 1) * 255 + 0.5));
                }
        }
        // preview on a dark green "grass" backdrop
        using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        {
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++)
                {
                    double a = Clamp(img[x, y, 3], 0, 1);
                    double br = 0.16, bgc = 0.24, bb = 0.12;
                    int r = (int)(255 * (img[x, y, 0] * a + br * (1 - a)));
                    int g = (int)(255 * (img[x, y, 1] * a + bgc * (1 - a)));
                    int b = (int)(255 * (img[x, y, 2] * a + bb * (1 - a)));
                    bmp.SetPixel(x, y, Color.FromArgb(255, Math.Min(255, Math.Max(0, r)), Math.Min(255, Math.Max(0, g)), Math.Min(255, Math.Max(0, b))));
                }
            bmp.Save(pngPath, ImageFormat.Png);
        }
    }

    // ---------------------------------------------------------------- crumpled paper
    public static void Crumpled(string tga, string png, int size, int seed)
    {
        Seed = seed;
        int W = size, H = size;
        var hgt = new double[W, H];
        var rnd = new Random(seed);
        // creases: V-shaped folds along random lines, each fading out along its length. A few long
        // ones (the first big crush) and many short ones (the ball being squeezed tighter).
        int n = 240;
        var cx = new double[n]; var cy = new double[n]; var nx = new double[n]; var ny = new double[n];
        var amp = new double[n]; var len = new double[n];
        for (int i = 0; i < n; i++)
        {
            cx[i] = rnd.NextDouble() * W; cy[i] = rnd.NextDouble() * H;
            double t = rnd.NextDouble() * Math.PI;
            nx[i] = Math.Cos(t); ny[i] = Math.Sin(t);
            bool big = i < 18;
            amp[i] = (rnd.NextDouble() < 0.5 ? -1 : 1) * (0.35 + rnd.NextDouble() * 0.65) * (big ? 1.6 : 1.0);
            len[i] = (big ? (0.30 + rnd.NextDouble() * 0.40) : (0.05 + rnd.NextDouble() * 0.16)) * W;
        }
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                double s = 0;
                for (int i = 0; i < n; i++)
                {
                    double dx = x - cx[i], dy = y - cy[i];
                    double t = -dx * ny[i] + dy * nx[i];           // along the crease
                    if (Math.Abs(t) > len[i] * 2.2) continue;
                    double d = dx * nx[i] + dy * ny[i];            // across it
                    double fall = Math.Exp(-(t * t) / (len[i] * len[i]));
                    double v = Math.Abs(d);
                    v = v < 28 ? v : 28 + (v - 28) * 0.1;           // each fold flattens out a little way off
                    s += amp[i] * v * fall * 0.13;
                }
                s += (Fbm(x / 70.0, y / 70.0, 4, 5) - 0.5) * 5.0;    // broad buckling
                hgt[x, y] = s;
            }

        var img = new double[W, H, 4];
        double lx = -0.55, ly = -0.60, lz = 0.58;                   // light from the top-left
        double ll = Math.Sqrt(lx * lx + ly * ly + lz * lz); lx /= ll; ly /= ll; lz /= ll;
        int margin = (int)(W * 0.035);
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                int x0 = Math.Max(0, x - 1), x1 = Math.Min(W - 1, x + 1), y0 = Math.Max(0, y - 1), y1 = Math.Min(H - 1, y + 1);
                double gx = (hgt[x1, y] - hgt[x0, y]) * 0.5, gy = (hgt[x, y1] - hgt[x, y0]) * 0.5;
                double nX = -gx, nY = -gy, nZ = 1.0;
                double nl = Math.Sqrt(nX * nX + nY * nY + nZ * nZ); nX /= nl; nY /= nl; nZ /= nl;
                double diff = Clamp(nX * lx + nY * ly + nZ * lz, 0, 1);
                double spec = Math.Pow(Clamp(nZ * 0.9 + diff * 0.1, 0, 1), 40) * 0.04;
                double fiber = (Value(x * 0.9, y * 0.35, 91) - 0.5) * 0.035 + (Value(x * 2.1, y * 2.1, 92) - 0.5) * 0.02;
                // crease lines: where the surface bends sharply the paper fibres broke and show darker
                double lap = (hgt[x0, y] + hgt[x1, y] + hgt[x, y0] + hgt[x, y1] - 4 * hgt[x, y]);
                double crease = Clamp(Math.Abs(lap) * 0.22, 0, 0.09);
                double tone = 0.79 + 0.25 * diff + spec + fiber - crease;
                double mott = (Fbm(x / 40.0, y / 40.0, 4, 33) - 0.5) * 0.05;   // uneven paper colour
                img[x, y, 0] = (0.955 + mott) * tone;
                img[x, y, 1] = (0.935 + mott) * tone;
                img[x, y, 2] = (0.880 + mott * 1.2) * tone;

                // outline: a cut sheet whose edges were pushed out of true by the crumpling
                double ex = Math.Min(x, W - 1 - x), ey = Math.Min(y, H - 1 - y);
                // the edges were bent with the creases: a slow wave plus kinks where creases meet the edge
                double wob = (Fbm(x / 120.0, y / 120.0, 3, 71) - 0.5) * 16.0 + (Fbm(x / 22.0, y / 22.0, 2, 72) - 0.5) * 4.0;
                double inside = Math.Min(ex, ey) - margin + wob + hgt[x, y] * 0.05;
                double a = Clamp(inside / 1.3, 0, 1);
                // edges a touch darker (handled, dusty)
                double edgeDark = Clamp(1 - inside / 14.0, 0, 1) * 0.08;
                for (int c = 0; c < 3; c++) img[x, y, c] *= 1 - edgeDark;
                img[x, y, 3] = a;
            }
        Save(img, tga, png);
    }

    // ---------------------------------------------------------------- torn rag
    // A strip torn off a shirt: unbleached cotton, plain weave, soft wrinkles, grime. Torn on three
    // sides (irregular, fibrous, loose threads) and the shirt's folded hem along the bottom.
    public static void Rag(string tga, string png, int size, int seed)
    {
        Seed = seed;
        int W = size, H = size;
        var img = new double[W, H, 4];
        double p = 4.0;                                   // thread pitch in pixels

        // the torn outline: each edge is a slow irregular line (where the tear wandered) plus jags
        Func<double, int, double, double> tear = (t, s, amp) =>
            (Fbm(t / 150.0, s * 0.37, 3, s) - 0.5) * amp * 2.2 +      // long wander
            (Fbm(t / 30.0, s * 0.53, 3, s + 7) - 0.5) * amp +         // jags
            (Value(t / 5.0, s * 0.71, s + 9) - 0.5) * amp * 0.25;     // ragged fibres
        double m = W * 0.06;

        double lx = -0.5, ly = -0.65, lz = 0.57;
        double ll = Math.Sqrt(lx * lx + ly * ly + lz * lz); lx /= ll; ly /= ll; lz /= ll;
        Func<double, double, double> wrinkle = (x, y) =>
            (Fbm(x / 130.0, y / 130.0, 4, 401) - 0.5) * 16.0 +
            Math.Sin((x * 0.55 + y) / 40.0 + Fbm(x / 70.0, y / 70.0, 2, 402) * 5) * 1.4 +
            Math.Sin((x - y * 0.3) / 23.0 + Fbm(x / 50.0, y / 50.0, 2, 403) * 6) * 0.6;

        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                // ---- weave: threads wander a little, so the grid isn't ruler-straight
                double wx = x + (Fbm(x / 60.0, y / 60.0, 2, 501) - 0.5) * 3.0;
                double wy = y + (Fbm(x / 60.0, y / 60.0, 2, 502) - 0.5) * 3.0;
                int i = (int)Math.Floor(wx / p), j = (int)Math.Floor(wy / p);
                double fx = wx / p - i, fy = wy / p - j;
                bool warpUp = ((i + j) & 1) == 0;
                double warpProfile = Math.Sin(Math.PI * fx), weftProfile = Math.Sin(Math.PI * fy);
                // thick and thin threads, and slubs along each one
                double warpShade = 0.95 + 0.07 * Hash(i, 0, 11) + 0.06 * (Value(i * 3.1, wy / 19.0, 12) - 0.5);
                double weftShade = 0.95 + 0.07 * Hash(0, j, 13) + 0.06 * (Value(wx / 19.0, j * 3.1, 14) - 0.5);
                double thread = warpUp ? 0.91 + 0.10 * warpProfile * warpShade : 0.91 + 0.10 * weftProfile * weftShade;
                double gap = Math.Min(Math.Min(fx, 1 - fx), Math.Min(fy, 1 - fy));
                if (gap < 0.10) thread *= 0.955;
                double fuzz = (Value(x * 1.3, y * 1.3, 15) - 0.5) * 0.045 + (Value(x * 0.4, y * 0.15, 16) - 0.5) * 0.03;

                // ---- wrinkles
                double h0 = wrinkle(x, y), hx = wrinkle(x + 1, y), hy = wrinkle(x, y + 1);
                double nX = -(hx - h0) * 1.1, nY = -(hy - h0) * 1.1, nZ = 1;
                double nl = Math.Sqrt(nX * nX + nY * nY + nZ * nZ); nX /= nl; nY /= nl; nZ /= nl;
                double diff = Clamp(nX * lx + nY * ly + nZ * lz, 0, 1);
                double light = 0.70 + 0.38 * diff;

                // ---- colour: unbleached cotton, grubby, with a couple of old stains
                double mott = (Fbm(x / 55.0, y / 55.0, 4, 21) - 0.5) * 0.07;
                double stain = Clamp((Fbm(x / 80.0, y / 80.0, 4, 23) - 0.64) * 3.5, 0, 1) * 0.08;
                double tone = thread * light + fuzz + mott;
                double r = 0.915 * tone - stain * 0.55, g = 0.875 * tone - stain * 0.72, b = 0.775 * tone - stain * 0.95;

                // ---- outline
                double dTop = y - (m + tear(x, 31, 14) + 6);
                double dLeft = x - (m + tear(y, 33, 13) + 2);
                double dRight = (W - m - tear(y, 35, 13)) - x;
                double dBot = (H - m * 0.7 + (Fbm(x / 140.0, 2.5, 2, 37) - 0.5) * 8) - y;   // the hem: gently curved
                // a corner torn away diagonally at the top-left
                double dCorner = (x + y) - (m * 2 + 26 + tear(x - y, 39, 8));
                double inside = Math.Min(Math.Min(Math.Min(dTop, dLeft), Math.Min(dRight, dBot)), dCorner);
                double a = Clamp(inside / 1.1, 0, 1);

                // fibrous tear: the last few pixels of a torn edge are wispy
                double tornIn = Math.Min(Math.Min(Math.Min(dTop, dLeft), dRight), dCorner);
                if (tornIn > 0 && tornIn < 4) a *= 0.55 + 0.45 * Value(x * 0.9, y * 0.9, 48);

                // loose threads: a few per edge, wavy, of very different lengths, darker than the cloth
                if (inside <= 0 && a < 0.5)
                {
                    double best = 0;
                    if (dTop <= 0 && dLeft > -1 && dRight > -1 && dCorner > -1)
                    {
                        int col = (int)Math.Floor((x + Math.Sin(y * 0.35 + x) * 1.2) / p);
                        double lenT = Hash(col, 2, 42) < 0.28 ? 4 + 20 * Math.Pow(Hash(col, 3, 43), 2) : 0;
                        double cxT = col * p + 1.5 + Math.Sin((-dTop) * 0.4 + col) * 1.2;
                        if (-dTop < lenT && Math.Abs(x - cxT) < 0.7) best = 0.9 - 0.5 * (-dTop / lenT);
                    }
                    if ((dLeft <= 0 || dRight <= 0) && dTop > -1 && dBot > 3 && dCorner > -1)
                    {
                        double out_ = dLeft <= 0 ? -dLeft : -dRight;
                        int row = (int)Math.Floor(y / p);
                        double lenS = Hash(row, dLeft <= 0 ? 4 : 6, 44) < 0.25 ? 4 + 18 * Math.Pow(Hash(row, 5, 45), 2) : 0;
                        double cyS = row * p + 1.5 + Math.Sin(out_ * 0.4 + row) * 1.2;
                        if (out_ < lenS && Math.Abs(y - cyS) < 0.7) best = Math.Max(best, 0.9 - 0.5 * (out_ / lenS));
                    }
                    if (best > 0) { a = best; r = 0.80; g = 0.76; b = 0.66; }
                }

                // torn edges: greyer, and the weave opens up near the tear
                if (tornIn > 0 && tornIn < 12)
                {
                    double k = 1 - tornIn / 12;
                    r *= 1 - 0.12 * k; g *= 1 - 0.13 * k; b *= 1 - 0.15 * k;
                    if (gap < 0.16 && Hash(x, y, 47) < 0.45 * k) a *= 0.4;
                }

                // the shirt's hem along the bottom: a folded-over band
                if (dBot > 0 && dBot < 24 && inside > 0)
                {
                    if (dBot > 21) { r *= 0.84; g *= 0.83; b *= 0.81; }          // fold line
                    else if (dBot < 3) { r *= 0.88; g *= 0.87; b *= 0.85; }      // rolled edge
                    else { r *= 0.975; g *= 0.97; b *= 0.965; }                   // doubled cloth
                }

                img[x, y, 0] = r; img[x, y, 1] = g; img[x, y, 2] = b; img[x, y, 3] = a;
            }
        Save(img, tga, png);
    }

    // ---------------------------------------------------------------- cured pipe-weed leaf
    // A broad tobacco leaf, air-cured to gold and brown: stem stub at the left, tip at the right,
    // a pale flattened midrib, lateral veins sweeping toward the tip, a fine network of veinlets
    // puckering the leaf into little cells, crinkles from drying, darker curing spots, wavy edges
    // with a couple of dry splits.
    static void Cell(double x, double y, int s, out double f1, out double f2)
    {
        int xi = (int)Math.Floor(x), yi = (int)Math.Floor(y);
        f1 = 9; f2 = 9;
        for (int j = -1; j <= 1; j++)
            for (int i = -1; i <= 1; i++)
            {
                double px = xi + i + Hash(xi + i, yi + j, s), py = yi + j + Hash(xi + i, yi + j, s + 1);
                double d = Math.Sqrt((px - x) * (px - x) + (py - y) * (py - y));
                if (d < f1) { f2 = f1; f1 = d; } else if (d < f2) f2 = d;
            }
    }
    public static void Leaf(string tga, string png, int size, int seed)
    {
        Seed = seed;
        int W = size, H = size;
        double x0 = W * 0.035, x1 = W * 0.975;             // stem end, tip
        double yc = H * 0.50;
        var hgt = new double[W, H];
        var col = new double[W, H, 3];
        var alpha = new double[W, H];
        var rnd = new Random(seed);
        int nVein = 9;
        var vu = new double[nVein];
        for (int i = 0; i < nVein; i++) vu[i] = 0.06 + i * 0.105 + (rnd.NextDouble() - 0.5) * 0.03;

        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                double u = (x - x0) / (x1 - x0);           // 0 at the stem, 1 at the tip
                // the midrib bows gently
                double ym = yc + Math.Sin(u * Math.PI) * H * 0.025 + (Fbm(u * 3, 0.5, 2, 301) - 0.5) * 8;
                double dy = y - ym, ady = Math.Abs(dy);
                // broad ovate outline: widest a third of the way along, drawn to a point at the tip
                double uu = Clamp(u, 0, 1);
                // rounded base, widest at 38%, then drawn out to a pointed tip
                double half;
                if (u < 0) half = 0;                                                    // only the stem out here
                else if (uu < 0.42) { double tb = (0.42 - uu) / 0.43; half = Math.Sqrt(Math.Max(0, 1 - Math.Pow(tb, 2.6))); }
                else { double tt = (uu - 0.42) / 0.58; half = Math.Pow(Math.Max(0, 1 - Math.Pow(tt, 2.3)), 1.15); }
                half *= H * 0.445;
                half *= 1 + (Fbm(x / 40.0, dy > 0 ? 3.0 : 7.0, 3, 302) - 0.5) * 0.10;   // wavy, a little uneven
                half += (Value(x / 7.0, dy > 0 ? 11.0 : 13.0, 303) - 0.5) * 3.0;          // crinkled rim
                // dry splits running in from the edge along a vein
                for (int k = 0; k < 1; k++)
                {
                    double su = k == 0 ? 0.64 : 0.30, side = k == 0 ? -1 : 1;     // upper edge: clear of the page-turn corner
                    if (dy * side > 0)
                    {
                        double xv = x0 + su * (x1 - x0) + ady * 0.55;
                        double depthIn = H * (k == 0 ? 0.08 : 0.09);
                        double open = ady - (half - depthIn);                           // the split opens toward the edge
                        if (open > 0 && Math.Abs(x - xv) < 0.8 + open * 0.16) half = Math.Min(half, ady - 0.5);
                    }
                }
                double inside = half - ady;
                // stem stub sticking out at the left
                double stem = (u < 0.02 && u > -0.035) ? 5.5 - ady : -9;
                double a = Clamp(Math.Max(inside, stem) / 1.2, 0, 1);
                if (u < -0.035 || u > 1) a = 0;
                alpha[x, y] = a;

                // ---- relief
                double h = 0;
                double rib = Math.Max(0, 1 - ady / (11.0 * (1 - uu * 0.8) + 1.5));
                h += Math.Sqrt(rib) * 3.6;                                                   // raised midrib, thick at the stem
                // lateral veins: leave the midrib at an angle and sweep toward the tip
                double vein = 0;
                for (int vi = 0; vi < nVein; vi++)
                {
                    // alternate: the veins on the lower side sit half a step further along
                    double v0 = vu[vi] + (dy > 0 ? 0.05 : 0);
                    double xv = x0 + v0 * (x1 - x0) + ady * 0.40 + ady * ady / H * 1.9;
                    double reach = Clamp(ady / Math.Max(1, half), 0, 1);
                    double w = 2.4 * (1 - reach) + 0.5;
                    double dist = Math.Abs(x - xv) * 0.7;
                    if (dist < w * 2) vein = Math.Max(vein, (1 - dist / (w * 2)) * Clamp((1 - reach) * 4, 0, 1));
                }
                h += vein * 1.3;
                // veinlets: a cell network that puckers the leaf between them
                double f1, f2;
                Cell(x / 13.0 + Fbm(x / 30.0, y / 30.0, 2, 304), y / 13.0, 305, out f1, out f2);
                double net = Clamp(1 - (f2 - f1) / 0.12, 0, 1);
                h += net * 0.55 + Math.Sqrt(Clamp(f1, 0, 1)) * -0.35;
                // drying crinkles
                h += (Fbm(x / 45.0, y / 18.0, 4, 306) - 0.5) * 7.0 + (Ridged(x / 25.0, y / 12.0, 3, 307) - 0.5) * 2.5;
                // the edges curl up a little
                h += Clamp(1 - inside / 18.0, 0, 1) * 3.0;
                hgt[x, y] = h;

                // ---- colour: cured gold to brown, darker patches and spots, paler veins
                double m = Fbm(x / 70.0, y / 70.0, 4, 310);
                double r = 0.66, g = 0.46, b = 0.22;                                       // golden
                double dark = Clamp((m - 0.42) * 2.2, 0, 1);
                r += (0.47 - r) * dark; g += (0.29 - g) * dark; b += (0.12 - b) * dark;   // to brown
                double green = Clamp((Fbm(x / 90.0, y / 90.0, 3, 311) - 0.70) * 4, 0, 0.35);
                r += (0.52 - r) * green; g += (0.47 - g) * green; b += (0.22 - b) * green; // a trace of unripe green
                double spots = Clamp((Fbm(x / 9.0, y / 9.0, 3, 312) - 0.68) * 5, 0, 1) * Clamp((m - 0.35) * 3, 0, 1);
                r *= 1 - 0.30 * spots; g *= 1 - 0.36 * spots; b *= 1 - 0.40 * spots;    // curing spots
                double pale = Math.Max(rib, vein * 0.75);
                r += (0.80 - r) * pale * 0.55; g += (0.64 - g) * pale * 0.55; b += (0.38 - b) * pale * 0.55;
                r += net * 0.025; g += net * 0.02;
                // edges browner and drier
                double edge = Clamp(1 - inside / 14.0, 0, 1);
                r *= 1 - 0.22 * edge; g *= 1 - 0.30 * edge; b *= 1 - 0.35 * edge;
                if (stem > 0 && inside <= 0) { r = 0.55; g = 0.40; b = 0.22; }
                col[x, y, 0] = r; col[x, y, 1] = g; col[x, y, 2] = b;
            }

        double lx, ly, lz; Light(out lx, out ly, out lz);
        var img = new double[W, H, 4];
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                int xa = Math.Max(0, x - 1), xb = Math.Min(W - 1, x + 1), ya = Math.Max(0, y - 1), yb = Math.Min(H - 1, y + 1);
                double gx = (hgt[xb, y] - hgt[xa, y]) * 0.5, gy = (hgt[x, yb] - hgt[x, ya]) * 0.5;
                double nX = -gx * 1.3, nY = -gy * 1.3, nZ = 1;
                double nl = Math.Sqrt(nX * nX + nY * nY + nZ * nZ); nX /= nl; nY /= nl; nZ /= nl;
                double diff = Clamp(nX * lx + nY * ly + nZ * lz, 0, 1);
                double sheen = Math.Pow(diff, 14) * 0.08;                                  // the leaf''s oils
                double tone = 0.50 + 0.62 * diff;
                for (int c = 0; c < 3; c++) img[x, y, c] = col[x, y, c] * tone + sheen;
                img[x, y, 3] = alpha[x, y];
            }
        Save(img, tga, png);
    }

    // ---------------------------------------------------------------- soft hide (the "Etched leather" look)
    // A rough-cut piece of supple tan leather, the kind a jerkin or a pair of breeches is cut from: a
    // hide-like outline (lobes where the legs were, knife-cut facets, a nick or two), soft drape folds,
    // a fine grain with pores, a darker band down the spine and paler belly towards the edges. The cut
    // edge shows the fibrous flesh side; no tooling, no stitching. The list is pressed into it.
    public static void Leather(string tga, string png, int size, int seed)
    {
        Seed = seed;
        int W = size, H = size;
        double cx0 = W * 0.5, cy0 = H * 0.5, ax = W * 0.455, ay = H * 0.425;
        double R = Math.Min(ax, ay);
        var rnd = new Random(seed);
        // lobes where the legs were (angle, height, width); y points down, so +45 deg is bottom-right
        double[] lobeA = { -2.30, -0.80, 2.35, 0.78 }, lobeH = { 0.19, 0.15, 0.17, 0.08 }, lobeW = { 0.19, 0.17, 0.21, 0.17 };
        for (int i = 0; i < 4; i++) lobeA[i] += (rnd.NextDouble() - 0.5) * 0.15;
        // knife cuts: the outline is a run of short straight-ish strokes
        int nCut = 46;
        var cut = new double[nCut];
        for (int i = 0; i < nCut; i++) cut[i] = (rnd.NextDouble() - 0.5) * 0.026;
        // two small nicks in the edge
        double[] nickA = { -1.55 + (rnd.NextDouble() - 0.5) * 0.3, 2.95 + (rnd.NextDouble() - 0.5) * 0.3 };
        // soft drape folds: rounded ridges and troughs along random lines, fading out along their length
        int nFold = 9;
        var fold = new double[nFold * 6];
        for (int i = 0; i < nFold; i++)
        {
            double t = rnd.NextDouble() * Math.PI;
            fold[i * 6] = W * (0.1 + rnd.NextDouble() * 0.8); fold[i * 6 + 1] = H * (0.1 + rnd.NextDouble() * 0.8);
            fold[i * 6 + 2] = Math.Cos(t); fold[i * 6 + 3] = Math.Sin(t);
            fold[i * 6 + 4] = (rnd.NextDouble() < 0.6 ? 1 : -1) * (2.6 + rnd.NextDouble() * 3.0);   // height
            fold[i * 6 + 5] = W * (0.18 + rnd.NextDouble() * 0.30);                                   // length
        }
        // a few healed scratches across the grain
        int nScr = 4;
        var scr = new double[nScr * 4];
        for (int i = 0; i < nScr; i++)
        {
            double sx = W * (0.25 + rnd.NextDouble() * 0.5), sy = H * (0.25 + rnd.NextDouble() * 0.5);
            double t = rnd.NextDouble() * Math.PI, l = W * (0.04 + rnd.NextDouble() * 0.07);
            scr[i * 4] = sx; scr[i * 4 + 1] = sy; scr[i * 4 + 2] = sx + Math.Cos(t) * l; scr[i * 4 + 3] = sy + Math.Sin(t) * l;
        }

        var hgt = new double[W, H];
        var col = new double[W, H, 3];
        var alpha = new double[W, H];
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                double dx = (x - cx0) / ax, dy = (y - cy0) / ay;
                double th = Math.Atan2(dy, dx), ct = Math.Cos(th), st = Math.Sin(th);
                double q = Math.Pow(Math.Pow(Math.Abs(dx), 3.2) + Math.Pow(Math.Abs(dy), 3.2), 1.0 / 3.2);
                double rim = 1.0 + (Fbm(ct * 1.1 + 5, st * 1.1 + 5, 3, 401) - 0.5) * 0.14   // the hide wanders
                    + (Fbm(ct * 4.0 + 9, st * 4.0 + 9, 2, 402) - 0.5) * 0.08;               // and the knife with it
                for (int i = 0; i < 4; i++)
                {
                    double da = Math.Atan2(Math.Sin(th - lobeA[i]), Math.Cos(th - lobeA[i]));
                    rim += lobeH[i] * Math.Exp(-da * da / (2 * lobeW[i] * lobeW[i]));
                    rim -= 0.06 * Math.Exp(-Math.Pow(da - lobeW[i] * 2.2, 2) / 0.03);        // the hollow beside a leg
                }
                double ci = (th + Math.PI) / (2 * Math.PI) * nCut;
                int c0 = (int)Math.Floor(ci); double cf = ci - c0;
                rim += cut[c0 % nCut] * (1 - cf) + cut[(c0 + 1) % nCut] * cf;                  // straight knife strokes
                for (int i = 0; i < 2; i++)
                {
                    double da = Math.Atan2(Math.Sin(th - nickA[i]), Math.Cos(th - nickA[i]));
                    rim -= Math.Max(0, 0.035 - Math.Abs(da) * 0.9);                            // a V nick
                }
                q /= rim;
                double inside = (1 - q) * R;                       // ~ pixels in from the cut edge
                double fz = Value(x * 0.8, y * 0.8, 409);
                alpha[x, y] = Clamp((inside + (fz - 0.5) * 1.6) / 1.4, 0, 1);              // a slightly fuzzy cut

                // ---- relief: soft drape folds, a fine grain with pores, the edge curling a touch
                double h = 0;
                h += (Fbm(x / 150.0, y / 150.0, 3, 405) - 0.5) * 10.0;                       // the hide's swell
                double crease = 0;
                for (int i = 0; i < nFold; i++)
                {
                    double ddx = x - fold[i * 6], ddy = y - fold[i * 6 + 1];
                    double along = ddx * fold[i * 6 + 2] + ddy * fold[i * 6 + 3];
                    double across = -ddx * fold[i * 6 + 3] + ddy * fold[i * 6 + 2] + (Fbm(along / 60.0, i * 3.7, 2, 406) - 0.5) * 30;
                    double wdt = 7 + 7 * Value(along / 80.0, i * 5.3, 407);
                    double fl = Math.Exp(-along * along / (fold[i * 6 + 5] * fold[i * 6 + 5]));
                    double v = fold[i * 6 + 4] * Math.Exp(-across * across / (2 * wdt * wdt)) * fl;
                    h += v; crease = Math.Max(crease, Math.Abs(v) / 5.6);
                }
                h += (Ridged(x / 110.0, y / 80.0, 2, 413) - 0.6) * 1.6;                     // and gentle buckling
                h += (Fbm(x / 35.0, y / 35.0, 3, 408) - 0.5) * 1.4;                          // supple, a bit lumpy
                double f1, f2;
                Cell(x / 2.6 + Fbm(x / 30.0, y / 30.0, 2, 403), y / 2.6, 404, out f1, out f2);
                double grain = Clamp(1 - (f2 - f1) / 0.16, 0, 1);                            // fine grain lines
                h -= grain * 0.22;
                double pore = Hash(x, y, 420) < 0.005 ? 0.6 + 0.4 * Hash(x, y, 422) : 0;                               // pores
                h -= pore * 0.3;
                double scar = 0;
                for (int i = 0; i < nScr; i++)
                {
                    double d = SegDist(x, y, scr[i * 4], scr[i * 4 + 1], scr[i * 4 + 2], scr[i * 4 + 3]);
                    scar = Math.Max(scar, Clamp(1 - d / 1.4, 0, 1) * (0.5 + 0.5 * Value(x / 6.0, y / 6.0, 421 + i)));
                }
                h -= scar * 0.35;
                h += Clamp(1 - inside / 14.0, 0, 1) * (0.6 + 1.6 * Fbm(x / 25.0, y / 25.0, 2, 414));   // the edge lifts here and there
                hgt[x, y] = h;

                // ---- colour: tan, darker down the spine, paler belly, mottled, darker in the folds
                double m = Fbm(x / 70.0, y / 70.0, 4, 410);
                double r = 0.78 + (m - 0.5) * 0.10, g = 0.60 + (m - 0.5) * 0.08, b = 0.41 + (m - 0.5) * 0.06;
                double spineY = H * 0.47 + (Fbm(x / 160.0, 0.5, 2, 412) - 0.5) * H * 0.10;
                double spine = Math.Exp(-Math.Pow((y - spineY) / (H * 0.17), 2));
                r -= spine * 0.07; g -= spine * 0.075; b -= spine * 0.06;
                double belly = Clamp(1 - inside / (R * 0.45), 0, 1);
                r += belly * 0.035; g += belly * 0.035; b += belly * 0.03;
                double blot = Clamp((Fbm(x / 45.0, y / 45.0, 3, 411) - 0.62) * 3.0, 0, 1) * 0.06;   // uneven tanning
                r -= blot; g -= blot * 1.1; b -= blot * 1.1;
                double dk = pore * 0.07 + grain * 0.02 + scar * 0.05 + crease * 0.05;
                r *= 1 - dk; g *= 1 - dk * 1.05; b *= 1 - dk * 1.1;
                // the cut edge: the paler, fibrous flesh side shows in a thin band, darkened by handling
                if (inside < 3.0)
                {
                    double k = Clamp(1 - inside / 3.0, 0, 1) * (0.6 + 0.4 * fz);
                    r += (0.82 - r) * k * 0.35; g += (0.69 - g) * k * 0.35; b += (0.52 - b) * k * 0.35;
                }
                else if (inside < 10.0)
                {
                    double k = Clamp(1 - (inside - 3.0) / (2.0 + 5.0 * fz), 0, 1);
                    r *= 1 - 0.12 * k; g *= 1 - 0.14 * k; b *= 1 - 0.16 * k;
                }
                col[x, y, 0] = r; col[x, y, 1] = g; col[x, y, 2] = b;
            }

        double lx, ly, lz; Light(out lx, out ly, out lz);
        var img = new double[W, H, 4];
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                int xa = Math.Max(0, x - 1), xb = Math.Min(W - 1, x + 1), ya = Math.Max(0, y - 1), yb = Math.Min(H - 1, y + 1);
                double gx = (hgt[xb, y] - hgt[xa, y]) * 0.5, gy = (hgt[x, yb] - hgt[x, ya]) * 0.5;
                double nX = -gx, nY = -gy, nZ = 1;
                double nl = Math.Sqrt(nX * nX + nY * nY + nZ * nZ); nX /= nl; nY /= nl; nZ /= nl;
                double diff = Clamp(nX * lx + nY * ly + nZ * lz, 0, 1);
                double sheen = Math.Pow(diff, 8) * 0.04;                                    // soft, nearly matte
                double tone = 0.58 + 0.50 * diff;
                for (int c = 0; c < 3; c++) img[x, y, c] = col[x, y, c] * tone + sheen;
                img[x, y, 3] = alpha[x, y];
            }
        Save(img, tga, png);
    }

    // ---------------------------------------------------------------- arcane script
    // Mage writing hanging in the air: a soft violet haze for the words to sit on (ArcaneHaze) and a
    // glowing rune circle drawn white (ArcaneRing; the addon tints it, adds it and turns it slowly).
    public static void ArcaneHaze(string tga, string png, int size, int seed)
    {
        Seed = seed;
        int W = size, H = size;
        var img = new double[W, H, 4];
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                double dx = (x - W * 0.5) / (W * 0.5), dy = (y - H * 0.5) / (H * 0.5);
                double q = Math.Pow(Math.Pow(Math.Abs(dx), 3) + Math.Pow(Math.Abs(dy), 3), 1.0 / 3);
                double t = Clamp((q - 0.45) / 0.55, 0, 1);
                double fall = 1 - t * t * (3 - 2 * t);                                        // smooth fade to the edge
                double wisp = Fbm(x / 40.0, y / 28.0, 4, 501);
                double a = 0.62 * fall * (0.80 + 0.40 * wisp);
                double mix = Fbm(x / 70.0, y / 70.0, 3, 502);
                img[x, y, 0] = 0.06 + 0.05 * mix; img[x, y, 1] = 0.03; img[x, y, 2] = 0.13 + 0.06 * (1 - mix);
                img[x, y, 3] = Clamp(a, 0, 1);
            }
        Save(img, tga, png);
    }

    static double SegDist(double px, double py, double ax, double ay, double bx, double by)
    {
        double vx = bx - ax, vy = by - ay, wx = px - ax, wy = py - ay;
        double t = Clamp((wx * vx + wy * vy) / Math.Max(1e-9, vx * vx + vy * vy), 0, 1);
        double ex = wx - vx * t, ey = wy - vy * t;
        return Math.Sqrt(ex * ex + ey * ey);
    }

    public static void ArcaneRing(string tga, string png, int size, int seed)
    {
        Seed = seed;
        int W = size, H = size;
        double S = W * 0.5;
        var rnd = new Random(seed);
        int nRune = 30;
        // each rune: 2-3 strokes in a unit cell (u along the ring, v outward), coords in -1..1
        var runes = new double[nRune][];
        for (int i = 0; i < nRune; i++)
        {
            int n = 2 + rnd.Next(2);
            var segs = new double[n * 4];
            for (int k = 0; k < n; k++)
            {
                int kind = rnd.Next(4);
                double a = rnd.NextDouble() * 1.2 - 0.6;
                if (kind == 0) { segs[k * 4] = a; segs[k * 4 + 1] = -0.9; segs[k * 4 + 2] = a; segs[k * 4 + 3] = 0.9; }          // stave
                else if (kind == 1) { segs[k * 4] = -0.7; segs[k * 4 + 1] = a; segs[k * 4 + 2] = 0.7; segs[k * 4 + 3] = -a; }   // slant
                else if (kind == 2) { segs[k * 4] = -0.6; segs[k * 4 + 1] = 0.9; segs[k * 4 + 2] = 0.1; segs[k * 4 + 3] = a; }   // branch
                else { segs[k * 4] = -0.6; segs[k * 4 + 1] = a; segs[k * 4 + 2] = 0.6; segs[k * 4 + 3] = a; }                 // bar
            }
            runes[i] = segs;
        }
        var img = new double[W, H, 4];
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                double px = (x + 0.5 - S) / S, py = (y + 0.5 - S) / S;
                double r = Math.Sqrt(px * px + py * py), th = Math.Atan2(py, px);
                double d = 9;                                                       // distance to the nearest line, in pixels
                d = Math.Min(d, Math.Abs(r - 0.95) * S);
                d = Math.Min(d, Math.Abs(r - 0.82) * S);
                d = Math.Min(d, Math.Abs(r - 0.60) * S);
                // runes in the band between the outer circles
                if (r > 0.83 && r < 0.94)
                {
                    double cellA = 2 * Math.PI / nRune;
                    int ci = (int)Math.Floor((th + Math.PI) / cellA);
                    double mid = -Math.PI + (ci + 0.5) * cellA;
                    double u = (th - mid) / (cellA * 0.38), v = (r - 0.885) / 0.042;
                    var segs = runes[((ci % nRune) + nRune) % nRune];
                    double scale = cellA * 0.38 * 0.885 * S;                        // pixels per unit u (roughly v too)
                    for (int k = 0; k < segs.Length; k += 4)
                        d = Math.Min(d, SegDist(u, v, segs[k], segs[k + 1], segs[k + 2], segs[k + 3]) * Math.Min(scale, 0.042 * S));
                }
                // a triangle inside the inner circle with a small ring at each point, an inner circle holding
                // a smaller upside-down triangle, and short spokes round the inner circle
                for (int k = 0; k < 3; k++)
                {
                    double a0 = -Math.PI / 2 + k * 2 * Math.PI / 3, a1 = a0 + 2 * Math.PI / 3;
                    double ax_ = Math.Cos(a0) * 0.60, ay_ = Math.Sin(a0) * 0.60, bx = Math.Cos(a1) * 0.60, by = Math.Sin(a1) * 0.60;
                    d = Math.Min(d, SegDist(px, py, ax_, ay_, bx, by) * S);
                    double rx = px - ax_, ry = py - ay_;
                    d = Math.Min(d, Math.Abs(Math.Sqrt(rx * rx + ry * ry) - 0.05) * S);
                    double b0 = Math.PI / 2 + k * 2 * Math.PI / 3, b1 = b0 + 2 * Math.PI / 3;
                    d = Math.Min(d, SegDist(px, py, Math.Cos(b0) * 0.28, Math.Sin(b0) * 0.28, Math.Cos(b1) * 0.28, Math.Sin(b1) * 0.28) * S);
                }
                d = Math.Min(d, Math.Abs(r - 0.30) * S);
                for (int k = 0; k < 12; k++)
                {
                    double sa = k * Math.PI / 6 + Math.PI / 12;
                    d = Math.Min(d, SegDist(px, py, Math.Cos(sa) * 0.63, Math.Sin(sa) * 0.63, Math.Cos(sa) * 0.70, Math.Sin(sa) * 0.70) * S);
                }
                double core = Clamp(1.6 - d, 0, 1);                                 // ~1.5px line
                double glow = Math.Exp(-d / 4.0) * 0.35;
                double flick = 0.85 + 0.15 * Fbm(th * 4 + 10, r * 6, 2, 601);
                double a = Clamp((core + glow) * flick, 0, 1);
                if (r > 1.0) a = 0;
                img[x, y, 0] = 1; img[x, y, 1] = 1; img[x, y, 2] = 1; img[x, y, 3] = a;
            }
        Save(img, tga, png);
    }

    // ---------------------------------------------------------------- ink blots
    // Drops of ink shaken off a quill and soaked into the material ("Blotted scrawl"): a 2x2 atlas of
    // blots, white (the addon tints them with the ink). Each: an irregular body that's never round, darkest
    // in the middle where the drop landed and thinning towards its edge, then bled out into the cloth along
    // a ragged front (furthest along the threads it wicks into), and a few satellite specks. Cells: 0 big blot, 1 smaller blot, 2 splash with specks,
    // 3 teardrop (a drop that landed at an angle).
    public static void InkBlots(string tga, string png, int size, int seed)
    {
        Seed = seed;
        int W = size, H = size, C = size / 2;
        var img = new double[W, H, 4];
        var rnd = new Random(seed);
        for (int cell = 0; cell < 4; cell++)
        {
            int ox = (cell % 2) * C, oy = (cell / 2) * C;
            double cx = C * 0.5, cy = C * 0.5;
            double R = C * (cell == 1 ? 0.24 : cell == 2 ? 0.22 : 0.27);
            double stretch = cell == 3 ? 1.55 : 1.0 + rnd.NextDouble() * 0.15;     // teardrop: drawn out
            double ang = rnd.NextDouble() * Math.PI;
            double ca = Math.Cos(ang), sa = Math.Sin(ang);
            // satellite specks
            int nSp = cell == 2 ? 7 : 2 + rnd.Next(3);
            var sp = new double[nSp * 3];
            for (int i = 0; i < nSp; i++)
            {
                double a = rnd.NextDouble() * 2 * Math.PI, d = R * (1.35 + rnd.NextDouble() * (cell == 2 ? 1.2 : 0.6));
                sp[i * 3] = cx + Math.Cos(a) * d; sp[i * 3 + 1] = cy + Math.Sin(a) * d;
                sp[i * 3 + 2] = R * (0.07 + rnd.NextDouble() * (cell == 2 ? 0.16 : 0.10));
            }
            int s = 900 + cell * 31;
            for (int y = 0; y < C; y++)
                for (int x = 0; x < C; x++)
                {
                    double dx = x + 0.5 - cx, dy = y + 0.5 - cy;
                    double u = dx * ca + dy * sa, v = -dx * sa + dy * ca;
                    if (cell == 3 && u > 0) u /= stretch; else if (cell != 3) u /= stretch;
                    if (cell == 3 && u < 0) u *= 1.15;                                    // the round head of the drop
                    double th = Math.Atan2(v, u), r = Math.Sqrt(u * u + v * v);
                    double ct = Math.Cos(th), st = Math.Sin(th);
                    double rim = R * (1 + (Fbm(ct * 1.6 + cell * 7, st * 1.6 + cell * 3, 3, s) - 0.5) * 0.55
                                        + (Fbm(ct * 5 + cell, st * 5, 2, s + 1) - 0.5) * 0.18);
                    // fibres: the ink wicks out along a few threads, thin and fading
                    double wick = Math.Pow(Clamp(Value(th * 7.0 / Math.PI + cell * 13, 0.5, s + 2) * 1.35 - 0.35, 0, 1), 3) * R * 0.55;
                    // the core: darkest in the middle where the drop landed, thinning towards its edge
                    double tc = Clamp(r / Math.Max(1, rim), 0, 1);
                    double soak = 0.94 + 0.06 * Fbm(x / 7.0 + cell * 5, y / 7.0, 3, s + 3);
                    double a = r <= rim ? (1 - 0.45 * Math.Pow(tc, 1.8)) * soak : 0;
                    // the bleed: the cloth drinks the ink out past the edge, fading to nothing along a ragged
                    // front, furthest along the threads it wicks into
                    double spread = R * 0.45 * (0.55 + 0.9 * Fbm(ct * 6 + cell * 3, st * 6 + cell, 3, s + 6)) + wick * 1.6;
                    if (r > rim && r < rim + spread)
                    {
                        double k = 1 - (r - rim) / spread;
                        double fibre = 0.7 + 0.3 * Value(x * 0.8, y * 0.8, s + 4);
                        a = 0.55 * Math.Pow(k, 1.6) * fibre;
                    }
                    for (int i = 0; i < nSp; i++)
                    {
                        double ex = x + 0.5 - sp[i * 3], ey = y + 0.5 - sp[i * 3 + 1];
                        double rr = sp[i * 3 + 2] * (1 + (Value(Math.Atan2(ey, ex) * 2 + i, 0.5, s + 5) - 0.5) * 0.6);
                        double sd = Math.Sqrt(ex * ex + ey * ey);
                        // a speck: dark at its heart, bleeding out a little way
                        a = Math.Max(a, Clamp(1 - sd / (rr * 1.6), 0, 1) * (sd < rr ? 0.95 : 0.6));
                    }
                    img[ox + x, oy + y, 0] = 1; img[ox + x, oy + y, 1] = 1; img[ox + x, oy + y, 2] = 1;
                    img[ox + x, oy + y, 3] = Clamp(a, 0, 1);
                }
        }
        Save(img, tga, png);
    }

    // ---------------------------------------------------------------- chalk grain
    // A small tiling overlay laid over the chalked writing: slate-coloured, with alpha where the chalk
    // skipped over the stone's low spots (speckle plus streaks along the stroke). Over bare slate it
    // is nearly invisible (same colour); over chalk it breaks the letters up like real chalk.
    static double TileValue(double x, double y, int period, int s)
    {
        int xi = (int)Math.Floor(x), yi = (int)Math.Floor(y);
        double xf = x - xi, yf = y - yi;
        Func<int, int, double> h = (a, c) => Hash(((a % period) + period) % period, ((c % period) + period) % period, s);
        double u = Smooth(xf), v = Smooth(yf);
        return (h(xi, yi) * (1 - u) + h(xi + 1, yi) * u) * (1 - v) + (h(xi, yi + 1) * (1 - u) + h(xi + 1, yi + 1) * u) * v;
    }
    public static void ChalkGrain(string tga, string png, int size, int seed, double r, double g, double b)
    {
        Seed = seed;
        var img = new double[size, size, 4];
        for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
            {
                // fine speckle (periods divide the tile, so it repeats seamlessly)
                double sp = TileValue(x / 1.0, y / 1.0, size, 1) * 0.45 + TileValue(x / 2.0, y / 2.0, size / 2, 2) * 0.35
                          + TileValue(x / 4.0, y / 4.0, size / 4, 3) * 0.20;
                // streaks: low spots in the stone the chalk skipped, drawn out sideways
                double st = TileValue(x / 8.0, y / 1.5, size / 8, 4) * 0.6 + TileValue(x / 16.0, y / 3.0, size / 16, 5) * 0.4;
                double gap = Math.Max(Clamp((sp - 0.58) * 3.2, 0, 1), Clamp((st - 0.60) * 3.0, 0, 1) * 0.85);
                img[x, y, 0] = r; img[x, y, 1] = g; img[x, y, 2] = b;
                img[x, y, 3] = gap;
            }
        Save(img, tga, png);
    }

    // ---------------------------------------------------------------- measuring
    // The largest rectangle that lies entirely on the material (alpha >= 0.94), as fractions of the
    // image: "left, top, right, bottom" insets. The addon keeps the writing inside it (style.inset),
    // so it follows the shape when the window is stretched. Also prints the bottom-right corner
    // along the diagonal (style.imageCorner).
    public static string SafeRect(string tgaPath)
    {
        byte[] b = File.ReadAllBytes(tgaPath);
        int W = b[12] | (b[13] << 8), H = b[14] | (b[15] << 8);
        int S = 4;                                    // search on a 4px grid
        int gw = W / S, gh = H / S;
        var sum = new int[gw + 1, gh + 1];           // prefix sum of "not material" cells
        for (int y = 0; y < gh; y++)
            for (int x = 0; x < gw; x++)
            {
                int bad = 0;
                for (int dy = 0; dy < S && bad == 0; dy++)
                    for (int dx = 0; dx < S; dx++)
                        if (b[18 + ((y * S + dy) * W + x * S + dx) * 4 + 3] < 240) { bad = 1; break; }
                sum[x + 1, y + 1] = bad + sum[x, y + 1] + sum[x + 1, y] - sum[x, y];
            }
        long best = 0; int bl = 0, bt = 0, br = 0, bb = 0;
        for (int t = 0; t < gh / 2; t++)
            for (int bo = gh; bo > gh / 2; bo--)
                for (int l = 0; l < gw / 2; l++)
                {
                    // widest r for this l, t, b: walk right while still clean (monotone)
                    int lo = l + 1, hi = gw, r = -1;
                    while (lo <= hi)
                    {
                        int mid = (lo + hi) / 2;
                        int bad = sum[mid, bo] - sum[l, bo] - sum[mid, t] + sum[l, t];
                        if (bad == 0) { r = mid; lo = mid + 1; } else hi = mid - 1;
                    }
                    if (r < 0) continue;
                    long area = (long)(r - l) * (bo - t);
                    if (area > best) { best = area; bl = l; bt = t; br = r; bb = bo; }
                }
        int diag = 0;
        while (diag < W && b[18 + ((H - 1 - diag) * W + (W - 1 - diag)) * 4 + 3] < 128) diag++;
        return string.Format(System.Globalization.CultureInfo.InvariantCulture,
            "inset = {{ {0:0.000}, {1:0.000}, {2:0.000}, {3:0.000} }}  imageCorner(diagonal) = {4:0.000}",
            bl * S / (double)W, bt * S / (double)H, 1 - br * S / (double)W, 1 - bb * S / (double)H, diag / (double)W);
    }

    // ---------------------------------------------------------------- shared helpers
    static void Light(out double lx, out double ly, out double lz)
    {
        lx = -0.55; ly = -0.62; lz = 0.56;
        double ll = Math.Sqrt(lx * lx + ly * ly + lz * lz); lx /= ll; ly /= ll; lz /= ll;
    }
    static double Ridged(double x, double y, int oct, int s)
    {
        double sum = 0, amp = 0.5, f = 1, norm = 0;
        for (int i = 0; i < oct; i++) { sum += amp * (1 - Math.Abs(Value(x * f, y * f, s + i * 13) * 2 - 1)); norm += amp; amp *= 0.5; f *= 2; }
        return sum / norm;
    }

    // ---------------------------------------------------------------- flat stone
    // An oblong river/field stone with a broad flat face to chalk on: grey, granite-speckled,
    // a quartz vein, a hairline crack, lichen creeping in from the rim, rolled-off edges in shadow.
    public static void Stone(string tga, string png, int size, int seed)
    {
        Seed = seed;
        int W = size, H = size;
        var hgt = new double[W, H];
        var qv = new double[W, H];
        double cx0 = W * 0.5, cy0 = H * 0.5;
        double ax = W * 0.465, ay = H * 0.445;
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                double dx = (x - cx0) / ax, dy = (y - cy0) / ay;
                // egg: the right end a little fuller, the bottom a little flatter
                dy *= 1.0 - 0.06 * (dx);
                double th = Math.Atan2(dy, dx);
                double p = 3.0;
                double q = Math.Pow(Math.Pow(Math.Abs(dx), p) + Math.Pow(Math.Abs(dy), p), 1.0 / p);
                double ct = Math.Cos(th), st = Math.Sin(th);
                double rim = 1.0
                    + (Fbm(ct * 1.6 + 5, st * 1.6 + 5, 3, 61) - 0.5) * 0.16     // lumpy outline
                    + (Fbm(ct * 6.0 + 9, st * 6.0 + 9, 2, 62) - 0.5) * 0.035;   // small chips
                q /= rim;
                qv[x, y] = q;
                // flat-topped dome: the face is nearly level, the sides roll steeply away
                double dome = q < 1 ? Math.Sqrt(Math.Max(0, 1 - Math.Pow(q, 5))) : 0;
                double bumps = (Fbm(x / 110.0, y / 110.0, 3, 63) - 0.5) * 7.0           // water-worn: gentle swells only
                    + (x - W * 0.5) / W * -3.0                                           // the face tilts a touch toward the light
                    + (Fbm(x / 3.0, y / 3.0, 2, 67) - 0.5) * 0.35;                       // fine matte grain that catches the light
                double pitMask = Clamp((Fbm(x / 80.0, y / 80.0, 2, 66) - 0.45) * 4, 0, 1);   // pits cluster in patches
                double pits = -Math.Pow(Clamp(Fbm(x / 13.0, y / 13.0, 3, 64) - 0.74, 0, 1), 1.3) * 5.0 * pitMask;
                double weather = (Ridged(x / 45.0, y / 45.0, 3, 65) - 0.5) * 0.5;
                hgt[x, y] = dome * 70.0 + (bumps + pits + weather) * Clamp(dome * 3, 0, 1);
            }

        // a hairline crack: a random walk across part of the face
        var crack = new double[W, H];
        var rnd = new Random(seed);
        {
            double px = W * 0.62, py = H * 0.18, ang = Math.PI * 0.62;
            for (int k = 0; k < 520; k++)
            {
                ang += (rnd.NextDouble() - 0.5) * 0.5;
                px += Math.Cos(ang) * 0.9; py += Math.Sin(ang) * 0.9;
                double wdt = 0.9 * (1 - k / 600.0);
                for (int oy = -2; oy <= 2; oy++)
                    for (int ox = -2; ox <= 2; ox++)
                    {
                        int ix = (int)(px + ox), iy = (int)(py + oy);
                        if (ix < 0 || iy < 0 || ix >= W || iy >= H) continue;
                        double d = Math.Sqrt((ix - px) * (ix - px) + (iy - py) * (iy - py));
                        crack[ix, iy] = Math.Max(crack[ix, iy], Clamp(1 - d / (wdt + 0.6), 0, 1));
                    }
                if (k == 260) ang += 0.7;
            }
            // the crack is a real groove: its upper wall shades, the lower one catches the light
            for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) hgt[x, y] -= crack[x, y] * 2.2;
        }

        double lx, ly, lz; Light(out lx, out ly, out lz);
        var img = new double[W, H, 4];
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                int x0 = Math.Max(0, x - 1), x1 = Math.Min(W - 1, x + 1), y0 = Math.Max(0, y - 1), y1 = Math.Min(H - 1, y + 1);
                double gx = (hgt[x1, y] - hgt[x0, y]) * 0.5, gy = (hgt[x, y1] - hgt[x, y0]) * 0.5;
                double nX = -gx, nY = -gy, nZ = 1.0;
                double nl = Math.Sqrt(nX * nX + nY * nY + nZ * nZ); nX /= nl; nY /= nl; nZ /= nl;
                double diff = Clamp(nX * lx + nY * ly + nZ * lz, 0, 1);
                double spec = Math.Pow(Clamp(diff, 0, 1), 10) * 0.10;                     // river-polished sheen
                double q = qv[x, y];

                // albedo: dark blue-grey slate, a slow wander in tone, faint layering bands
                double base_ = 0.215 + (Fbm(x / 70.0, y / 70.0, 4, 70) - 0.5) * 0.05;
                double warm = (Fbm(x / 110.0, y / 110.0, 3, 71) - 0.5) * 0.03;
                double r = base_ + warm - 0.010, g = base_ + warm * 0.4 + 0.005, b = base_ - warm * 0.3 + 0.030;
                double lam = (y + x * 0.18) / 7.0 + (Fbm(x / 90.0, y / 90.0, 3, 72) - 0.5) * 6.0;
                double band = (Math.Sin(lam) * 0.5 + 0.5) * (Fbm(x / 40.0, y / 40.0, 2, 69) * 0.8 + 0.2);
                r += (band - 0.3) * 0.022; g += (band - 0.3) * 0.022; b += (band - 0.3) * 0.026;
                double fine = (Hash(x, y, 73) - 0.5) * 0.018;
                r += fine; g += fine; b += fine;
                // rusty iron staining seeping along the layers, and darker damp patches
                double iron = Clamp((Fbm(x / 55.0, y / 30.0, 4, 68) - 0.60) * 3.5, 0, 1) * 0.45;
                r += (0.30 - r) * iron; g += (0.235 - g) * iron; b += (0.18 - b) * iron;
                double damp = Clamp((Fbm(x / 45.0, y / 45.0, 3, 59) - 0.58) * 4, 0, 1) * 0.14;
                r *= 1 - damp; g *= 1 - damp; b *= 1 - damp * 0.8;
                // the odd pale mineral fleck
                if (Value(x / 1.6, y / 1.6, 58) > 0.965) { r += 0.10; g += 0.10; b += 0.10; }

                // a quartz vein wandering across the lower part
                double vy = H * 0.74 + (x - W * 0.5) * 0.22 + (Fbm(x / 60.0, 0.5, 3, 74) - 0.5) * 34
                    + (Fbm(x / 6.0, y / 6.0, 2, 79) - 0.5) * 3.0;                   // ragged edges
                double vd = Math.Abs(y - vy);
                double vw = 0.8 + Fbm(x / 25.0, 1.5, 2, 75) * 3.2;
                double vFade = Clamp((Fbm(x / 70.0, 2.5, 2, 80) - 0.30) * 3, 0, 1);  // the vein comes and goes
                if (vd < vw) { double k = Math.Pow(1 - vd / vw, 0.5) * 0.45 * vFade; r += (0.66 - r) * k; g += (0.67 - g) * k; b += (0.66 - b) * k; }

                // lichen creeping in from the rim (pale sage, a few rusty orange spots)
                double lich = Fbm(x / 26.0, y / 26.0, 4, 76) + Clamp((q - 0.72) * 1.6, 0, 0.5);
                if (lich > 9 && q < 1)             // river stone: no lichen (kept for other stones: lower the threshold)
                {
                    double k = Clamp((lich - 0.86) * 9, 0, 1) * (0.7 + 0.3 * Value(x * 0.5, y * 0.5, 77));
                    bool rust = Fbm(x / 60.0, y / 60.0, 2, 78) > 0.68;
                    double lr = rust ? 0.72 : 0.66, lg = rust ? 0.52 : 0.68, lb = rust ? 0.30 : 0.52;
                    r += (lr - r) * k; g += (lg - g) * k; b += (lb - b) * k;
                }

                double light = 0.32 + 0.85 * diff + spec;
                // ambient occlusion: the underside of the roll-off sinks into shadow
                double ao = 1 - Clamp((q - 0.80) * 2.2, 0, 0.55);
                double tone = light * ao * (1 - crack[x, y] * 0.30);
                img[x, y, 0] = r * tone; img[x, y, 1] = g * tone; img[x, y, 2] = b * tone;
                img[x, y, 3] = Clamp((1 - q) * W * 0.5 / 1.2, 0, 1);
            }
        Save(img, tga, png);
    }

    // ---------------------------------------------------------------- bark slab
    // A jagged slab of bark broken off a trunk (grain running left-right): rough plates split by
    // furrows, lichen and moss in the cracks, and the broken edge showing the reddish layered
    // inner bark along the bottom and right where the slab's thickness faces the viewer.
    public static void Bark(string tga, string png, int size, int seed)
    {
        Seed = seed;
        int W = size, H = size;
        var rnd = new Random(seed);
        // outline: a polygon of broken edges, long splinters at the ends (bark splits along the grain)
        int nv = 34;
        var vx = new double[nv]; var vy = new double[nv];
        for (int i = 0; i < nv; i++)
        {
            double t = 2 * Math.PI * i / nv + (rnd.NextDouble() - 0.5) * 0.10;
            double ct = Math.Cos(t), st = Math.Sin(t);
            double rx = W * 0.47, ry = H * 0.42;
            double sq = 3.2;     // squarish slab
            double k = Math.Pow(Math.Pow(Math.Abs(ct), sq) + Math.Pow(Math.Abs(st), sq), -1.0 / sq);
            double jag = 1 - rnd.NextDouble() * 0.07;
            // the ends split along the grain into splinters: alternate long points and deep notches
            if (Math.Abs(ct) > 0.80) jag += (i % 2 == 0) ? 0.03 + rnd.NextDouble() * 0.04 : -0.06 - rnd.NextDouble() * 0.07;
            // top and bottom break across the grain: a few bites out of them
            else if (rnd.NextDouble() < 0.25) jag -= 0.05 + rnd.NextDouble() * 0.05;
            vx[i] = W * 0.5 + ct * rx * k * jag;
            vy[i] = H * 0.5 + st * ry * k * jag;
        }
        Func<double, double, double> sdPoly = (px, py) =>
        {
            double d = double.MaxValue; bool inside = false;
            for (int i = 0, j = nv - 1; i < nv; j = i++)
            {
                double ex = vx[i] - vx[j], ey = vy[i] - vy[j];
                double wx = px - vx[j], wy = py - vy[j];
                double t = Clamp((wx * ex + wy * ey) / (ex * ex + ey * ey), 0, 1);
                double ddx = wx - ex * t, ddy = wy - ey * t;
                d = Math.Min(d, ddx * ddx + ddy * ddy);
                if (((vy[i] > py) != (vy[j] > py)) && (px < (vx[j] - vx[i]) * (py - vy[i]) / (vy[j] - vy[i]) + vx[i])) inside = !inside;
            }
            return (inside ? 1 : -1) * Math.Sqrt(d);
        };

        // bark relief: plates split by furrows that run along the grain (left-right), wandering
        // furrows are the contour lines of noise stretched along the grain, so they meander, merge
        // and split like real bark fissures; plates between them carry fibres along the grain
        Func<double, double, double> relief = (x, y) =>
        {
            double wy = y + (Fbm(x / 120.0, y / 120.0, 3, 81) - 0.5) * 50;
            double l1 = Math.Abs(Fbm(x / 170.0, wy / 30.0, 3, 82) - 0.5);
            double l2 = Math.Abs(Fbm(x / 110.0, wy / 22.0, 2, 83) - 0.5);
            double f1 = Math.Pow(Clamp(1 - l1 / 0.075, 0, 1), 1.3);
            double f2 = Math.Pow(Clamp(1 - l2 / 0.040, 0, 1), 1.3) * 0.7;
            double furrow = Math.Max(f1, f2);
            double fibre = (Fbm(x / 30.0, y / 1.6, 3, 84) - 0.5) * 0.45 + (Fbm(x / 9.0, y / 0.9, 2, 85) - 0.5) * 0.25;
            double flake = (Fbm(x / 12.0, y / 7.0, 3, 86) - 0.5) * 1.8 + (Ridged(x / 20.0, y / 11.0, 2, 87) - 0.5) * 0.8;   // scaly plate tops
            double crust = (Fbm(x / 2.5, y / 2.0, 2, 88) - 0.5) * 0.7;                                                    // crusty grit
            // (no cracks across the grain: at tally size they read as stray carving marks)
            return Math.Sqrt(1 - furrow) * 10.0 + (fibre + flake + crust) * 1.6 * (1 - furrow * 0.6);
        };

        double lx, ly, lz; Light(out lx, out ly, out lz);
        var img = new double[W, H, 4];
        for (int y = 0; y < H; y++)
            for (int x = 0; x < W; x++)
            {
                double d = sdPoly(x, y);
                // the broken edge is fibrous: roughen the distance
                d += (Fbm(x / 7.0, y / 7.0, 3, 87) - 0.5) * 6.0 + (Value(x / 2.0, y / 2.0, 88) - 0.5) * 1.5;
                double a = Clamp(d / 1.2, 0, 1);

                double h0 = relief(x, y), hx = relief(x + 1, y), hy = relief(x, y + 1);
                double nX = -(hx - h0) * 1.7, nY = -(hy - h0) * 1.7, nZ = 1;
                double nl = Math.Sqrt(nX * nX + nY * nY + nZ * nZ); nX /= nl; nY /= nl; nZ /= nl;
                double diff = Clamp(nX * lx + nY * ly + nZ * lz, 0, 1);
                double depth = Clamp(1 - h0 / 9.0, 0, 1);                       // 0 on plates, 1 in furrows

                // colour: grey-brown weathered plates, darker reddish furrows
                double m = (Fbm(x / 50.0, y / 50.0, 4, 89) - 0.5) * 0.08;
                double wyc = y + (Fbm(x / 120.0, y / 120.0, 3, 81) - 0.5) * 50;
                m += (Fbm(x / 90.0, wyc / 22.0, 3, 94) - 0.5) * 0.10;                       // each plate a shade of its own
                m += (Hash(x, y, 95) - 0.5) * 0.035;                                        // grit
                double r = 0.265 + m * 0.8, g = 0.180 + m * 0.65, b = 0.130 + m * 0.5;     // chocolate brown
                double grey = Clamp(Fbm(x / 80.0, y / 40.0, 3, 90) * 1.4 - 0.55, 0, 0.30);  // a little weathering
                r += (0.33 - r) * grey; g += (0.27 - g) * grey; b += (0.23 - b) * grey;
                r = r * (1 - depth * 0.52) + 0.24 * depth * 0.35; g = g * (1 - depth * 0.62) + 0.10 * depth * 0.35; b = b * (1 - depth * 0.68) + 0.06 * depth * 0.35;   // reddish deep in the fissures
                // moss and lichen in the furrows
                double moss = Fbm(x / 30.0, y / 30.0, 3, 91);
                if (depth > 0.45 && moss > 0.60) { double k = Clamp((moss - 0.60) * 4, 0, 0.8); r += (0.30 - r) * k; g += (0.38 - g) * k; b += (0.16 - b) * k; }
                double lich = Fbm(x / 18.0, y / 18.0, 3, 92);
                if (depth < 0.3 && lich > 0.80) { double k = Clamp((lich - 0.80) * 5, 0, 0.4); r += (0.62 - r) * k; g += (0.64 - g) * k; b += (0.55 - b) * k; }

                // small grey-green lichen spots on the plates
                if (depth < 0.25 && Value(x / 4.0, y / 4.0, 96) > 0.90 && Fbm(x / 70.0, y / 70.0, 2, 97) > 0.5)
                { r += (0.48 - r) * 0.5; g += (0.50 - g) * 0.5; b += (0.42 - b) * 0.5; }

                double light = 0.38 + 0.85 * diff;
                double tone = light * (1 - 0.35 * Math.Pow(depth, 1.5));                    // fissures sink into shadow

                // the slab's broken edge: its thickness shows along the bottom and right as layered
                // reddish inner bark, a pale cambium line at the very edge
                if (d > 0 && d < 16)
                {
                    // which way the edge faces: sample the outline's gradient
                    double gxd = sdPoly(x + 2, y) - sdPoly(x - 2, y), gyd = sdPoly(x, y + 2) - sdPoly(x, y - 2);
                    double gl = Math.Sqrt(gxd * gxd + gyd * gyd) + 1e-6;
                    double face = Clamp((-gxd * 0.45 - gyd * 0.89) / gl, 0, 1);    // outward normal points down/right
                    double thick = 3 + 7 * face;
                    if (d < thick)
                    {
                        double layer = Math.Sin(d * 1.7 + Fbm(x / 10.0, y / 10.0, 2, 93) * 6);
                        double fresh = Clamp(1 - d / thick, 0, 1);
                        double er = 0.55 + 0.06 * layer, eg = 0.31 + 0.04 * layer, eb = 0.22 + 0.03 * layer;   // reddish inner bark
                        if (d < 2.0) { er = 0.82; eg = 0.55; eb = 0.40; }                   // pale cambium at the very edge
                        double k = Clamp(face * 1.4 + 0.25, 0, 1);
                        r += (er - r) * k; g += (eg - g) * k; b += (eb - b) * k;
                        tone = tone * (1 - k) + (0.70 + 0.25 * face - 0.2 * fresh * (1 - face)) * k;
                    }
                    else if (d < thick + 3) tone *= 0.82;                                  // lip shadow
                }
                img[x, y, 0] = r * tone; img[x, y, 1] = g * tone; img[x, y, 2] = b * tone; img[x, y, 3] = a;
            }
        Save(img, tga, png);
    }
}
