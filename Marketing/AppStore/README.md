# App Store assets

`metadata.json` contains the approved name, subtitle, description, keywords and promotional text for eighteen App Store localizations. The widget-focused default page has five contextual alternatives: Offline, Travel, History, Crypto and Metals. The app name and subtitle are shared across custom product pages; their screenshots and promotional text vary.

`asset-bundle.json` pins the approved media to an independent GitHub asset release, currently `app-store-assets-v1`. The ZIP contains 1,512 unique screenshots referenced by 3,240 placements, the fifteen-second H09 header and `manifest.json`. Media binaries stay out of Git history; no Git LFS, external hosting account or download-URL secret is needed.

`design/` and `generator/` hold editable screenshot and header recipes. Icon Composer documents and icon generation sources are documented in [../Icons/README.md](../Icons/README.md). Generated media, native captures, system fonts, private source packs, evidence, credentials and delivery archives remain excluded from Git. Never commit an App Store Connect API key.

## Edit and validate

Install the pinned Python dependencies in `generator/requirements.txt`, plus `rsvg-convert` for screenshot bodies and FFmpeg for header video. See [generator/README.md](generator/README.md) for rendering commands and input-pack layout. Rendering requires the private frozen source pack, including native app captures and licensed resources. Downloading and uploading the approved final assets does not require that pack.

Editable rendering produces review candidates. Approve media changes before packaging a new asset version. The unpacked manifest uses `schemaVersion: 1`: placements record `locale`, `profile`, `family`, `order`, `path` and `sha256`; the legacy `header` records `path` and `sha256`. A localized bundle instead records `headers`, mapping all eighteen locales to `{path, sha256}`. A supplied locale map must be complete; a global fallback is refused. Identical video hashes share one bundled file and one Asset Library upload. The uploader selects the locale’s header for both default and custom product pages, preserving existing placement conflict and readback checks. Paths are relative to the unpacked directory, and placements may share a PNG.

Download the exact release asset, verify its pinned byte count and SHA-256, then unpack into an empty ignored directory:

```sh
python3 Marketing/AppStore/fetch_assets.py --repo OWNER/REPOSITORY \
  --output Marketing/AppStore/generator/.local/media
python3 Marketing/AppStore/upload.py --validate-only \
  --media-dir Marketing/AppStore/generator/.local/media
```

The fetch helper uses `gh release download` with the explicit repository, tag and exact filename from `asset-bundle.json`. It checks that the configuration SHA-256 matches `design/recipe.json` before download, checks size and checksum before unpacking, and only promotes a verified extraction to the output directory. It refuses nonempty output and removes partial candidates on failure. An existing verified directory can be reused directly for validation or uploading.

Validation makes no App Store requests and always checks every file's SHA-256, PNG dimensions and alpha/transparency, and placement completeness. The default scope includes `header` and requires `ffprobe` from FFmpeg to verify the fifteen-second 3840×1646 video at 30/60 fps. Scopes without `header` verify its hash and report `verifiedHeader: false`. The same scope-aware validation runs before remote planning or applying; finish with a full-scope audit.

## Independent asset versions

App versions and asset versions are separate. App 1.0 and 1.1 can both use `app-store-assets-v1`; a text-only metadata change stays in Git and does not require a new media release. The `duoPresentation` delivery selection stays in metadata Git history and reuses approved files. Bump to `app-store-assets-v2` when approved media or the bundle manifest changes, and update `asset-bundle.json` plus the matching approved recipe hashes together. Never replace the bytes under an existing asset version.

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

The workflow uploads localized text, default device screenshot sets, contextual custom product page drafts, native Duo placements and the H09 product page header. Shared metadata uses pinned `asc metadata apply` with canonical app-info/version locale files, explicit targets and a read-only plan before apply. Omitted fields remain untouched; nulls, clears, default fallback files and locale deletion are disabled. CPP text and asset placement remain separately scoped.

