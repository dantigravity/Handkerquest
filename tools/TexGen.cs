using System;
using System.IO;
using System.Drawing;
using System.Drawing.Imaging;

// Procedural textures for the Handkerquest tally: crumpled paper and a torn rag.
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
}
