# LocalCurrency

Coarse location-to-currency resolution, permission state, and coordinated local-currency storage.

Automatic refresh must never prompt for permission. Preserve generation checks when accepting asynchronous results, and persist only the coarse observation needed by the app and widgets. The app supplies live instances; setup presentation belongs to LocationOnboarding.
