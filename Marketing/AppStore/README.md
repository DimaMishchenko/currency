# App Store assets

`metadata.json` contains the approved name, subtitle, description, keywords and promotional text for eighteen App Store localizations. The widget-focused default page has five contextual alternatives: Offline, Travel, History, Crypto and Metals. The app name and subtitle are shared across custom product pages; their screenshots and promotional text vary.

`asset-bundle.json` pins the approved media to an independent GitHub asset release, currently `app-store-assets-v1`. The ZIP contains 1,512 unique screenshots referenced by 3,240 placements, the fifteen-second H09 header and `manifest.json`. Media binaries stay out of Git history; no Git LFS, external hosting account or download-URL secret is needed.

`design/` and `generator/` hold editable screenshot and header recipes. Icon Composer documents and icon generation sources are documented in [../Icons/README.md](../Icons/README.md). Generated media, native captures, system fonts, private source packs, evidence, credentials and delivery archives remain excluded from Git. Never commit an App Store Connect API key.

## Edit and validate

Install the pinned Python dependencies in `generator/requirements.txt`, plus `rsvg-convert` for screenshot bodies and FFmpeg for header video. See [generator/README.md](generator/README.md) for rendering commands and input-pack layout. Rendering requires the private frozen source pack, including native app captures and licensed resources. Downloading and uploading the approved final assets does not require that pack.

Editable rendering produces review candidates. Approve media changes before packaging a new asset version. The unpacked manifest uses `schemaVersion: 1`: placements record `locale`, `profile`, `family`, `order`, `path` and `sha256`; the header records `path` and `sha256`. Paths are relative to the unpacked directory, and placements may share a PNG.

Download the exact release asset, verify its pinned byte count and SHA-256, then unpack into an empty ignored directory:

```sh
python3 Marketing/AppStore/fetch_assets.py --repo OWNER/REPOSITORY \
  --output Marketing/AppStore/generator/.local/media
python3 Marketing/AppStore/upload.py --validate-only \
  --media-dir Marketing/AppStore/generator/.local/media
```

The fetch helper uses `gh release download` with the explicit repository, tag and exact filename from `asset-bundle.json`. It checks that the configuration SHA-256 matches `design/recipe.json` before download, checks size and checksum before unpacking, and only promotes a verified extraction to the output directory. It refuses nonempty output and removes partial candidates on failure. An existing verified directory can be reused directly for validation or uploading.

Validation requires `ffprobe` from FFmpeg. It makes no App Store requests and checks every file's SHA-256, PNG dimensions and alpha/transparency, placement completeness, and the approved fifteen-second 3840×1646 header at 30/60 fps. The same validation runs before any remote planning or applying.

## Independent asset versions

App versions and asset versions are separate. App 1.0 and 1.1 can both use `app-store-assets-v1`; a text-only metadata change stays in Git and does not require a new media release. Bump to `app-store-assets-v2` only when the approved media or placement mapping changes, and update `asset-bundle.json` plus the matching approved recipe hashes together. Never replace the bytes under an existing asset version.

To publish a newly approved media version, create a new tag rather than updating the old release:

```sh
gh release create app-store-assets-v2 APPROVED-BUNDLE.zip \
  --target REVIEWED_COMMIT --title "App Store assets v2" \
  --notes-file ASSET-NOTES.md --prerelease --latest=false
```

Keep the filename in `asset-bundle.json` identical to the uploaded asset name. Commit the new tag, byte count, SHA-256 and approved recipe together, then use that source revision for delivery. App version bumps do not change this pin.

Publish asset-only releases with `--prerelease --latest=false`. Here “prerelease” categorizes a media distribution package separately from app releases; it does not mean the artwork is unapproved. This keeps asset packs out of GitHub's latest stable release selection. Delivery always uses the explicit configured tag and never a `latest` endpoint. Release creation is a separate authorized publishing step, not an action performed by the upload workflow.

## Delivery setup

The manually dispatched **App Store Draft Assets** workflow prepares drafts; it does not submit for review or release an app. It uses the existing `testflight` GitHub environment and its App Store Connect API secrets. No duplicate key, second environment or asset-storage secret is needed. GitHub asset downloads use the workflow's existing `github.token` with `contents: read`. The workflow is restricted to `main` and defaults to dry-run.

