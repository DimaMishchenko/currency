# Screenshot design source

`recipe.json` maps 1,512 locale masters to 3,240 ordered placements across eighteen locales, five device profiles and six variants. Thirty-three shared SVG geometry templates retain the approved composition, device apertures, native screenshot placement and nested source `viewBox` crops. The recipe supplies each template's bitmap slots and editable headline runs, baseline coordinates, measured font sizes, font faces and variable axes. Watch listing masters use their full frozen native capture directly.

The recipe deliberately contains no simulator identities, proof documents, local filesystem paths or release audit material. It describes composition, not native capture verification or permission to publish.

`input-manifest.json` defines the external frozen input pack. Each entry is addressed by SHA-256 and records its byte length and input roles. Put the exact bytes at `objects/<sha256>` under a private input directory. The renderer validates every consumed object. Native captures are immutable bitmap inputs: the generator composes and crops them using SVG geometry; it does not redraw or translate the app UI. Headline text is separate from native UI.

`header.svg` is the editable H09 currency symbol layout. The header renderer uses the geometry to create its repeating background and three animated currency reels. `header-locales.json` selects each language edition’s primary and first two secondary currency examples for the center tiles and replacement spins. Currency glyphs use Nunito; disambiguating prefixes retain the local dollar identity.

The approved archive and header hashes identify the accepted output authority. Existing English originals used a different historical rendering path. Editing a design or rerendering an original requires visual review before replacing its accepted pixels.

# External input rights

Native captures, Apple device frames, masks and system fonts are intentionally excluded from the repository. Obtain and use them under their applicable rights. Do not redistribute the local input pack: it may contain Apple licensed materials and system fonts. A shared CI input package must omit system font files; provide matching licensed fonts on the runner locally before rendering. The approved output bundle contains final screenshots and header only, with a sanitized placement manifest.

Nunito is licensed under the SIL Open Font License in `Nunito-OFL.txt`. Its frozen font bytes are external inputs too. The public source retains the license so the font can be sourced lawfully and identified by the recipe hash.
