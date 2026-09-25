# GitHub Actions → TestFlight

Every pull request runs `CurrencyTests` on an iOS simulator without Apple credentials. A new commit to the same pull request cancels its older test job. Every push to `main` runs the same tests, then queues a signed archive and TestFlight upload. The release job is serialized with `queue: max`, so normal back-to-back merges do not replace an earlier pending release. GitHub currently caps this queue at 100 pending jobs.

The workflow uses Xcode 27, Tuist, and [`asc`](https://github.com/rorkai/App-Store-Connect-CLI). It creates or renews one Apple Distribution certificate from a persistent RSA private key and separate App Store profiles for the app and widget. It never revokes a team certificate or deletes an Apple profile. Local Tuist generation uses automatic signing with team `77X75EH6F4`; only the release job supplies the two profile UUIDs to Tuist.

## One-time Apple setup

1. In Apple Developer, accept any pending agreements and confirm the membership is active.
2. Create explicit iOS Bundle IDs `com.dimasike.currency` and `com.dimasike.currency.widgets`. Register App Group `group.com.dimasike.currency.shared` and enable it on **both** Bundle IDs. CI creates the App Store profiles after this is done.
3. In App Store Connect, create the Currency app record using `com.dimasike.currency`. Create an internal TestFlight group and enable automatic distribution for new builds if desired.
4. In App Store Connect → Users and Access → Integrations → App Store Connect API → **Team Keys**, create an Admin key and download its `.p8` file once. An individual API key cannot access the provisioning endpoints used by this workflow. Record its Key ID and Issuer ID.

The first upload can require Apple account questions such as export compliance, app privacy, or beta information. Resolve any such prompts in App Store Connect. The repository includes the app's required-reason privacy manifest for its app-local `UserDefaults` use; review the separate App Privacy questionnaire against actual data flows before answering it.

## One-time GitHub setup

Create a `testflight` environment in repository Settings → Environments and restrict deployments to `main`. Do not require a reviewer if the intent is automatic upload on each merge. Put these values **in that environment**:

| Name | Type | Value |
| --- | --- | --- |
| `ASC_API_KEY_ID` | Secret | Team API Key ID |
| `ASC_API_ISSUER_ID` | Secret | Team API Issuer ID |
| `ASC_API_CERT` | Secret | Base64 of the downloaded `.p8` file |
| `APPLE_DISTRIBUTION_PRIVATE_KEY_B64` | Secret | Base64 of one persistent RSA private key |

CI resolves the numeric App Store Connect app ID from `com.dimasike.currency` on each release.

The initial distribution key for this repository is backed up at `~/.config/currency/signing/distribution.key` with owner-only permissions and is already stored in the GitHub environment secret. Keep that file outside the public repository; CI reuses the same key when Apple's public certificate expires. Do not post the key or its base64 form in an issue or chat. If the key is intentionally rotated, generate a replacement and update the GitHub secret together.

For deliberate key rotation, generate a new backup outside the repository and put its base64 content in `APPLE_DISTRIBUTION_PRIVATE_KEY_B64`:

```sh
umask 077
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$HOME/.config/currency/signing/distribution-next.key"
base64 -i "$HOME/.config/currency/signing/distribution-next.key" | pbcopy
```

Separately, run `base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy` and paste that into `ASC_API_CERT`. Keep the two keys distinct. The GitHub release runner creates a disposable `.p12` and keychain from the distribution key, then removes them after the job.

Protect `main` with the `test` job as a required status check before merging. Keep the `testflight` environment limited to `main`; pull request jobs do not receive release secrets.

## Renewal and failures

On each release, CI lists all distribution certificates and matches their public key to the persistent private key. If no matching certificate has more than 30 days left, it requests a new Apple Distribution certificate from the **same** key. It independently checks each bundle's App Store profile for state, expiry, team, certificate, and App Group, and creates a successor as needed. Old Apple assets remain in the account; there is no automatic revocation. If Apple's distribution certificate quota prevents renewal, the job warns and uses the still-valid certificate until it expires, then stops with an account action rather than revoking another team's certificate.

CI uses `asc builds next-build-number` after it enters the serialized release job, accounting for uploaded and in-flight builds. The same number is used for the app and widget. After export, it verifies the IPA's bundle IDs, build numbers, profile UUIDs, and signed App Group before upload. `asc` waits for TestFlight processing and resumes a known build ID after a wait failure.

The first live run is the final integration check for Apple's API permissions, profile format, Xcode export, and TestFlight processing. After a successful upload, install the beta on a real device and check that the widget reads the shared App Group data.
