#!/bin/bash
set -euo pipefail
umask 077

workdir=$(mktemp -d "$RUNNER_TEMP/currency-public-beta.XXXXXX")
trap 'status=$?; rm -rf "$workdir"; exit "$status"' EXIT
fail() { echo "::error::$*" >&2; exit 1; }
report() { printf '%s\n' "$*"; printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"; }
defer() { report "Public beta deferred: $*. The hourly retry will check again."; exit 0; }
# jq's fromdateiso8601 accepts UTC only. Retain fractions and subtract the offset.
date_filter='def apple_epoch:
  (capture("^(?<date>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(?<fraction>\\.[0-9]+)?(?<zone>Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])$")
    // error("Invalid Apple timestamp")) as $d |
  ($d.date + "Z" | fromdateiso8601) as $seconds |
  (if ($seconds | todateiso8601) == ($d.date + "Z") then $seconds
    else error("Invalid Apple timestamp") end) + ("0" + ($d.fraction // "") | tonumber) -
  (if $d.zone == "Z" then 0 else
    (($d.zone[1:3] | tonumber) * 3600 + ($d.zone[4:6] | tonumber) * 60) *
    (if $d.zone[0:1] == "+" then 1 else -1 end) end);'
enable_public_link() {
  local link
  if [[ $(jq -r '.data.attributes.publicLinkEnabled // false' "$workdir/group.json") != true ]]; then
    asc testflight groups edit --id "$group_id" --public-link-enabled --output json > "$workdir/group.json" || return 1
  fi
  link=$(jq -er '.data.attributes.publicLink | select(length > 0)' "$workdir/group.json") || return 1
  report "Public beta invitation: $link"
}

for name in ASC_KEY_ID ASC_ISSUER_ID ASC_PRIVATE_KEY_B64 ASC_APP_ID; do
  [[ -n "${!name:-}" ]] || fail "Missing testflight environment value: $name"
done

# The ID comes exclusively from the successful, tested main publication artifact.
[[ -f "${1:-}" ]] || fail 'Pass CurrencyBuildId.txt from a successful main TestFlight Publish run.'
build_id=$(cat "$1")
[[ "$build_id" =~ ^[A-Za-z0-9-]+$ ]] || fail 'The trusted release artifact contains an invalid build ID.'

# An older approved group build can become available while the latest upload waits.
asc testflight groups list --app "$ASC_APP_ID" --paginate --output json > "$workdir/groups.json"
group_count=$(jq -er '[.data[] | select(.attributes.name == "Public Beta" and
  .attributes.isInternalGroup != true)] | length' "$workdir/groups.json")
(( group_count <= 1 )) || fail 'Multiple external groups named Public Beta exist. Keep one group with that name.'
if [[ "$group_count" == 1 ]]; then
  jq '{data: (.data[] | select(.attributes.name == "Public Beta" and
    .attributes.isInternalGroup != true))}' "$workdir/groups.json" > "$workdir/group.json"
  group_id=$(jq -er '.data.id' "$workdir/group.json")
  if [[ $(jq -r '.data.attributes.publicLinkEnabled // false' "$workdir/group.json") == true ]]; then
    enable_public_link
  else
    asc testflight groups links view --group-id "$group_id" --type builds --paginate \
      --output json > "$workdir/group-builds.json"
    asc builds list --app "$ASC_APP_ID" --platform IOS --processing-state VALID --exclude-expired \
      --include buildBetaDetail --paginate --output json > "$workdir/available-builds.json"
    approved=$(jq -r --slurpfile members "$workdir/group-builds.json" "$date_filter"'
      (.included // []) as $details | [.data[] |
      select(.attributes.processingState == "VALID" and .attributes.expired != true) |
      select((.attributes.expirationDate | apple_epoch) > now) |
      select(.id as $id | any($members[0].data[]; .id == $id)) |
      select(.relationships.buildBetaDetail.data.id as $id | any($details[];
        .type == "buildBetaDetails" and .id == $id and (.attributes.externalBuildState as $state |
          ["READY_FOR_BETA_TESTING", "READY_FOR_TESTING", "IN_BETA_TESTING", "BETA_APPROVED"] | index($state) != null))) |
      .id][0] // empty' "$workdir/available-builds.json")
    if [[ -n "$approved" ]]; then enable_public_link; fi
  fi
fi

asc builds info --build-id "$build_id" --output json > "$workdir/build.json"
valid=$(jq -r "$date_filter"'.data.attributes | (.expirationDate | apple_epoch) as $expiry |
  .processingState == "VALID" and .expired != true and $expiry > now' "$workdir/build.json")
[[ "$valid" == true ]] || defer "build $build_id is not valid and unexpired"
version=$(jq -er '. as $r | .data.relationships.preReleaseVersion.data.id as $id |
  $r.included[] | select(.type == "preReleaseVersions" and .id == $id) |
  .attributes.version | select(length > 0)' "$workdir/build.json")
asc builds build-beta-detail view --build-id "$build_id" --output json > "$workdir/detail.json"
detail_id=$(jq -er '.data.id | select(length > 0)' "$workdir/detail.json")
state=$(jq -er '.data.attributes.externalBuildState | select(length > 0)' "$workdir/detail.json")
case "$state" in
  WAITING_FOR_BETA_REVIEW|IN_BETA_REVIEW|PROCESSING|IN_EXPORT_COMPLIANCE_REVIEW)
    defer "build $build_id is $state" ;;
  READY_FOR_BETA_SUBMISSION|READY_FOR_BETA_TESTING|READY_FOR_TESTING|IN_BETA_TESTING|BETA_APPROVED) ;;
  *) fail "Build $build_id cannot be promoted ($state). Check its TestFlight details in App Store Connect." ;;