Missing custom product pages are created through pinned `asc product-pages custom-pages create`, which supplies an initial version and localization in the app’s primary language. The uploader resolves that initial draft and reuses existing pages/localizations before adding the approved text and assets. Any remote creation error stops apply without attributing it to a release-state prerequisite.

Custom product pages use the iPhone and iPad screenshot sets. Apple’s current `CUSTOM_PRODUCT_PAGES` reference policy omits Watch, so preflight reports that exclusion while retaining all 108 Watch screenshots on the default page. Core CPP profiles require matching specifications and capacity for six screenshots; unknown or insufficient policies stop before changes. Eligibility follows Apple’s [asset specifications and feature policies](https://developer.apple.com/documentation/appstoreconnectapi/discovering-asset-specifications), checked again at runtime.

Duo uses six images per page, mixing inner and outer displays once per feature. `duoPresentation` selects the display for each of the six existing positions in every family; the complete two-pose source sets remain in the immutable media pack. Native preflight reads Apple’s reference data and checks the selected group capacities. Reconciliation reads placements in Apple’s saved display order and requests reordering only for groups that differ from the approved sequence. Exact pixel dimensions take precedence over nominal aspect-ratio labels; flexible-size specifications still enforce ratios. Unknown or insufficient policies stop the selected plan before changes.

Use `inspect-native-policy` for a read-only catalog report without downloading media or resolving an app draft. It emits only typed global specifications and limits. Inspections use a separate concurrency group; draft mutations remain serialized. Raw API responses, private error details and signed upload URLs stay suppressed. Failure diagnostics expose only bounded HTTP statuses, structured error identifiers and field pointers.

The uploader refuses conflicting existing assets instead of deleting them. Complete screenshots whose checksums match a unique subset of the approved set can resume: default pages use `--skip-existing`; custom pages upload only missing images and restore the approved order after verifying all six asset identities. Canonical membership and order are checked during planning and after upload; sets are rechecked immediately before upload, and ordering changes are read back. Unknown, duplicate, failed or still-processing assets stop reconciliation. Upload and Apple processing waits allow thirty minutes per batch, within the uploader’s thirty-five-minute command deadline. It refreshes missing localization identities immediately before creation so late resources can be reused without duplicate POST retries. Interrupted uploads can leave draft resources: inspect remote state and the sanitized resource-ID receipt before retrying. Receipts are retained for seven days.

`--remove-approved-duplicate SCREENSHOT_ID` explicitly permits one redundant copy to be removed from a verified seven-image gallery. Dry-run reports the exact removed and retained IDs, approved checksum, byte size and gallery; apply rechecks the evidence, retains the first ordered copy, deletes only the selected later copy and verifies the remaining six identities and saved order. Foreign assets, changed evidence and ambiguous failures stop the repair. Omit the flag for subsequent verification and normal resumption; no bulk replacement or automatic duplicate cleanup occurs.

## Remaining release actions

- Upload a signed app build to deliver primary/alternate icons. Existing TestFlight publishing builds the checked-in Icon Composer documents; metadata uploads cannot change binary icons.
- Select the release build and complete account declarations: privacy, age rating, export compliance, pricing/availability, agreements and review contact information.
- Complete the [DSA trader-status declaration](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/). Complete the [Digital Goods and Services questionnaire](https://developer.apple.com/help/app-store-connect/manage-app-information/complete-the-digital-goods-and-services-questionnaire/) if it appears. [Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/) are currently optional and require their own evaluation before claiming support.
- Review and submit the app version and eligible custom product pages. Processed uploads do not establish Apple approval or storefront publication.
- Configure organic custom-page keyword associations from terms eligible on the latest approved version. The first release may need approval before these exist. Direct page URLs and campaigns are separate routing choices; localization does not provide arbitrary country-level screenshot targeting.
- Inspect the processed Duo screenshots in App Store Connect’s product-page preview before submission. The mixed six-image selection uses the single Duo placement group and current live capacity limits.

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
