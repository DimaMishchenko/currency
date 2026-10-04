# Simulator Home Screen widgets

A standalone Python standard-library CLI plus a small Objective-C worker. Copy this directory into another repository and call it from an E2E runner, Playwright setup, or a shell. No app identifiers, Python packages, or JavaScript dependencies are built in.

Requires macOS, Python 3.9+, selected Xcode with an iOS Simulator SDK, and an **already booted, explicitly named iOS simulator**. Install the app and register its widget extension first. The requested kind must support the requested family. Prefer a disposable simulator owned by the caller.

```sh
python3 Tools/SimulatorWidgets/widget-place.py "$SIMULATOR_UDID" \
  org.example.app.widgets ExampleWidget small \
  --state-dir "$HOME/Library/Caches/example-widget-tests"

python3 Tools/SimulatorWidgets/widget-place.py "$SIMULATOR_UDID" \
  --unload --state-dir "$HOME/Library/Caches/example-widget-tests"
```

Positional arguments are `UDID EXTENSION_BUNDLE_IDENTIFIER KIND FAMILY`. Families are `small`, `medium`, and `large`. `--inspect` accepts only UDID and lifecycle options and returns method metadata instead of placing a widget:

```sh
python3 Tools/SimulatorWidgets/widget-place.py "$SIMULATOR_UDID" \
  --inspect --state-dir "$HOME/Library/Caches/example-widget-tests"
```

Inspection uses the same injection/restart lifecycle as placement. The worker only reads its established manager/model getters and Objective-C runtime method metadata; it does not invoke discovered removal, placement, or reveal selectors. The result is `status: "inspected"` with `response.inspection`, including selectors, defining classes, and Objective-C ABI type encodings. Unload the worker afterward.

Optional `--container BUNDLE_IDENTIFIER` enables the private provider's container lookup when its descriptor collection has no matching kind. The extension argument still participates in final persisted-state verification.

`--state-dir` defaults to `~/Library/Caches/SimulatorWidgets`. Reuse the same directory for placement and unload. Paths with spaces are supported. Each user-owned state directory must be unwritable by other users. It contains generated worker caches and per-device sessions; no generated files belong in this source directory. Compilation uses the selected Xcode SDK/compiler, the requested device's runtime version, and the native host architecture (`arm64` or `x86_64`), checked against runtime `supportedArchitectures` when available. For a simulator running with a different architecture, pass `--architecture arm64` or `--architecture x86_64` explicitly. Cache identity includes source contents, protocol, compiler, SDK, stable runtime identifier/version/build, and target triple. Volatile runtime metadata does not invalidate the worker.

The CLI writes one JSON result to stdout. Exit code 0 means `status: "verified"` for placement, `status: "inspected"` for inspection, `status: "ready"` for preparation, or `status: "unloaded"` for unload. Exit code 0 also covers verified scoped removal as described below. Exit code 2 means duplicate preflight or an unverified persisted result. Exit code 1 means a tool, lifecycle, or worker failure. Invalid CLI arguments use argparse's stderr diagnostics and exit code 2. Results include the requested UDID, worker response, exact persisted matches, and separate injection/restart, command, and verification timings. Those timings exclude boot, app installation, app data preparation, and visual rendering.

Placement rejects multiple existing Home entries matching extension + kind + family before compiling or injecting. Missing/unreadable Home IconState fails closed. A successful private call alone does not count as success: the CLI must observe exactly one matching entry beneath Home `iconLists`. Today-only entries do not count. When an individual matching widget already exists, ensure resolves its persisted leaf icon UUID and asks the manager to reveal it with animation. Missing widgets use the system's ensure operation, then receive a second nonce command to reveal the newly verified leaf UUID through the same worker. The CLI rechecks persisted identity after reveal. Repeated calls reuse the live worker; they preserve other kinds and families. Existing widgets can be on another Home page. This utility does not arrange pages or prove rendered content; optional configuration operations are described below. Tests must separately inspect the intended widget and its user-visible outcome.

