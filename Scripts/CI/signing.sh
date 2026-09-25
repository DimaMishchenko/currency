#!/bin/bash
set -euo pipefail
umask 077

# asc performs all Apple API operations. This script only decides whether the
# distribution certificate and each App Store profile are still usable.
app_bundle=com.dimasike.currency
widget_bundle=com.dimasike.currency.widgets
app_group=group.com.dimasike.currency.shared
signing_dir=$(mktemp -d "$RUNNER_TEMP/currency-signing.XXXXXX")
echo "CURRENCY_SIGNING_DIR=$signing_dir" >> "$GITHUB_ENV"
key_file=$signing_dir/distribution.key
printf '%s' "$APPLE_DISTRIBUTION_PRIVATE_KEY_B64" | base64 --decode > "$key_file"

fail() { echo "::error::$*" >&2; exit 1; }
fresh() {
  jq -en --arg date "$1" --argjson days "${2:-30}" \
    '($date | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) > (now + $days * 86400)' >/dev/null
}
public_hash() {
  openssl pkey -pubin -outform DER | shasum -a 256 | cut -d ' ' -f 1
}
key_hash=$(openssl pkey -in "$key_file" -pubout | public_hash)

find_certificate() {
  asc certificates list --certificate-type DISTRIBUTION --paginate --output json > "$signing_dir/certificates.json"
  cert_id=
  fallback_cert_id=
  while IFS= read -r id; do
    cert_file="$signing_dir/$id.cer"
    jq -er --arg id "$id" '.data[] | select(.id == $id) | .attributes.certificateContent' \
      "$signing_dir/certificates.json" | base64 --decode > "$cert_file"
    cert_hash=$(openssl x509 -inform DER -in "$cert_file" -pubkey -noout | public_hash)
    expiration=$(jq -er --arg id "$id" '.data[] | select(.id == $id) | .attributes.expirationDate' \
      "$signing_dir/certificates.json")
    if [[ "$cert_hash" == "$key_hash" ]] && fresh "$expiration"; then
      cert_id=$id
      break
    elif [[ "$cert_hash" == "$key_hash" ]] && fresh "$expiration" 0; then
      fallback_cert_id=$id
    fi
  done < <(jq -r '.data[] | select(.attributes.certificateType == "DISTRIBUTION") | .id' \
    "$signing_dir/certificates.json")
}

find_certificate
profile_fresh_days=30
if [[ -z "$cert_id" ]]; then
  openssl req -new -key "$key_file" -out "$signing_dir/distribution.csr" \
    -subj '/CN=Currency CI Distribution'
  if ! asc certificates create --certificate-type DISTRIBUTION \
      --csr "$signing_dir/distribution.csr" --output json > "$signing_dir/created-cert.json"; then
    # A network failure after creation is ambiguous. Search once before failing.
    find_certificate
    if [[ -z "$cert_id" && -n "$fallback_cert_id" ]]; then
      cert_id=$fallback_cert_id
      profile_fresh_days=0
      echo '::warning::Certificate renewal failed; using the still-valid certificate. Check the Apple Distribution certificate quota.'
    fi
    [[ -n "$cert_id" ]] || fail 'Certificate renewal failed. Check the Apple Distribution certificate quota; CI will not revoke team certificates.'
  else
    cert_id=$(jq -er '.data.id' "$signing_dir/created-cert.json")
    jq -er '.data.attributes.certificateContent' "$signing_dir/created-cert.json" \
      | base64 --decode > "$signing_dir/$cert_id.cer"
    cert_hash=$(openssl x509 -inform DER -in "$signing_dir/$cert_id.cer" -pubkey -noout | public_hash)
    [[ "$cert_hash" == "$key_hash" ]] || fail 'New certificate does not match the persistent private key.'
  fi
fi

asc bundle-ids list --paginate --output json > "$signing_dir/bundles.json"
asc profiles list --profile-type IOS_APP_STORE --paginate --output json > "$signing_dir/profiles.json"

