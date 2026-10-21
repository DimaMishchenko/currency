# App Store assets

`metadata.json` contains the approved name, subtitle, description, keywords and promotional text for eighteen App Store localizations. The widget-focused default page has five contextual alternatives: Offline, Travel, History, Crypto and Metals. The app name and subtitle are shared across custom product pages; their screenshots and promotional text vary.

`design/` and `generator/` hold editable, portable screenshot and header recipes. Icon Composer documents and icon generation sources are documented in [../Icons/README.md](../Icons/README.md).

Generated PNGs, native captures, licensed device frames, system fonts, private evidence, credentials and delivery archives are excluded from Git. Do not commit an asset archive or an App Store Connect API key. The source recipes contain hashes and relative object references, not developer paths or simulator identifiers.

## Reproduce images

Install the pinned Python dependencies in `generator/requirements.txt`, plus `rsvg-convert` for screenshot bodies and FFmpeg for header video. See [generator/README.md](generator/README.md) for exact commands and input-pack layout.

A frozen input pack is required: native app captures and licensed Apple resources cannot be reconstructed from public source alone. Keep it in private storage and acquire Apple resources under their applicable licenses. Fresh captures use changing rates and may differ from the approved screenshots. Editable rendering produces review candidates; the approved delivery archive is the authority for exact original PNG bytes. Preserve both when changing designs. Do not upload a preview manifest as approved delivery.

## Delivery setup

The manually dispatched **App Store Draft Assets** workflow prepares drafts; it does not submit for review or release an app. It uses the existing `testflight` GitHub environment and its App Store Connect API secrets. No duplicate API key or second environment is needed. The workflow remains manually dispatched, restricted to `main`, and defaults to dry-run.

Reuse the three existing API secrets below. Add only the asset bundle URL to the same `testflight` environment:

| Secret | Value |
| --- | --- |
| `ASC_API_KEY_ID` | App Store Connect API key ID |
| `ASC_API_ISSUER_ID` | API issuer ID |
| `ASC_API_CERT` | Base64-encoded API private key |
| `APP_STORE_ASSET_BUNDLE_URL` | HTTPS download URL for the sanitized approved media bundle |

The current sanitized bundle is **858,144,096 bytes**, containing 1,512 unique screenshots referenced by 3,240 placements plus one header video. Its identity is recorded in `asset-bundle.json`.

The existing API key must have access to this app and permission to edit its metadata and assets; upload-only permissions may need to be expanded. Store the immutable media bundle outside the public repository. Its SHA-256 belongs in the workflow dispatch inputs; verify it against the local generation receipt. URLs granting access to private storage are credentials and belong only in secrets. This is a one-time storage/setup step, not a per-screenshot upload.

Select the exact editable app version, corresponding editable app-info ID, and approved media checksum from `asset-bundle.json`. First run the dry-run plan. Review the sanitized plan, then explicitly select apply. Do not reuse IDs from a different version or guess them. Existing privacy/support/marketing links and release notes remain account-owned unless explicitly supplied in metadata.

The IDs can be inspected locally with read-only calls using the pinned CLI and the same environment authentication:

```sh
asc api GET /v1/apps/6816213577/appStoreVersions --output json --paginate
asc api GET /v1/apps/6816213577/appInfos --output json --paginate
```

For a local dry-run (omit `--apply`), supply those exact editable IDs:

```sh
python3 Marketing/AppStore/upload.py --metadata Marketing/AppStore/metadata.json \
  --bundle APPROVED-BUNDLE.zip --bundle-sha256 APPROVED_SHA256 \
  --version-id VERSION_ID --version-string VERSION --app-info-id APP_INFO_ID \
  --scope metadata,default,cpp,duo,header \
  --receipts Marketing/AppStore/.local/receipts.jsonl
```

The workflow keeps only sanitized resource-ID receipts for seven days. Keep the downloaded receipt before retrying an interrupted apply. Raw API responses and signed upload URLs are suppressed.

The workflow uploads localized text, the default device screenshot sets, contextual custom product page drafts, native Duo placements and the fifteen-second H09 product page header. It checks the complete input before applying changes and refuses conflicting existing assets rather than deleting unrecognized screenshots. An interrupted upload can leave draft resources; inspect the sanitized receipt and remote IDs before retrying.

## Remaining release actions

- Upload a signed app build to deliver primary/alternate icons. The metadata workflow cannot change binary icons. Existing TestFlight publishing builds the checked-in Icon Composer documents.
- Select the release build and complete account declarations: privacy, age rating, export compliance, pricing/availability, agreements and review contact information. These are not inferred from marketing assets.
- Review and submit the app version and custom product pages. Media processing or a successful upload is not Apple approval or storefront publication.
- Configure organic custom-page keyword associations only from keywords eligible on the latest approved version. The first release may need approval before those selectors exist. Direct page URLs and campaigns are separate routing choices; language localization does not provide arbitrary country-level screenshot targeting.
- Inspect the first authorized Duo upload on the app record. Both poses share Apple's `IPHONE_DUO_PROFILE`; the uploader places six outer and six inner images with explicit order. This documented API path has mock coverage but has not been exercised against this app's live record.

No app preview video is included. The H09 video is product page header artwork, a different asset type.

## Checks

```sh
python3 -m unittest discover -s Marketing/AppStore/tests -v
python3 -m unittest discover -s Marketing/AppStore/generator/tests -v
```

The upload adapter is tested without credentials using a fake CLI. A successful local test is not evidence of a live App Store Connect upload.

## References

- [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- [Apple creative asset specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications/)
- [Apple custom product pages](https://developer.apple.com/help/app-store-connect/create-custom-product-pages/configure-multiple-product-page-versions/)
- [Pinned asc asset-library guide](https://github.com/rorkai/App-Store-Connect-CLI/blob/5.16.0/guides/asset-library.mdx)