esac

# Apple allows one build per version in review and six submissions per 24 hours.
review_blocker() {
  local pending count
  asc builds list --app "$ASC_APP_ID" --platform IOS --version "$version" \
    --beta-review-state WAITING_FOR_REVIEW,IN_REVIEW --processing-state all \
    --paginate --output json > "$workdir/pending.json" || return 1
  pending=$(jq -er '.data | length' "$workdir/pending.json") || return 1
  if [[ "$pending" != 0 ]]; then
    printf 'another build of version %s is in review' "$version"
    return
  fi
  asc builds list --app "$ASC_APP_ID" --processing-state all \
    --include betaAppReviewSubmission --paginate --output json > "$workdir/reviews.json" || return 1
  count=$(jq -er "$date_filter"'[.included[]? | select(.type == "betaAppReviewSubmissions")] |
    unique_by(.id) | [.[] | select(.attributes.submittedDate | type == "string" and length > 0) |
      select((.attributes.submittedDate | apple_epoch) > now - 86400)] | length' \
    "$workdir/reviews.json") || return 1
  if (( count >= 6 )); then printf 'six builds have been submitted within the last 24 hours'; fi
  return 0
}
if [[ "$state" == READY_FOR_BETA_SUBMISSION ]]; then
  blocker=$(review_blocker)
  [[ -z "$blocker" ]] || defer "$blocker"
fi

if [[ $(jq -er '[.data[] | select(.attributes.isInternalGroup == true)] | length' "$workdir/groups.json") == 0 ]]; then
  asc testflight groups create --app "$ASC_APP_ID" --name Internal --internal \
    --access-all-builds --output json > /dev/null
fi
if [[ "$group_count" == 0 ]]; then
  asc testflight groups create --app "$ASC_APP_ID" --name 'Public Beta' \
    --feedback-enabled --output json > "$workdir/group.json"
fi
group_id=$(jq -er '.data.id' "$workdir/group.json")
asc testflight groups list --build-id "$build_id" --output json > "$workdir/membership.json"
jq -e '.complete == true' "$workdir/membership.json" > /dev/null
if [[ "$state" != READY_FOR_BETA_SUBMISSION ]] && jq -e --arg id "$group_id" 'any(.groups[]; .id == $id)' "$workdir/membership.json" > /dev/null; then
  enable_public_link
  report "Build $build_id is already available to Public Beta."
  exit 0
fi

# One-time app/reviewer metadata remains in App Store Connect, outside this public repo.
asc testflight app-localizations list --app "$ASC_APP_ID" --paginate --output json > "$workdir/localizations.json"
jq -e 'any(.data[]; ([.attributes.description, .attributes.feedbackEmail] |
  all(.[]; type == "string" and length > 0)))' "$workdir/localizations.json" > /dev/null \
  || fail 'Enter Beta App Description and Feedback Email in App Store Connect → TestFlight → Test Information.'
asc testflight review view --app "$ASC_APP_ID" --output json > "$workdir/review-details.json"
jq -e '.data[0].attributes | [.contactFirstName, .contactLastName, .contactEmail, .contactPhone] |
  all(.[]; type == "string" and length > 0)' "$workdir/review-details.json" > /dev/null \
  || fail 'Complete the beta review contact name, email, and phone in App Store Connect → TestFlight → Test Information.'

flags=(--notify)
if [[ "$state" == READY_FOR_BETA_SUBMISSION ]]; then
  # This schedules notification after approval; it does not notify unapproved builds.
  asc testflight distribution edit --id "$detail_id" --auto-notify --output json > /dev/null
  flags=(--submit --confirm)
fi
publish=(asc publish testflight --app "$ASC_APP_ID" --build-id "$build_id" --group "$group_id"
  --test-notes 'Please test currency conversion, currency selection, rate refresh, and Home Screen widgets. Report unexpected results or layout issues through TestFlight.'
  --locale en-US "${flags[@]}" --output json)
if [[ "$state" == READY_FOR_BETA_SUBMISSION ]] && jq -e --arg id "$group_id" 'any(.groups[]; .id == $id)' "$workdir/membership.json" > /dev/null; then
  # The previous attempt may have assigned the group before submission failed.
  publish=(asc testflight review submit --build-id "$build_id" --confirm --output json)
fi
if "${publish[@]}" > "$workdir/publish.json" 2> "$workdir/publish-error.txt"; then
  if [[ "$state" != READY_FOR_BETA_SUBMISSION ]]; then enable_public_link; fi
  report "Build $build_id promoted to Public Beta ($state). Apple approval controls availability."
else
  # A concurrent submission or an ambiguous response may have filled Apple's queue.
  blocker=$(review_blocker)
  [[ -z "$blocker" ]] || defer "$blocker"
  cat "$workdir/publish-error.txt" >&2
  fail "Public beta promotion failed for build $build_id. The signed upload remains successful."
fi
