# Contributing

Contributions are welcome, especially new provider adapters and production-shaped fixtures.

## Before opening a pull request

1. Keep provider parsing inside its adapter.
2. Do not add credentials, personal paths or real account payloads to fixtures.
3. Preserve explicit unavailable, stale and error states.
4. Add tests for new behaviour.
5. Run the full verification commands.

```sh
swift test
./Scripts/build-app.sh release
```

Provider contributions should also follow [Documentation/ADDING_A_PROVIDER.md](Documentation/ADDING_A_PROVIDER.md).

## Pull requests

Describe what changed, why it changed, the user impact and the exact checks run. Keep unrelated cleanup out of the same pull request.