Commands are serialized with a per-device filesystem lock within the chosen state directory. Do not use different state directories concurrently for the same device. Each request has a fresh nonce and must receive a response from the same SpringBoard PID. Heartbeats must match UDID, source identity, protocol, live PID, and freshness. Commands are cleared before initialization and after response waiting, including failure. A failed initialization can leave a pending one-launch injection; `--unload` tracks that state and overrides its environment before restarting the target job. Unload checks that the PID changed and observes no live worker for three seconds. With no owned live worker or pending injection, unload succeeds without restarting. Unload leaves placed widgets in Home IconState. Keep this directory and state available until unload completes.

## Preparation and exclusive ensure

```sh
python3 Tools/SimulatorWidgets/widget-place.py "$SIMULATOR_UDID" \
  --prepare --state-dir "$HOME/Library/Caches/example-widget-tests"

python3 Tools/SimulatorWidgets/widget-place.py "$SIMULATOR_UDID" \
  org.example.app.widgets ExampleWidget small --exclusive \
  --state-dir "$HOME/Library/Caches/example-widget-tests"
```

`--prepare` initializes or reuses the worker and returns `status: "ready"` without sending a runtime inspection or widget command. Run it before opening the app or establishing UI automation handles: cold preparation can restart the explicit simulator's SpringBoard. Preparation still requires an available booted UUID, selected SDK/compiler, and the same lifecycle ownership checks. Use the same state directory for subsequent calls and unload.

`--exclusive` applies only to ensure. It selects other persisted Home widgets from the same extension and preserves the requested kind/family tuple, widgets from other extensions, and app icons. The worker validates the requested installed descriptor, kind, and family support, then every existing target, including a preserved desired widget, before any deletion. Missing desired descriptors and unsupported families reject the operation without removing current widgets. Duplicate Home identifiers, ambiguous tuples, and stacks reject preflight. Scoped removals use separate nonces with an exact persisted verification after each UUID. The desired widget is then ensured and revealed through the same worker session. No bulk-removal selector is used. A later failure can leave earlier scoped removals completed; the JSON result records those operations. Final persisted verification checks that no other widget from the requested extension remains and that preserved Home identity counts remain intact.

For new placement, `timings.reveal_seconds` reports the second command and `post_reveal_verification_seconds` reports its final persisted check. Existing-widget reveal is the initial command and uses `command_seconds`. Exclusive results also contain batch preflight timing and per-removal command/verification timings. A reveal response and persisted entry do not prove visible rendering or accessibility; the E2E runner must check those outcomes.

## Read-only configuration export

```sh
python3 Tools/SimulatorWidgets/widget-place.py "$SIMULATOR_UDID" \
  org.example.app.widgets ExampleWidget small \
  --export-config ./widget-configuration.json \
  --state-dir "$HOME/Library/Caches/example-widget-tests"
```

Export requires one existing individual Home widget with exact persisted leaf/widget UUIDs and an app container identifier. It reads the ABI-guarded current `INAppIntent` identifiers and full JSON-valid `serializedParameters`, then reconstructs a detached intent from a deep JSON snapshot. The full canonical class/app/extension/type identifiers and parameters must roundtrip unchanged, including entity titles, images, remote proxy URIs, and unknown nested fields. The live intent and manager configuration are not updated.

Exit code 0 with `status: "configuration_exported"` means the exported schema-version-1 envelope was bound to the exact current UDID, extension, container, kind, family, and both widget IDs, its detached roundtrip matched, and persisted identity remained unchanged. `configuration_path` identifies the file; the worker response includes roundtrip data, observed intent identifiers, and optional alternate plist/JSON representation diagnostics. Unsupported intent classes, non-JSON parameters, ABI mismatches, or changed target identity fail closed. Export does not prove later applying or archiving a configuration, image-service lifetime, or rendering; runtime export support must be checked on the caller's device. Configuration mutation is not enabled by this command.

## Full configuration apply

