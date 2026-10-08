# Public repository

This repository is open source. Never commit or push sensitive information, including secrets, private personal data, internal legal or release audits, and confidential security findings. Keep private notes and evidence in ignored local files. Before publishing, inspect staged changes, commit history, PR descriptions, comments, attachments and logs for sensitive content. Public policy contact details must be explicitly approved for publication; that approval does not extend to other private information.

# Functional verification

Maintain the real-app journeys in `Apps/Currency/Tests/E2E` instead of repeating manual screen tours for covered behavior. Use `Documentation/FeatureMap.md` for the app-wide capabilities and expected outcomes, including features without E2E coverage. Follow the E2E README for setup, test mapping and limitations.

When a change adds, removes or changes app functionality, update `Documentation/FeatureMap.md` with the current entry points and expected outcomes, preserving existing feature IDs. Update the E2E README mapping when coverage changes.

For functional changes, extend or add a user-visible outcome check and build the current worktree when app code/resources change. Select and run only the journeys affected by the change, using the feature map and E2E coverage mapping; include dependent shared-data flows where relevant. Use the same selection during iteration and before handoff. Do not run the full core or widget suite by default; broaden the selection only when the change affects those flows or the user explicitly requests it. Manual exploration is useful for diagnosis or new coverage; turn the discovered regression into a maintained journey. Do not accept a replacement cache recording until the expected outcome is proven. Report the selected coverage, failures/skips and separate warm test duration from build/cold preparation.

Choose verification targets from the changed behavior. Use one owned iPhone by default; add iPad checks for layout, sizing or tablet-specific behavior, and widget journeys for widget or shared-data changes. Run additional profiles when relevant or explicitly requested. Keep journeys shared across devices unless the user flow differs. Consult the E2E README for current driver limitations and report blocked checks. Duo verification is deferred.
