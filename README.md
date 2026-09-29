# ModelBar

ModelBar is a lightweight, provider-extensible macOS menu-bar app for AI model quotas, token usage and service status.

It ships with OpenAI, Claude and Grok adapters. Forks can add any provider that can produce ModelBar's small `ProviderReading` contract, whether the source is a CLI, HTTP API or local usage file.

## What it shows

- a menu bar gauge and percentage left for each enabled provider, based on its tightest quota window
- quota windows with percentage remaining and reset time
- local token totals for today or the last 24 hours and seven days
- provider service status when a reliable source exists
- optional, read-only Hermes token totals by agent profile
- provider controls, refresh interval and launch-at-login settings

ModelBar uses native AppKit, one status item, no WebViews and no persistent child processes.

## Requirements

- macOS 14 or newer
- Swift 6.2 or newer when building from source
- [CodexBar CLI](https://github.com/steipete/CodexBar/blob/main/docs/cli.md) for the three built-in provider adapters

The built-in adapters look for `codexbar` at `/opt/homebrew/bin/codexbar` or `/usr/local/bin/codexbar`. CodexBar's Homebrew cask and app settings can install the CLI in those locations.

Hermes is optional. If no live Hermes profile databases exist, ModelBar continues to show provider data.

## Build and install

```sh
swift test
./Scripts/build-app.sh release
ditto .build/ModelBar.app /Applications/ModelBar.app
open /Applications/ModelBar.app
```

The local build is ad-hoc signed. It is not notarised or distributed through the Mac App Store.

## Add a provider

A provider addition has three parts:

1. implement `ProviderAdapter`
2. add the adapter to `ProviderRegistry.standard`
3. add production-shaped fixtures and tests

The menu, settings, cache, refresh filtering, stale-data handling and neutral-brand fallback are provider-independent. A provider may optionally supply separate light and dark accent colours.

See [Adding a provider](Documentation/ADDING_A_PROVIDER.md) and the copy-ready [adapter template](Documentation/ProviderAdapterTemplate.swift).

## Privacy and resource use

- ModelBar stores no provider credentials or raw provider responses.
- Provider commands run only during refresh and have explicit deadlines.
- Hermes databases are opened read-only.
- The snapshot cache contains display data only and is written only when content changes.
- The current native build targets effectively zero idle CPU and a physical footprint below 40 MB.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security reports should follow [SECURITY.md](SECURITY.md).

ModelBar is available under the [MIT License](LICENSE).
