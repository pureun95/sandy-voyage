"""Landscape art pipeline (trial): AI "pixel art" reference -> album master -> sand puzzle image.

Not wired into the game. Produces candidate PNGs + a metrics report for review.

    python tools/landscape_pipeline.py <reference.png> <out_dir> <prefix> [options]

Steps
  1. Album master (default 256x256):
     a. k-means (CIELAB) palette of `--album-colors` colors fitted on the full-res reference.
     b. every reference pixel -> nearest palette index (no blended colors survive).
     c. downsample by majority vote of the indices inside each output cell (crisp edges,
        no resampling blur; works even when the reference's fake pixel grid is irregular).
     d. cleanup: isolated pixels and components <= `--album-tiny` px merge into the
        neighbouring color they share the longest border with.
     e. `--blank x0,y0,x1,y1[,x2,y2]` (reference px): fill a rect with the color sampled at
        (x2,y2) (default: the rect's most common color). Used to erase plaque lettering that
        cannot be drawn correctly at album size.
  2. Puzzle (default 128x128) from the album master only:
     a. weighted k-means (CIELAB) over the album's palette entries, weight = count **
        `--puzzle-weight`, maximin init -> `--puzzle-colors` sand colors.
     b. each 2x2 album block -> sand color nearest to the block's mean (Lab).
     c. cleanup: components <= `--puzzle-tiny` px merge into their longest-border neighbour.
  3. Metrics (same definitions as scripts/sand/sand_map_analyzer.gd) printed as JSON.

Needs numpy, pillow, scipy.
"""
import argparse, json, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage

# ---------------------------------------------------------------- color helpers