```sh
python3 Tools/SimulatorWidgets/widget-place.py "$UDID" org.example.widgets ExampleKind small \
  --apply-config ./widget-configuration.json \
  --state-dir "$HOME/Library/Caches/SimulatorWidgets"
```

Apply accepts a complete exported envelope bound to the exact current widget. Change only the full `intent.parameters` dictionary; class, app, extension, intent type, UDID, kind, family, and target IDs must still match. The worker verifies detached reconstruction before invoking the ABI-guarded manager configuration callback with secure archiving enabled. Callback argument semantics were established from the iOS 27 simulator runtime implementation. On the owned arm64 iOS 27 simulator, Pocket configuration export, detached reconstruction, no-op apply, and a full canonical currency-pair swap passed exact intent readback and preservation of other Home entries. The swapped pair rendered correctly and remained visible after helper unload and a targeted SpringBoard restart. Apply took approximately 0.21 seconds plus 0.52 seconds for persisted identity verification with a warm worker. Mental Math’s reversed pair and Board’s text amount, Custom list enum and currency entity array also produced the expected rendered data. Other widget configuration types, OS versions, and device architectures remain unverified.

A successful `configuration_applied` response includes `configuration`, a fresh export envelope for restoration. The leaf icon UUID must stay fixed; the active widget UUID may rotate. The CLI verifies that new persisted tuple and all other Home identity counts, while the worker checks complete live intent readback. Save the returned envelope before the next change: restoration must use its current target IDs and the original full parameter dictionary. Input files are not overwritten. This operation does not prove persistence across restart, image-service lifetime, or visible rendering; verify those separately. A failure after the callback can leave the configuration changed, so inspect/export current state before retrying.

## Fresh widget replacement

```sh
python3 Tools/SimulatorWidgets/widget-place.py "$SIMULATOR_UDID" \
  org.example.app.widgets ExampleWidget small --replace --position top \
  --state-dir "$HOME/Library/Caches/example-widget-tests"
```

`--replace` applies only to ensure. When the desired tuple exists, its descriptor and family are validated before the concrete old widget is removed. Removal and persisted identity preservation are checked before creating the same kind/family again, revealing it, and optionally positioning it. Success requires new widget and leaf-icon UUIDs while preserving other Home identities. `--replace` leaves other widgets, including other kinds/families from the same extension, intact; combine it with `--exclusive` to remove those other same-extension widgets too. A missing desired tuple follows ordinary new placement. The default continues to reuse existing widgets.

Replacement results include `replaced_identifiers`, `replace_preflight`, and per-operation `replace_removals` timings; when combined with exclusive mode, the existing `exclusive_*` operation fields cover the scoped removals. Fresh identities support repeatable default-widget tests, but the caller must still prove the app's default configuration and visible outcome. The utility does not promise to clear every platform intent archive or application-owned setting.

## Optional same-page top position

```sh
python3 Tools/SimulatorWidgets/widget-place.py "$SIMULATOR_UDID" \
  org.example.app.widgets ExampleWidget small --position top \
  --state-dir "$HOME/Library/Caches/example-widget-tests"
```

`--position top` applies only to ensure and preserves the current Home page. The validated concrete widget resolves its root folder and containing `SBIconListModel`; the worker verifies the exact root/list/move method ABIs, moves only that icon to index 0 with options 0, then reveals it. For new placement, this happens after persisted widget UUID verification through the second command. Other Home icons may shift within the page. The CLI waits for the persisted layout, checks index 0 of the same page, and verifies other Home identity counts remain intact. `position_verification_seconds` measures that check; `position` records the zero-based page and index. The default leaves placement order unchanged.

With `--exclusive`, the read-only batch preflight also checks positioning selectors on the existing concrete targets before removing scoped widgets. A newly created desired widget cannot have its actual containing-list instance checked until it exists; a later positioning failure is reported without pretending the entire operation rolled back. This optional API is experimental until the caller proves its runtime and user-visible outcome. It is not a guarantee of accessibility-tree completeness.

## Scoped removal and targeting

