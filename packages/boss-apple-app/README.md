# boss-apple-app

Shared Apple app-core logic for Boss frontends.

This package sits above `libboss-apple` and below the platform apps:

- `boss-macos`
- `boss-ios`

It owns shared app-facing orchestration such as:

- discovery and connect/reconnect flow
- workspace loading and periodic refresh
- shared audio mode, settings, and EQ mutation flows
- UI-facing status/error state and derived control availability

Run tests from this package directory:

```sh
swift test --disable-sandbox
```
