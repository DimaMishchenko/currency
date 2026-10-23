# Deterministic media generation

Python 3.12, Pillow 12.3.0 and `rsvg-convert` are required for design rendering. Install Python dependencies from `requirements.txt` in your own virtual environment. The validated raster stack is librsvg 2.61.3, cairo 1.18.4, pango 1.57.0, harfbuzz 12.2.0 and fontconfig 2.17.1. The header video additionally requires ffmpeg with libx264. Exact PNG encoding also depends on Pillow's linked PNG/zlib and FreeType versions. Record and pin the complete runner when changing artwork.

Approved media is distributed through the independent GitHub release pinned in `../asset-bundle.json`. Use `python3 Marketing/AppStore/fetch_assets.py --repo OWNER/REPOSITORY --output Marketing/AppStore/generator/.local/media` to fetch and verify it without a custom URL or rendering dependencies. App releases can reuse this media version.

Keep input packs, archives and generated output in ignored `.local/`. The input format and licensing boundary are documented in `../design/README.md`. The input pack is not downloadable from this public repository; a maintainer must supply its licensed frozen captures, frames and fonts. Live rate captures cannot recreate the approved historical pixels.

Run from the repository root:

```sh
python3 Marketing/AppStore/generator/generate.py verify-inputs --inputs Marketing/AppStore/generator/.local/inputs
python3 Marketing/AppStore/generator/generate.py render --inputs Marketing/AppStore/generator/.local/inputs --output Marketing/AppStore/generator/.local/preview --locale de-DE
python3 Marketing/AppStore/generator/header.py --inputs Marketing/AppStore/generator/.local/inputs --output Marketing/AppStore/generator/.local/header --video
python3 Marketing/AppStore/generator/header.py --inputs Marketing/AppStore/generator/.local/inputs --output Marketing/AppStore/generator/.local/localized-headers --all-locales --video
python3 -m unittest discover -s Marketing/AppStore/generator/tests -v
```

Repeat `--locale` or `--asset` to narrow rendering. Without selection, all locale masters render. The image bodies are rendered from the editable SVG templates and frozen native bitmaps, then Pillow draws editorial headlines using their exact measured coordinates, font hashes, faces, axes and semantic color spans. Geometry and copy remain editable in `design/`. Preview manifests report `approved_byte_match` per master and never imply approval for changed pixels.

For exact approved delivery, provide the frozen approved archive and H09 header. These commands use Python's standard library without Pillow or librsvg:

```sh
python3 Marketing/AppStore/generator/generate.py unpack --archive APPROVED-BUNDLE.zip --output Marketing/AppStore/generator/.local/media
python3 Marketing/AppStore/generator/generate.py export --archive INPUT.zip --output Marketing/AppStore/generator/.local/approved
python3 Marketing/AppStore/generator/generate.py bundle --archive INPUT.zip --header INPUT.mp4 --output Marketing/AppStore/generator/.local/upload-bundle.zip
```

`unpack` validates the compact approved bundle identity, exact placement mapping, every unique PNG hash/dimension and header hash before extracting media with a sanitized manifest. This is the supported input after retiring the original archive. Use an empty output directory.

`export` verifies the archive identity, all 3,240 PNG hashes and dimensions, then writes placements with a fresh sanitized manifest. It excludes the original archive's private sidecars. Use an empty output directory.

`bundle` verifies approved archive/header identity and all 1,512 unique PNG hashes/dimensions, then creates a deterministic ZIP with fixed member timestamps and permissions. The ZIP contains one PNG per locale master, one header video and `manifest.json`. Its 3,240 placements reference shared master paths. The manifest contract is `{schemaVersion:1, placements:[{locale,profile,family,order,path,sha256,...}], header:{path,sha256}}`. Screenshot profiles are `iphone`, `ipad`, `watch`, `duo-outer` and `duo-inner`. Existing bundle outputs are refused. Neither command publishes or contacts App Store Connect.

Exact archive assembly preserves accepted bytes across platforms. Editable raster generation is reproducible only with the same input bytes and rendering stack. Historical English originals can differ from this renderer; their accepted pixels remain in the frozen archive. Use the approved output for upload and visually review design changes before updating the recipe's approved hashes.

The localized header command writes eighteen 3840 × 1646, silent H.264 videos at 60 fps, posters, a local review gallery and per-locale render proofs. Repeat `--locale` to select editions. Without `--video`, it creates a poster gallery. Add `--gallery-only` with the same locale selection to rebuild the gallery from completed output. Exact background PNGs are shared under `.header-backgrounds/` next to locale output folders; their cache key includes the pixel renderer, layout, font, Pillow and linked FreeType versions. Delete only this generated cache to reclaim its space. `design/header-locales.json` owns the approved language currency priorities: the primary and first two secondary screenshot examples are candidates. The resolver skips currencies without a single currency sign, deduplicates rendered signs (including dollar and yen collisions), then fills three distinct signs from the ordered EUR/USD/GBP/JPY/KRW fallbacks. CHF is skipped; dollar currencies use `$` without alphabetic prefixes. Proofs and gallery labels record the resolved currency codes. The center tiles and their replacement reels use those signs; the peripheral rails, geometry, Nunito face, 15-second period, leftward scroll and early reel timing remain fixed. These outputs require review and do not replace the approved bundle or its release pointer. Rendering checks all 900 unique input frames, exact raw scene/reel return, repeating rail textures and the encoded duration, dimensions, frame count and BT.709 color tags. Exact video bytes depend on the same Pillow/FreeType and ffmpeg/libx264 versions.

Localized delivery uses `header-map.json` from a complete video gallery. Its `headers` object maps each locale to a relative `path` and `sha256`; every screenshot locale must be present. Pin reviewed hashes in a candidate recipe's `approved_header_sha256_by_locale`, then pass `--headers header-map.json` instead of `--header` to `bundle`. Bundle media paths use content hashes, so identical editions share one MP4. `unpack` checks the complete locale map and every unique video's bytes against that recipe. A recipe with localized headers refuses a global fallback. Existing single-header recipes and bundles remain supported.

Gallery generation requires the current pixel-renderer/configuration/runtime identity, matching poster bytes, completed 900-frame video proof and the actual MP4 hash. Poster-only renders cannot authorize an old video left in the output directory. Pixel-code fingerprints exclude gallery/proof orchestration; each render also records its actual full script hash. All localized media remains a review candidate until approved and pinned in a new asset version.

When the original placement archive has been retired, reuse its pinned compact bundle without regenerating screenshots:

```sh
python3 Marketing/AppStore/generator/generate.py --recipe Marketing/AppStore/generator/.local/assets-v2/recipe.json bundle \
  --base-bundle Marketing/AppStore/generator/.local/Currency-AppStore-Approved.zip \
  --base-recipe Marketing/AppStore/design/recipe.json \
  --headers Marketing/AppStore/generator/.local/localized-headers/header-map.json \
  --output Marketing/AppStore/generator/.local/assets-v2/Currency-AppStore-Approved.zip
```

The candidate recipe must retain the existing screenshot mapping and pin every localized header hash. The base recipe independently pins the source bundle; every source member is checked before reuse. This command creates only a local bundle. Update the candidate bundle hash before checking it with `unpack`; publish and change the public asset pin only after separate approval.