profile_uuid() {
  local bundle=$1 profile_id=$2 profile_file=$3
  asc profiles download --id "$profile_id" --output "$profile_file" >/dev/null
  security cms -D -i "$profile_file" > "$signing_dir/profile.plist"
  [[ $(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$signing_dir/profile.plist") == "$APPLE_TEAM_ID" ]] || return 1
  [[ $(/usr/libexec/PlistBuddy -c 'Print :Entitlements:application-identifier' "$signing_dir/profile.plist") == "$APPLE_TEAM_ID.$bundle" ]] || return 1
  /usr/libexec/PlistBuddy -c 'Print :Entitlements:com.apple.security.application-groups' \
    "$signing_dir/profile.plist" | grep -Fqx "    $app_group" || return 1
  asc profiles local install --path "$profile_file" --output json >/dev/null
  plutil -extract UUID raw -o - "$signing_dir/profile.plist"
}

reconcile_profile() {
  local bundle=$1 resource_id id detail name selected= file
  resource_id=$(jq -er --arg bundle "$bundle" \
    '.data[] | select(.attributes.identifier == $bundle) | .id' "$signing_dir/bundles.json") \
    || fail "Create explicit Bundle ID $bundle with the $app_group capability in Apple Developer."
  while IFS= read -r id; do
    detail=$(asc profiles view --id "$id" --include bundleId,certificates --output json)
    if jq -e --arg bundle "$resource_id" --arg cert "$cert_id" '
      .data.relationships.bundleId.data.id == $bundle and
      ([.data.relationships.certificates.data[].id] | index($cert) != null)
    ' <<< "$detail" >/dev/null; then
      file="$signing_dir/$id.mobileprovision"
      if selected=$(profile_uuid "$bundle" "$id" "$file"); then
        printf '%s' "$selected"
        return
      fi
    fi
  done < <(jq -r --argjson days "$profile_fresh_days" '.data[] | select(.attributes.profileType == "IOS_APP_STORE" and
    .attributes.profileState == "ACTIVE") |
    select((.attributes.expirationDate | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | fromdateiso8601) > (now + $days * 86400)) |
    .id' "$signing_dir/profiles.json")

  name="Currency CI $bundle $(date -u +%Y%m%d) $(openssl rand -hex 4)"
  if ! asc profiles create --name "$name" --profile-type IOS_APP_STORE \
      --bundle "$resource_id" --certificate "$cert_id" --output json > "$signing_dir/created-profile.json"; then
    asc profiles list --profile-type IOS_APP_STORE --paginate --output json > "$signing_dir/retry-profiles.json"
    id=$(jq -er --arg name "$name" '.data[] | select(.attributes.name == $name) | .id' \
      "$signing_dir/retry-profiles.json") || fail "Profile creation for $bundle failed; inspect Apple Developer."
  else
    id=$(jq -er '.data.id' "$signing_dir/created-profile.json")
  fi
  file="$signing_dir/$id.mobileprovision"
  profile_uuid "$bundle" "$id" "$file" \
    || fail "Profile for $bundle lacks $app_group or has the wrong team. Enable the App Group for this Bundle ID."
}

app_uuid=$(reconcile_profile "$app_bundle")
widget_uuid=$(reconcile_profile "$widget_bundle")

openssl x509 -inform DER -in "$signing_dir/$cert_id.cer" -out "$signing_dir/distribution.pem"
openssl rand -hex 32 | tr -d '\n' > "$signing_dir/identity-password"
openssl rand -hex 32 | tr -d '\n' > "$signing_dir/keychain-password"
# macOS Security.framework rejects OpenSSL 3's default PKCS#12 encryption.
openssl pkcs12 -export -legacy -inkey "$key_file" -in "$signing_dir/distribution.pem" \
  -out "$signing_dir/distribution.p12" -passout "file:$signing_dir/identity-password"
asc signing keychain install \
  --identity "$signing_dir/distribution.p12" \
  --identity-password-file "$signing_dir/identity-password" \
  --keychain "$signing_dir/currency-ci.keychain-db" \
  --keychain-password-file "$signing_dir/keychain-password" \
  --add-to-search-list --confirm --output json >/dev/null

{
  echo "CURRENCY_APP_PROFILE_UUID=$app_uuid"
  echo "CURRENCY_WIDGET_PROFILE_UUID=$widget_uuid"
} >> "$GITHUB_ENV"
echo "Signing ready: certificate $cert_id; app profile $app_uuid; widget profile $widget_uuid"
