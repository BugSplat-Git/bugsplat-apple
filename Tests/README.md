# Tests

```sh
scripts/build-native.sh          # once: builds Frameworks/BugSplatNative.xcframework (Crashpad + bugsplat-native)
swift test                       # unit tests: options, errors, Info.plist resolution, pending-report parsing, call stacks
BUGSPLAT_RUNTIME_TESTS=1 swift test --filter RuntimeTests   # end to end against the real monitor and fred
```

The runtime test starts the SDK in the test process, captures a report of the live process,
waits for `BugSplatMonitor` to import it, uploads it (plus a feedback and a structured report)
to the `fred` database and prints the crash ids. It needs network access and a few seconds, so
it only runs when asked. `BUGSPLAT_DATABASE` overrides the database.

CI (`.github/workflows/ci.yml`) runs both on a macOS runner.
