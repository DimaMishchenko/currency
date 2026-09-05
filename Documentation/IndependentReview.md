# Independent architecture review

A subagent reviewed the working tree without conversation context. No P1 findings were reported. Both P2 findings are addressed.

## Shared input transactions

The app previously saved its in-memory state, which could overwrite widget edits. Both hosts now mutate freshly loaded state through `CurrencyStore.updateInput`. Currency reordering uses currency identities and an insertion anchor so concurrent additions survive.

Regression coverage interleaves widget amount entry with app list changes and reordering, then verifies both hosts see the combined result.

## Shared rate refresh and commit

The app previously refreshed stale in-memory rates and could overwrite a newer widget result. `CurrencyStore.refreshRates` now reads before requesting data and coordinates the final commit. Network requests run outside file coordination.

`RateSnapshot.merging` preserves newer publication dates and observation times, keeps daily fallbacks separate, and prevents an older result from resurrecting an overlay removed by a later failed refresh. Regression coverage suspends an older refresh until after a newer host commit, and verifies that the newer cache survives.
