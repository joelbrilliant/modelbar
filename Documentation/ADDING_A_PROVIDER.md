# Adding a provider

ModelBar deliberately uses a compile-time adapter registry. It does not download or execute provider plug-ins at runtime.

## Provider contract

An adapter supplies:

- a stable, unique `id` used by settings and cached snapshots
- a user-facing `displayName`
- optional light and dark brand colours
- an async `fetch` method that returns one `ProviderReading`

The reading may contain any number of quota windows, optional token totals, optional service status and one typed issue. The registry adds the provider ID, display name, branding and fetch time when it creates the cached snapshot. Missing data should stay missing. Do not render a zero quota or operational status unless the provider actually returned that information.

Adapters may use:

- `CommandRunning` for a bounded, short-lived CLI call
- `URLSession` for an HTTPS API
- bounded local file reads for provider-owned usage data

Keep credentials in the provider's existing auth store, the macOS Keychain or an environment variable. Never commit credentials, put them in `ProviderReading`, or write them to ModelBar preferences.

## Implementation

1. Copy [ProviderAdapterTemplate.swift](ProviderAdapterTemplate.swift) into `Sources/ModelBarCore` and rename the provider.
2. Parse production-shaped output into `QuotaWindow`, `TokenUsage` and `ServiceStatus` values.
3. Convert authentication, timeout, network, provider and invalid-data failures into the matching `SourceIssueKind`.
4. Register the adapter in `ProviderRegistry.standard` in `Sources/ModelBarCore/RefreshService.swift`.

For example:

```swift
let example = ExampleProviderAdapter(
    executable: URL(fileURLWithPath: "/usr/local/bin/example-model")
)
return ProviderRegistry(providers: [codex, claude, grok, example])
```

No menu, settings, cache or preference code should change. The provider appears automatically, defaults to enabled and receives a neutral accent if it does not supply a brand.

## Required tests

Add tests that prove:

- a production-shaped fixture maps every real quota window
- used percentages clamp to the zero-to-100 range
- token totals and their time label are accurate
- missing data stays unavailable rather than becoming a false zero
- authentication, timeout, network and invalid-data failures stay distinct
- service status is not inferred from a successful quota fetch
- the adapter's ID, display name and brand flow through `ProviderRegistry`
- disabling the provider prevents its fetch

Run:

```sh
swift test
./Scripts/build-app.sh release
```

Then launch the app and verify the new provider in Settings and in the open menu. Confirm the process returns to zero idle CPU and has no persistent child processes after refresh.

## Compatibility rules

- Provider IDs are persistent data. Do not rename one after release without a migration.
- Keep adapter-specific parsing outside the menu and snapshot cache.
- Do not expose account email, credentials, raw payloads or provider-owned file paths in snapshots.
- Do not add polling inside an adapter. ModelBar owns refresh scheduling and coalescing.
- A fork can register any number of providers. Registry order is display order.