| Existing secret | Value |
| --- | --- |
| `ASC_API_KEY_ID` | App Store Connect API key ID |
| `ASC_API_ISSUER_ID` | API issuer ID |
| `ASC_API_CERT` | Base64-encoded API private key |

The existing API key must have access to this app and permission to edit metadata and assets. Leave target fields blank to discover the unique editable iOS app version and unique editable app-info draft. Discovery stops when either target is missing or ambiguous; it never creates an app version or guesses a version number. Optionally supply a version ID, version string or app-info ID to narrow the candidates. First run the dry-run plan, review the resolved target IDs and sanitized operations, then explicitly select apply. Existing privacy/support/marketing links and release notes remain account-owned unless supplied in metadata.

Inspect IDs locally with pinned asc 5.16.0 and the same environment authentication:

```sh
asc api GET /v1/apps/6816213577/appStoreVersions --output json --paginate
asc api GET /v1/apps/6816213577/appInfos --output json --paginate
```

Run a local read-only plan using unique-target discovery:

```sh
python3 Marketing/AppStore/upload.py \
  --media-dir Marketing/AppStore/generator/.local/media \
  --scope metadata,default,cpp,duo,header \
  --receipts Marketing/AppStore/.local/receipts.jsonl
```

Add `--apply` only after reviewing the plan. `--media-dir` selects a verified unpacked asset directory; `--metadata` defaults to the sibling JSON file. Remote plans and apply require a receipt path. Optional `--version-id`, `--version-string` and `--app-info-id` filters must match the selected editable targets; wrong or live-only filters fail without falling back to another draft. The selected IDs and version string are printed without raw API responses, then checked again during complete preflight before changes. `--validate-only` requires no target inputs, credentials or receipt path and cannot be combined with apply.

The workflow uploads localized text, default device screenshot sets, contextual custom product page drafts, native Duo placements and the H09 product page header. Before any changes, native Duo/header preflight reads Apple’s current asset reference data, resolves placement groups through compatible specifications, and checks each applicable App Store version/CPP group limit. Unknown specifications/policies or insufficient capacity stop the whole selected plan. If both Duo poses map to one group, the approved six outer plus six inner screenshots require twelve slots in that group; the uploader never truncates them to fit. Select supported scopes separately or approve a revised mapping when Apple’s limit is lower. Capacity diagnostics contain only feature/type/group identifiers and counts. It refuses conflicting existing assets rather than deleting unrecognized screenshots. Interrupted uploads can leave draft resources: inspect remote state and the sanitized resource-ID receipt before retrying. The workflow preserves these receipts for seven days and suppresses raw API responses and signed upload URLs.

## Remaining release actions

- Upload a signed app build to deliver primary/alternate icons. Existing TestFlight publishing builds the checked-in Icon Composer documents; metadata uploads cannot change binary icons.
- Select the release build and complete account declarations: privacy, age rating, export compliance, pricing/availability, agreements and review contact information.
- Review and submit the app version and custom product pages. Processed uploads do not establish Apple approval or storefront publication.
- Configure organic custom-page keyword associations from terms eligible on the latest approved version. The first release may need approval before these exist. Direct page URLs and campaigns are separate routing choices; localization does not provide arbitrary country-level screenshot targeting.
- Inspect the first authorized Duo upload. The uploader uses runtime-discovered groups and orders six outer and six inner images within their respective groups only when current per-group limits allow the complete approved mapping. The documented API path has mock coverage but has not been exercised against this app's live record.

No app preview video is included. H09 is product page header artwork, a different asset type.

## Checks

```sh
python3 -m unittest discover -s Marketing/AppStore/tests -v
python3 -m unittest discover -s Marketing/AppStore/generator/tests -v
python3 Marketing/AppStore/upload.py --validate-only \
  --media-dir Marketing/AppStore/generator/.local/media
```

Unit tests use a fake CLI and require no credentials or media downloads. Local checks are not evidence of a live App Store Connect upload.

## References

- [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Apple creative asset specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications/)
- [Apple custom product pages](https://developer.apple.com/help/app-store-connect/create-custom-product-pages/configure-multiple-product-page-versions/)
- [Pinned asc asset-library guide](https://github.com/rorkai/App-Store-Connect-CLI/blob/5.16.0/guides/asset-library.mdx)
