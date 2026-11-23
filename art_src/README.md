# art_src — landscape source material (not game content)

`art_src/.gdignore` makes Godot skip this folder: nothing here is imported, loaded by the
game, or packed into the Android build. Game-side candidates live in `assets/destinations/`.

Committed (sources):
- reference images, e.g. `gyeongju/bulguksa_reference.png` (v1), `bulguksa_reference_v2.png`
- fixed sand palettes, e.g. `gyeongju/gyeongju_palette8.json` (key, name_ko, color)
- puzzle touch-up specs, e.g. `gyeongju/gyeongju_s1_v2_touchup.json`

Not committed (regenerated review outputs, see `.gitignore`): `*_comparison.png`,
`*_auto.png`, `*_report.json`, `album_display_check.png`.

Regenerate the Bulguksa v2 candidates (album 256 + puzzle 128):

    python tools/landscape_pipeline.py art_src/gyeongju/bulguksa_reference_v2.png \
        assets/destinations/gyeongju gyeongju_s1_v2 \
        --blank 535,423,717,482,545,452 --puzzle-tiny 5 \
        --palette art_src/gyeongju/gyeongju_palette8.json \
        --touchup art_src/gyeongju/gyeongju_s1_v2_touchup.json \
        --auto-copy art_src/gyeongju/gyeongju_s1_v2_puzzle128_auto.png \
        --roi stairs_all:330,570,930,1200 --roi upper_flight:470,600,790,770 \
        --roi arch:490,790,750,965 --roi lower_flight:350,965,910,1190 \
        --roi rail_left:255,830,445,1190 --roi rail_right:805,830,1000,1190 \
        --report art_src/gyeongju/gyeongju_s1_v2_report.json

Check against the game's loader: `godot --headless --path . -s res://tests/check_landscape_candidate.gd -- <puzzle.png> <album.png>`
