# Currency icons

The twelve editable Icon Composer documents live in `Apps/Currency/App/Resources/*.icon`. World Yen / Yuan is the primary icon; the Watch uses the same default artwork. Settings offers six currency variants in each World and Grid family. Native icon documents own their glass materials and platform appearances.

`Layers/` contains the vector cutouts, including the custom Bitcoin outline. Ordinary symbols use the bundled Nunito font under the SIL Open Font License in `Fonts/OFL.txt`. The dollar artwork stays fixed across each family. No SF Symbols artwork is embedded in the icons.

To rebuild raster layers with an existing Playwright installation:

```sh
CURRENCY_PLAYWRIGHT_MODULE=/path/to/playwright node Marketing/Icons/render.mjs
```

Optionally set `CURRENCY_CHROMIUM_PATH` to an existing Chromium executable. The script writes rebuilt documents to `.validation/icons` by default; pass another output directory as the first argument. It reads material metadata from the production documents and does not replace them. Chromium/font rasterization may vary between versions; review rebuilt artwork before copying it into production.

Open the documents in Icon Composer to export appearances. Settings preview images are 216-pixel iOS Default and Dark exports, stored in the corresponding feature asset catalogs. Keep those previews synchronized with any approved artwork changes. Apply approved primary-icon changes to the Watch document as well.
