# Crick

Crick is an experimental, human-scale creek-tending game. Read [VISION.md](VISION.md) for the product direction.

The repository currently contains the bootstrap for Scope 1 from the development handoff: a platform-independent Swift core, a small command-line executable, and tests. It does not yet contain a creek simulation or an iOS client.

## Requirements

- Swift 6.3 or later
- macOS or Linux

The initial environment was validated with:

- macOS 26.5.2 (arm64)
- Xcode 26.6 (build 17F113)
- Apple Swift 6.3.3
- Swift Package Manager 6.3.3

The package uses Swift tools version 6.3 and Swift 6 language mode. The core intentionally has no Apple-framework, wall-clock, file-I/O, or global-random-state dependency.

## Build and test

```sh
swift build
swift run crick
swift test
```

Expected CLI output:

```text
Crick scenario seed: 42
```

GitHub Actions independently runs the build, executable, and tests with Swift 6.3.3 on Linux. Local commands are the development feedback loop; CI is a verification gate.

## Current scope

Implemented:

- `CreekCore` library boundary
- `crick` headless executable boundary
- Minimal seeded scenario value and deterministic smoke test

Not yet implemented:

- Authoritative world state and tick semantics
- Water flow, terrain, rocks, or sediment
- Commands, snapshots, replay, or diagnostic exports
- Feature evaluation
- Native iOS client