def srgb_to_lab(rgb):
    c = np.asarray(rgb, dtype=np.float64) / 255.0
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    m = np.array([[0.4124564, 0.3575761, 0.1804375],
                  [0.2126729, 0.7151522, 0.0721750],
                  [0.0193339, 0.1191920, 0.9503041]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 216 / 24389, np.cbrt(xyz), (24389 / 27 * xyz + 16) / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def delta_e2000(a, b):
    L1, a1, b1 = a[..., 0], a[..., 1], a[..., 2]
    L2, a2, b2 = b[..., 0], b[..., 1], b[..., 2]
    C1, C2 = np.hypot(a1, b1), np.hypot(a2, b2)
    Cm = (C1 + C2) / 2
    G = 0.5 * (1 - np.sqrt(Cm ** 7 / (Cm ** 7 + 25 ** 7)))
    a1p, a2p = a1 * (1 + G), a2 * (1 + G)
    C1p, C2p = np.hypot(a1p, b1), np.hypot(a2p, b2)
    h1p = np.degrees(np.arctan2(b1, a1p)) % 360
    h2p = np.degrees(np.arctan2(b2, a2p)) % 360
    dLp, dCp = L2 - L1, C2p - C1p
    dh = h2p - h1p
    dh = np.where(dh > 180, dh - 360, np.where(dh < -180, dh + 360, dh))
    dh = np.where(C1p * C2p == 0, 0, dh)
    dHp = 2 * np.sqrt(C1p * C2p) * np.sin(np.radians(dh / 2))
    Lpm, Cpm = (L1 + L2) / 2, (C1p + C2p) / 2
    hs = h1p + h2p
    hpm = np.where(C1p * C2p == 0, hs, np.where(np.abs(h1p - h2p) <= 180, hs / 2,
                   np.where(hs < 360, (hs + 360) / 2, (hs - 360) / 2)))
    T = (1 - 0.17 * np.cos(np.radians(hpm - 30)) + 0.24 * np.cos(np.radians(2 * hpm))
         + 0.32 * np.cos(np.radians(3 * hpm + 6)) - 0.20 * np.cos(np.radians(4 * hpm - 63)))
    Sl = 1 + 0.015 * (Lpm - 50) ** 2 / np.sqrt(20 + (Lpm - 50) ** 2)
    Sc, Sh = 1 + 0.045 * Cpm, 1 + 0.015 * Cpm * T
    Rt = (-2 * np.sqrt(Cpm ** 7 / (Cpm ** 7 + 25 ** 7))
          * np.sin(np.radians(60 * np.exp(-(((hpm - 275) / 25) ** 2)))))
    return np.sqrt((dLp / Sl) ** 2 + (dCp / Sc) ** 2 + (dHp / Sh) ** 2 + Rt * (dCp / Sc) * (dHp / Sh))


def lab_to_srgb8(lab):
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    fy = (L + 16) / 116
    fx, fz = fy + a / 500, fy - b / 200
    def inv(f):
        return np.where(f ** 3 > 216 / 24389, f ** 3, (116 * f - 16) / (24389 / 27))
    xyz = np.stack([inv(fx), inv(fy), inv(fz)], -1) * np.array([0.95047, 1.0, 1.08883])
    m = np.array([[3.2404542, -1.5371385, -0.4985314],
                  [-0.9692660, 1.8760108, 0.0415560],
                  [0.0556434, -0.2040259, 1.0572252]])
    c = np.clip(xyz @ m.T, 0, 1)
    c = np.where(c <= 0.0031308, 12.92 * c, 1.055 * c ** (1 / 2.4) - 0.055)
    return np.clip(np.round(c * 255), 0, 255).astype(np.uint8)


def kmeans_lab(lab_pts, k, seed=7, iters=40, sample=200000):
    rng = np.random.default_rng(seed)
    pts = lab_pts if len(lab_pts) <= sample else lab_pts[rng.choice(len(lab_pts), sample, replace=False)]
    centers = [pts[rng.integers(len(pts))]]
    d2 = ((pts - centers[0]) ** 2).sum(1)
    for _ in range(1, k):  # k-means++
        centers.append(pts[rng.choice(len(pts), p=d2 / d2.sum())])
        d2 = np.minimum(d2, ((pts - centers[-1]) ** 2).sum(1))
    c = np.array(centers)
    for _ in range(iters):
        lab_idx = nearest(pts, c)
        newc = np.array([pts[lab_idx == i].mean(0) if np.any(lab_idx == i) else c[i] for i in range(k)])
        if np.allclose(newc, c, atol=1e-3):
            break
        c = newc
    return c


def nearest(lab_pts, centers, chunk=400000):
    out = np.empty(len(lab_pts), dtype=np.int32)
    for s in range(0, len(lab_pts), chunk):
        p = lab_pts[s:s + chunk]
        out[s:s + chunk] = ((p[:, None, :] - centers[None]) ** 2).sum(2).argmin(1)
    return out

# ---------------------------------------------------------------- index-image helpers

def components(idx):
    """4-connected same-color components: returns (labels, n, color_of_label, size_of_label)."""
    labels = np.zeros(idx.shape, np.int32)
    n = 0
    for c in np.unique(idx):
        lab, k = ndimage.label(idx == c)
        labels[lab > 0] = lab[lab > 0] + n
        n += k
    color = np.zeros(n + 1, np.int32)
    color[labels.ravel()] = idx.ravel()
    size = np.bincount(labels.ravel(), minlength=n + 1)
    return labels, n, color, size


def merge_small(idx, max_px, protect=None, passes=6):
    """Components <= max_px take the color of the neighbour they share the longest border with."""
    idx = idx.copy()
    for _ in range(passes):
        labels, n, color, size = components(idx)
        small = np.where((size <= max_px) & (np.arange(n + 1) > 0))[0]
        if len(small) == 0:
            break
        h, w = idx.shape
        changed = 0
        small_set = np.zeros(n + 1, bool); small_set[small] = True
        # border votes: for each pixel of a small comp, look at 4 neighbours of other labels
        votes = {}
        ys, xs = np.nonzero(small_set[labels])
        for y, x in zip(ys, xs):
            if protect is not None and protect[y, x]:
                continue
            l = labels[y, x]
            for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < h and 0 <= xx < w and labels[yy, xx] != l:
                    d = votes.setdefault(l, {})
                    c = idx[yy, xx]
                    d[c] = d.get(c, 0) + 1
        for l, d in votes.items():
            best = max(d.items(), key=lambda kv: kv[1])[0]
            idx[labels == l] = best
            changed += 1
        if changed == 0:
            break
    return idx


def isolated_count(idx):
    h, w = idx.shape
    p = np.pad(idx, 1, constant_values=-1)
    same = np.zeros(idx.shape, np.int32)
    for dy, dx in ((0, 1), (2, 1), (1, 0), (1, 2)):
        same += p[dy:dy + h, dx:dx + w] == idx
    return int((same == 0).sum())


def metrics(idx, rgb_palette, tiny_max=3):
    labels, n, color, size = components(idx)
    total = idx.size
    per = []
    for c in range(len(rgb_palette)):
        sizes = size[1:][color[1:] == c]
        if len(sizes) == 0:
            per.append({"color": "#%02x%02x%02x" % tuple(rgb_palette[c]), "pixels": 0})
            continue
        per.append({
            "color": "#%02x%02x%02x" % tuple(rgb_palette[c]),
            "pixels": int(sizes.sum()), "ratio": round(float(sizes.sum()) / total, 4),
            "components": int(len(sizes)), "largest": int(sizes.max()),
            "tiny_components": int((sizes <= tiny_max).sum()),
            "tiny_pixels": int(sizes[sizes <= tiny_max].sum()),
        })
    diff = (idx[:, 1:] != idx[:, :-1]).sum() + (idx[1:] != idx[:-1]).sum()
    pairs = idx[:, 1:].size + idx[1:].size
    lab = srgb_to_lab(np.array(rgb_palette))
    de = []
    for i in range(len(lab)):
        for j in range(i + 1, len(lab)):
            de.append((float(delta_e2000(lab[i], lab[j])), i, j,
                       float(np.linalg.norm((np.array(rgb_palette[i], float) - rgb_palette[j]) / 255.0))))
    de.sort()
    tiny_px = sum(p.get("tiny_pixels", 0) for p in per)
    return {
        "size": list(idx.shape[::-1]), "colors": len(rgb_palette),
        "edge_ratio": round(float(diff) / pairs, 4),
        "isolated_pixels": isolated_count(idx),
        "tiny_components_total": int(sum(p.get("tiny_components", 0) for p in per)),
        "tiny_pixel_ratio": round(tiny_px / total, 4),
        "components_total": int(n),
        "min_pair_de2000": [round(de[0][0], 1), per[de[0][1]]["color"], per[de[0][2]]["color"]] if de else None,
        "closest_pairs": [[round(d, 1), per[i]["color"], per[j]["color"], round(r, 3)] for d, i, j, r in de[:4]],
        "per_color": per,
    }


def summary(m):
    return {k: m[k] for k in ("colors", "edge_ratio", "isolated_pixels", "tiny_components_total",
                              "tiny_pixel_ratio", "components_total")}


def index_of_image(path):
    a = np.array(Image.open(path).convert("RGB"))
    cols, inv = np.unique(a.reshape(-1, 3), axis=0, return_inverse=True)
    return inv.reshape(a.shape[:2]), cols

# ---------------------------------------------------------------- pipeline

def make_album(ref_rgb, size, n_colors, tiny, blanks, seed):
    H, W = ref_rgb.shape[:2]
    lab = srgb_to_lab(ref_rgb.reshape(-1, 3))
    centers = kmeans_lab(lab, n_colors, seed)
    full_idx = nearest(lab, centers).reshape(H, W)
    # majority vote per output cell
    ys = (np.arange(H) * size // H)
    xs = (np.arange(W) * size // W)
    cell = (ys[:, None] * size + xs[None, :]).ravel()
    votes = np.zeros((size * size, n_colors), np.int32)
    np.add.at(votes, (cell, full_idx.ravel()), 1)
    idx = votes.argmax(1).reshape(size, size)
    raw = idx.copy()
    for b in blanks:
        x0, y0, x1, y1 = [int(round(v * size / W)) for v in b[:4]]
        if len(b) >= 6:
            c = idx[int(b[5] * size / H), int(b[4] * size / W)]
        else:
            c = np.bincount(idx[y0:y1, x0:x1].ravel()).argmax()
        idx[y0:y1, x0:x1] = c
    idx = merge_small(idx, tiny)
    rgb_pal = lab_to_srgb8(centers)
    return idx, raw, rgb_pal, centers


def compact(idx, rgb_pal):
    used = np.unique(idx)
    remap = np.zeros(len(rgb_pal), np.int32); remap[used] = np.arange(len(used))
    return remap[idx], rgb_pal[used]


def weighted_kmeans(pts, w, k, iters=100):
    """k-means over palette entries with weights; maximin init so small but distinct hues
    (red pillars, pink flowers) get their own center instead of being outvoted by big areas."""
    c = [pts[w.argmax()]]
    for _ in range(1, k):
        d = np.min([((pts - ci) ** 2).sum(1) for ci in c], 0) * np.sqrt(w)
        c.append(pts[d.argmax()])
    c = np.array(c)
    for _ in range(iters):
        a = ((pts[:, None] - c[None]) ** 2).sum(2).argmin(1)
        n = np.array([(pts[a == i] * w[a == i, None]).sum(0) / w[a == i].sum() if (a == i).any() else c[i]
                      for i in range(k)])
        if np.allclose(n, c):
            break
        c = n
    return c


def make_puzzle(album_idx, album_rgb, size, n_colors, tiny, weight_power, fixed_rgb=None):
    A = album_idx.shape[0]
    f = A // size
    pal_lab = srgb_to_lab(album_rgb.astype(float))
    if fixed_rgb is not None:
        centers = srgb_to_lab(np.asarray(fixed_rgb, float))
    else:
        counts = np.bincount(album_idx.ravel(), minlength=len(album_rgb)).astype(float)
        centers = weighted_kmeans(pal_lab, counts ** weight_power, n_colors)
    alab = pal_lab[album_idx].reshape(-1, 3)
    blk = alab.reshape(size, f, size, f, 3).mean((1, 3)).reshape(-1, 3)
    idx = nearest(blk, centers).reshape(size, size)
    raw = idx.copy()
    idx = merge_small(idx, tiny)
    rgb = np.asarray(fixed_rgb, np.uint8) if fixed_rgb is not None else lab_to_srgb8(centers)
    return idx, raw, rgb


# ---------------------------------------------------------------- touch-up (puzzle)

def dark_priority(album_idx, album_rgb, centers_lab, rect):
    """Inside rect (puzzle px): 2x2 vote of album pixels mapped to sand colors, ties and
    2-of-4 splits go to the darker color, so 1-px album lines (step shadows, railing and arch
    outlines) survive the halving instead of averaging away."""
    x0, y0, x1, y1 = rect
    pal_lab = srgb_to_lab(album_rgb.astype(float))
    pix = nearest(pal_lab, centers_lab)[album_idx]
    blk = pix[2 * y0:2 * y1, 2 * x0:2 * x1]
    h, w = y1 - y0, x1 - x0
    b = blk.reshape(h, 2, w, 2).transpose(0, 2, 1, 3).reshape(h, w, 4)
    k = len(centers_lab)
    votes = np.stack([(b == i).sum(2) for i in range(k)], -1).astype(float)
    votes += (votes >= 2) * (100 - centers_lab[:, 0])[None, None, :] / 100.0  # 2 votes + darker wins
    return votes.argmax(2)


def apply_touchup(idx, spec, color_index, album_idx=None, album_rgb=None, centers_lab=None):
    """spec (JSON, puzzle px, colors as palette key or #hex):
       album_recolor: [{rect, from: [colors], album: {album #hex: color}, min_votes}, ...]
       dark_priority: [[x0,y0,x1,y1], ...]   rule-based detail pass (needs the album)
       outline_bright: [[x0,y0,x1,y1,L,fill,edge], ...]  album-bright stone -> fill + 1px edge
       adaptive_two_tone: [[x0,y0,x1,y1,light,shadow,win], ...]  local-mean split of two tones
       rects:  [[x0,y0,x1,y1,color], ...]    fill (x1,y1 exclusive)
       hlines: [[x0,x1,y,color], ...]        x1 inclusive
       vlines: [[x,y0,y1,color], ...]        y1 inclusive
       pixels: [[x,y,color], ...]
       Edits are applied in this order. Returns (idx, number of changed pixels)."""
    out = idx.copy()
    for r in spec.get("album_recolor", []):
        # Wrong sand color where the album shows a known material: inside rect, pixels whose
        # sand color is in `from` and whose 2x2 album block has >= min_votes pixels of the
        # listed album colors take that color's target (e.g. roof tiles quantized to sky).
        x0, y0, x1, y1 = r["rect"]
        frm = {color_index(c) for c in r["from"]}
        hexes = ["#%02x%02x%02x" % tuple(c) for c in album_rgb]
        target = {hexes.index(h.lower()): color_index(t) for h, t in r["album"].items() if h.lower() in hexes}
        need = int(r.get("min_votes", 2))
        for y in range(y0, y1):
            for x in range(x0, x1):
                if out[y, x] not in frm:
                    continue
                votes = {}
                for i in album_idx[2 * y:2 * y + 2, 2 * x:2 * x + 2].ravel():
                    if i in target:
                        votes[target[i]] = votes.get(target[i], 0) + 1
                if votes:
                    best = max(votes.items(), key=lambda kv: kv[1])
                    if best[1] >= need:
                        out[y, x] = best[0]
    for r in spec.get("dark_priority", []):
        x0, y0, x1, y1 = r
        out[y0:y1, x0:x1] = dark_priority(album_idx, album_rgb, centers_lab, r)
    if spec.get("outline_bright"):
        aL = srgb_to_lab(album_rgb[album_idx].astype(float))[..., 0]
    for x0, y0, x1, y1, thr, fill, edge in spec.get("outline_bright", []):
        # bright carved stone (railings, posts, arch ring): 2x2 blocks with >= 2 album px brighter
        # than thr become `fill`; their 4-neighbours inside the rect that are not bright get `edge`.
        h, w = y1 - y0, x1 - x0
        b = (aL[2 * y0:2 * y1, 2 * x0:2 * x1] > thr).reshape(h, 2, w, 2).sum((1, 3)) >= 2
        p = np.pad(b, 1)
        near = p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
        sub = out[y0:y1, x0:x1]
        sub[near & ~b] = color_index(edge)
        sub[b] = color_index(fill)
    for x0, y0, x1, y1, light, shadow, win in spec.get("adaptive_two_tone", []):
        # carved stone with only two sand tones: compare each 2x2 album block with its local mean
        # so highlight-vs-mid edges (lost by a fixed threshold) survive. Only pixels that already
        # are one of the two tones change (flowers, pines, outlines stay).
        aL = srgb_to_lab(album_rgb[album_idx].astype(float))[..., 0]
        m = aL.reshape(aL.shape[0] // 2, 2, aL.shape[1] // 2, 2).mean((1, 3))
        loc = ndimage.uniform_filter(m, size=int(win), mode="nearest")
        li, si = color_index(light), color_index(shadow)
        sub, ms, ls = out[y0:y1, x0:x1], m[y0:y1, x0:x1], loc[y0:y1, x0:x1]
        stone = (sub == li) | (sub == si)
        sub[stone & (ms >= ls)] = li
        sub[stone & (ms < ls)] = si
    for x0, y0, x1, y1, c in spec.get("rects", []):
        out[y0:y1, x0:x1] = color_index(c)
    for x0, x1, y, c in spec.get("hlines", []):
        out[y, x0:x1 + 1] = color_index(c)
    for x, y0, y1, c in spec.get("vlines", []):
        out[y0:y1 + 1, x] = color_index(c)
    for x, y, c in spec.get("pixels", []):
        out[y, x] = color_index(c)
    return out, int((out != idx).sum())


def roi_legibility(album_idx, album_rgb, pidx, prgb, rect, thr=8.0):
    """Edge preservation inside rect (puzzle px).
       density_ratio: vertical-neighbour luminance edges per pair, puzzle 128 / album 256.
       recall: edges of the album box-averaged to 128 (both directions) that the puzzle keeps."""
    x0, y0, x1, y1 = rect
    aL = srgb_to_lab(album_rgb[album_idx].astype(float))[..., 0]
    pL = srgb_to_lab(prgb[pidx].astype(float))[..., 0]
    a256 = aL[2 * y0:2 * y1, 2 * x0:2 * x1]
    p = pL[y0:y1, x0:x1]
    dens_a = (np.abs(np.diff(a256, axis=0)) > thr).mean()
    dens_p = (np.abs(np.diff(p, axis=0)) > thr).mean()
    m = a256.reshape(y1 - y0, 2, x1 - x0, 2).mean((1, 3))
    pv, ph = np.abs(np.diff(p, axis=0)) > thr, np.abs(np.diff(p, axis=1)) > thr

    def recall(t):
        tv, th = np.abs(np.diff(m, axis=0)) > t, np.abs(np.diff(m, axis=1)) > t
        return round(float(((tv & pv).sum() + (th & ph).sum()) / max(tv.sum() + th.sum(), 1)), 3)
    # recall_strong (album luminance step >= 15) = structural lines (step shadows, railing and
    # arch outlines); recall (>= thr) also counts stone-surface texture the cleanup removes on purpose.
    return {"rect": list(rect), "density_ratio": round(float(dens_p / max(dens_a, 1e-9)), 3),
            "recall": recall(thr), "recall_strong": recall(15.0)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ref"); ap.add_argument("out_dir"); ap.add_argument("prefix")
    ap.add_argument("--album-size", type=int, default=256)
    ap.add_argument("--album-colors", type=int, default=32)
    ap.add_argument("--album-tiny", type=int, default=2)
    ap.add_argument("--puzzle-size", type=int, default=128)
    ap.add_argument("--puzzle-colors", type=int, default=8)
    ap.add_argument("--puzzle-tiny", type=int, default=3)
    ap.add_argument("--puzzle-weight", type=float, default=0.5,
                    help="palette weight = pixel count ** this (1 = area-driven, lower keeps small hues)")
    ap.add_argument("--blank", action="append", default=[], help="x0,y0,x1,y1[,sx,sy] in reference px")
    ap.add_argument("--palette", default="", help="JSON [{key, color}] fixed sand palette (skips k-means)")
    ap.add_argument("--roi", action="append", default=[],
                    help="name:x0,y0,x1,y1 in reference px; edge preservation is reported per ROI")
    ap.add_argument("--touchup", default="", help="JSON touch-up spec for the puzzle (see apply_touchup)")
    ap.add_argument("--auto-copy", default="", help="also save the puzzle before touch-up to this path")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--report", default="")
    a = ap.parse_args()
    ref = np.array(Image.open(a.ref).convert("RGB"))
    H, W = ref.shape[:2]
    blanks = [[float(v) for v in b.split(",")] for b in a.blank]
    aidx, araw, apal0, _ = make_album(ref, a.album_size, a.album_colors, a.album_tiny, blanks, a.seed)
    album_before = summary(metrics(*compact(araw, apal0)))
    aidx, apal = compact(aidx, apal0)
    album_path = os.path.join(a.out_dir, f"{a.prefix}_album{a.album_size}.png")
    Image.fromarray(apal[aidx]).save(album_path, optimize=True)
    keys = None
    fixed = None
    if a.palette:
        pal = json.load(open(a.palette, encoding="utf-8"))
        keys = [p["key"] for p in pal]
        fixed = [[int(p["color"][i:i + 2], 16) for i in (1, 3, 5)] for p in pal]
    pidx, praw, ppal0 = make_puzzle(aidx, apal, a.puzzle_size, a.puzzle_colors, a.puzzle_tiny, a.puzzle_weight, fixed)
    puzzle_before = summary(metrics(*compact(praw, ppal0)))
    rois = {}
    for r in a.roi:
        name, coords = r.split(":")
        x0, y0, x1, y1 = [float(v) for v in coords.split(",")]
        s = a.puzzle_size
        rois[name] = (int(x0 * s / W), int(y0 * s / H), int(np.ceil(x1 * s / W)), int(np.ceil(y1 * s / H)))
    roi_auto = {n: roi_legibility(aidx, apal, pidx, ppal0, rc) for n, rc in rois.items()}
    touch = None
    if a.touchup:
        if a.auto_copy:
            Image.fromarray(ppal0[pidx].astype(np.uint8)).save(a.auto_copy, optimize=True)
        spec = json.load(open(a.touchup, encoding="utf-8"))
        hexes = ["#%02x%02x%02x" % tuple(c) for c in ppal0]
        def color_index(c):
            return keys.index(c) if keys and c in keys else hexes.index(c.lower())
        before = pidx
        pidx, changed = apply_touchup(pidx, spec, color_index, aidx, apal,
                                      srgb_to_lab(ppal0.astype(float)))
        pidx = merge_small(pidx, spec.get("final_tiny", 0)) if spec.get("final_tiny", 0) else pidx
        touch = {"spec": a.touchup, "changed_pixels": int((pidx != before).sum()),
                 "changed_ratio": round(float((pidx != before).mean()), 4)}
    roi_final = {n: roi_legibility(aidx, apal, pidx, ppal0, rc) for n, rc in rois.items()}
    used_keys = None
    if keys:
        used = np.unique(pidx)
        used_keys = [keys[i] for i in used]
    pidx, ppal = compact(pidx, ppal0)
    puzzle_path = os.path.join(a.out_dir, f"{a.prefix}_puzzle{a.puzzle_size}.png")
    Image.fromarray(ppal[pidx].astype(np.uint8)).save(puzzle_path, optimize=True)
    # fidelity: puzzle vs album box-averaged to puzzle size (mean dE2000)
    f = a.album_size // a.puzzle_size
    alab = srgb_to_lab(apal[aidx].astype(float)).reshape(a.puzzle_size, f, a.puzzle_size, f, 3).mean((1, 3))
    plab = srgb_to_lab(ppal[pidx].astype(float))
    fid = delta_e2000(alab, plab)
    album_m = metrics(aidx, apal)
    album_m.pop("per_color")  # 30+ colors: summary only
    rep = {
        "album": {"path": album_path, "before_cleanup": album_before, **album_m},
        "puzzle": {"path": puzzle_path, "before_cleanup": puzzle_before, **metrics(pidx, ppal)},
        "puzzle_vs_album_mean_de2000": round(float(fid.mean()), 2),
        "puzzle_vs_album_p95_de2000": round(float(np.percentile(fid, 95)), 2),
        "palette_keys": used_keys,
        "touchup": touch,
        "roi_auto": roi_auto,
        "roi_final": roi_final,
    }
    js = json.dumps(rep, ensure_ascii=False, indent=1)
    if a.report:
        open(a.report, "w", encoding="utf-8").write(js)
    print(js)


if __name__ == "__main__":
    main()
