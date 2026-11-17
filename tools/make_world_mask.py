"""Builds assets/ui/world_land_480x180.png (1 = land) for the world/continent maps.

Source: Natural Earth 1:50m land (public domain) via the world-atlas npm package
(https://cdn.jsdelivr.net/npm/world-atlas@2.0.2/land-50m.json).
Projection: equirectangular, 0.75 degrees per pixel, x = 0 at lon -30 (Europe left,
Americas right), y = 0 at lat 78N, 180 rows down to lat 57S. Matches MapArt in
scripts/ui/map_art.gd.

    python tools/make_world_mask.py land-50m.json assets/ui/world_land_480x180.png
Needs numpy + opencv-python.
"""
import json, sys
import numpy as np, cv2

DEG, LON0, LAT0, W, H = 0.75, -30.0, 78.0, 480, 180
SS = 8  # supersampling per output pixel

def decode(topo):
    sx, sy = topo["transform"]["scale"]; tx, ty = topo["transform"]["translate"]
    arcs = []
    for arc in topo["arcs"]:
        x = y = 0; pts = []
        for dx, dy in arc:
            x += dx; y += dy; pts.append((x * sx + tx, y * sy + ty))
        arcs.append(pts)
    def ring(idx):
        out = []
        for i in idx:
            pts = arcs[i] if i >= 0 else arcs[~i][::-1]
            out.extend(pts if not out else pts[1:])
        return out
    polys = []
    for g in topo["objects"]["land"]["geometries"]:
        groups = [g["arcs"]] if g["type"] == "Polygon" else g["arcs"]
        for p in groups:
            polys.append([ring(r) for r in p])
    return polys

def to_px(r):
    xs, ys, prev = [], [], None
    for lon, lat in r:
        x = ((lon - LON0) % 360.0) / DEG
        if prev is not None:
            while x - prev > W / 2: x -= W
            while prev - x > W / 2: x += W
        prev = x
        xs.append(x * SS); ys.append((LAT0 - lat) / DEG * SS)
    return np.round(np.stack([xs, ys], 1)).astype(np.int32)

def main(src, dst):
    polys = decode(json.load(open(src, encoding="utf8")))
    big = np.zeros((H * SS, W * SS), np.uint8)
    for p in polys:
        rings = [to_px(r) for r in p]
        for shift in (-W * SS, 0, W * SS):
            off = np.array([shift, 0], np.int32)
            cv2.fillPoly(big, [rings[0] + off], 1)
            if len(rings) > 1:
                cv2.fillPoly(big, [r + off for r in rings[1:]], 0)
    frac = big.reshape(H, SS, W, SS).mean(axis=(1, 3))
    out = np.where(frac >= 0.43, 255, 0).astype(np.uint8)
    cv2.imwrite(dst, out)
    print("land cells:", int((out > 0).sum()), "of", W * H)

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
