# Currency website

One landing and an illustrated widget setup guide per locale, plus canonical English privacy and terms pages. `Documentation/PrivacyPolicy.md` and `Documentation/TermsOfUse.md` own policy copy. No accounts or automatic language redirects. Production pages at `currency.dimasike.com` include cookie-free Cloudflare Web Analytics; preview and alternate-host builds omit the beacon. The shared `dimasike.com` analytics site records subdomain traffic separately by hostname. The prelaunch email form loads Cloudflare Turnstile only when opened.

## Build and review

From the repository root:

```sh
python3 Website/scripts/build.py
python3 Website/scripts/serve.py
python3 Website/scripts/check-seo.py --directory Website/.local/dist
node Website/tests/calculator.cjs
node Website/tests/waitlist.cjs
python3 Website/tests/waitlist-build.py
node Website/tests/localization.cjs Website/.local/dist
```

The build produces 30 pages across 14 language variants. The manifest in `locales/manifest.json` owns language names and routes: English at `/`, then `/de/`, `/fr/`, `/es/`, `/it/`, `/pt-br/`, `/ja/`, `/ko/`, `/tr/`, `/ru/`, `/uk/`, `/zh-hans/`, `/zh-hant/`, `/et/`. Each has a `/support/` child. Regional English, French and Spanish are consolidated; Simplified and Traditional Chinese stay separate. Policies remain English at `/privacy/` and `/terms/`.

`locales/en-US.json` owns source text keys. Update every catalog when copy changes; the build rejects incomplete catalogs and unknown source text. The language picker preserves landing versus Support context. Calculator numbers, decimal keys and accessibility labels follow the selected locale; rates are fixed examples, not live quotes.

For isolated responsive checks:

```sh
python3 Website/scripts/prepare-review.py --site-dir Website/.local/dist --all-locales
```

This creates review frames for landing/Support in all locales at 320, 390, 768, 1024 and 1280 pixels. Check actual language switching, tab images and keyboard navigation, calculator input, support anchors, FAQs, translated wrapping and system Reduce Motion in the browser. No app code changes or simulator tests are needed.

## Launch waitlist

`launch.json` controls the launch state and contains only the public signup endpoint and Turnstile site key. With `prelaunch: true`, every App Store link opens the localized signup dialog; official Apple badges remain unchanged. Set the public site key before publishing and configure its allowed hostname as `currency.dimasike.com`. The managed challenge is loaded only after opening the dialog. Submitting the launch notification form expresses consent to the one launch email described above the field and on the button. Submissions require a valid email and a fresh challenge token.

The Worker stores signups in a private Cloudflare D1 database for one manual launch notification. No mailing service is connected. The browser keeps no email in storage or URLs and clears the field on success or close. See `waitlist-worker/README.md` for deployment and retention operations. Set `prelaunch: false` and rebuild to restore direct App Store links and remove the form and challenge integration.

## Deployment

The `Website` workflow validates pull requests and deploys changes on `main` to GitHub Pages. A manual run on `main` also redeploys. It uses the built-in GitHub token and Pages OIDC, without additional deployment secrets. The optional waitlist Worker and D1 database are deployed separately. Only the production output is uploaded; source scripts, tests and local evidence are excluded.

In repository Settings → Pages, select **GitHub Actions** as the publishing source before the first deployment. The initial address is `https://dimamishchenko.github.io/currency/`. The workflow reads Pages' configured URL, so routes, canonical links, language alternates and the sitemap match the active host and path. No `CNAME` is committed. Configure `currency.dimasike.com` and DNS later in Pages settings, then rerun the workflow to rebuild for that domain.

## Production

```sh
python3 Website/scripts/build.py --production --output Website/.local/production
python3 Website/scripts/check-seo.py --directory Website/.local/production --production
```

The canonical domain is `https://currency.dimasike.com/`. `--base-url` supports other hosts or path prefixes. Production pages have self-canonicals, reciprocal locale alternates with `x-default`, translated social metadata, structured app/site data and all 30 URLs in the sitemap. Important content is static HTML; JavaScript enhances tabs and the calculator. All routes are allowed to search/retrieval crawlers. No fabricated ratings or special hidden AI copy are generated.

Before publishing:

- Configure DNS/HTTPS and deploy only the fresh production output. The builder refuses an output containing review frames. Never use `serve.py` as the production server: it deliberately sends `X-Robots-Tag: noindex`.
- Verify live HTTP responses, assets, robots and sitemap. Host/CDN bot rules must permit search/retrieval crawlers without login or challenges.
- Verify the domain in Google Search Console and Bing Webmaster Tools, submit `/sitemap.xml`, and inspect the live URLs and structured data. Measure real-host mobile Core Web Vitals.
- Confirm App Store ID `6816213577` is publicly downloadable. Connect the App Store marketing URL and repository About link to the canonical website.

Preview builds remain unindexed. Eligibility does not guarantee indexing, ranking or AI citations. Google app-rich-result eligibility additionally needs genuine visible ratings/reviews, which are not fabricated here.

## Artwork reproduction

Restore the approved App Store generator inputs, then run the following for each distinct `assets` locale in `locales/manifest.json`:

```sh
python3 Website/scripts/build-assets.py --locale en-US
python3 Website/scripts/build-device-scenes.py --locale en-US
```

After all native sets exist:

```sh
python3 Website/scripts/fetch-badges.py
python3 Website/scripts/build-social.py
```

Native extraction and social rendering require Pillow and `rsvg-convert`; inputs default to `Marketing/AppStore/generator/.local/inputs/objects`. Fonts and frames come from approved inputs. Nunito’s license accompanies the shared font. App Store badges are downloaded unchanged from Apple and served locally at their original proportions.

The website uses approved localized App Store captures for its selected languages. Estonian is also supported by the app and website; it currently uses English product captures because the approved App Store pack has no Estonian set. Its copy, calculator, badge and social text are localized. iPad/Duo illustrations arrange native widget assets within official frames; they are Home Screen illustrations rather than additional app captures. The source World Yen icon is the app’s `AppIcon.icon`.

Primary guidance: [Google multilingual pages](https://developers.google.com/search/docs/specialty/international/managing-multi-regional-sites), [Google AI search](https://developers.google.com/search/docs/fundamentals/ai-optimization-guide), [Bing/Copilot](https://www.bing.com/webmasters/help/bing-webmaster-guidelines-30fba23a), [OpenAI crawlers](https://developers.openai.com/api/docs/bots).