```sh
python3 Tools/SimulatorWidgets/widget-place.py "$SIMULATOR_UDID" \
  org.example.app.widgets ExampleWidget small --remove \
  --state-dir "$HOME/Library/Caches/example-widget-tests"

python3 Tools/SimulatorWidgets/widget-place.py "$SIMULATOR_UDID" \
  --inspect --icon-identifier "$PERSISTED_DISPLAY_IDENTIFIER" \
  --state-dir "$HOME/Library/Caches/example-widget-tests"
```

Removal requires exactly one matching Home tuple and valid persisted `displayIdentifier` and `uniqueIdentifier` UUIDs. The worker resolves the leaf icon by `displayIdentifier`, requires an individual `SBWidgetIcon`, and rejects stacks. If the active widget exposes `uniqueIdentifier`, it must match the persisted widget UUID; the response states whether that extra check was available. The manager receives only that concrete icon with removal options 0. The worker checks exact runtime method encodings before calling the model lookup, removal, or reveal selector.

Exit code 0 with `status: "removed"` means both targeted identifiers disappeared and every other persisted Home identity remained. A missing tuple returns that status with `no_op: true` without injecting. Duplicate tuples reject the operation. Exit code 2 with `status: "removal_unverified"` means the persisted outcome was not proven. No bulk-removal selectors are called. Other Home entries may move during the manager's layout updates; their identity counts must be preserved.

Targeted inspection adds concrete icon and active-widget class/method metadata to `response.inspection`. It also reports root-folder objects from available typed object getters, an icon folder when exposed, and `SBRootFolder`/`SBFolder` method metadata for placement diagnosis. Intent/configuration/archive/update/cache/save selectors and `CHSIntentReference` metadata are included. For a concrete active widget, the ABI-checked read-only `intentForWidget:ofIcon:` getter supplies `targetIntent` class, description, and methods, or an explicit missing/unavailable flag. Discovered setters and archive/update methods are not invoked. It performs no removal or reveal. Animated reveal returns after command submission; the caller must poll for the visible/accessible outcome rather than treating the response as animation completion. Removal and existing-widget reveal are experimental selectors observed in iOS 27 runtime metadata; successful SDK compilation and host tests do not prove their runtime behavior, completion, or visible outcome. The caller must validate those operations on its owned simulator before relying on them.

## Private API and support

This deliberately loads trusted locally compiled code into **only the explicit simulator's SpringBoard** using a one-launch `launchctl debug` environment and a targeted restart. It reads `launchctl manageruid` inside the requested simulator rather than assuming the host UID. If discovery is unsupported, supply `--launch-domain user/UID` with the device's known SpringBoard domain (the proven simulator used `user/501`). Use the same override for unload. It does not modify global simulator services or inject into physical devices. Treat the source and state directory as trusted code: anyone able to change the worker or its commands can run code inside that simulator process.

Placement depends on private SpringBoard selectors, descriptor family masks, launchd behavior, and IconState format. It is development tooling coupled to the OS and Xcode; it is unsuitable for shipping in an app. On 2026-10-04, application-specific validation checked ten Home kind/family combinations across an 11-case native/rendered suite and a focused Board check on an owned arm64 iOS 27.0 simulator with Xcode 27.0 build 27A266a. Small, medium, and large placement, exact scoped removal, fresh replacement, reveal, and same-page top positioning were verified there. The worker compiles against that SDK with strict warnings. Observed warm placement took about 1–2 seconds and cold helper preparation usually about 12–20 seconds, reaching 47 seconds under contention; these are samples, not a benchmark, and exclude app/driver preparation and rendering checks. Other runtimes, Intel simulators, iPad behavior, and Lock Screen placement remain unverified. There is no automatic fallback that touches other devices.

## Host-only checks

```sh
python3 -m unittest discover -s Tools/SimulatorWidgets -p 'test_*.py' -v
```

These tests use temporary files and mocked device calls. They do not boot, restart, install, or modify a simulator. The native worker can be compiled separately for a static SDK check; real placement and rendering remain the caller's device-owned integration checks.
