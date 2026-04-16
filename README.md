# AppleUITesting

A Swift package providing UI testing utilities for iOS and macOS apps.

## Libraries

| Target | Purpose |
|--------|---------|
| `AccessibilityKit` | Accessibility identifiers and query helpers |
| `VisionEvalKit` | Claude Vision-powered screenshot evaluation |
| `UITestingBridge` | Lightweight HTTP server exposing the AX tree on port 7979 |
| `SnapshotKit` | Snapshot testing via swift-snapshot-testing |
| `PerformanceKit` | Performance measurement helpers |

## `apple-ui-tester` CLI

A command-line tool that connects to a running `UITestingBridge` inside a simulator, fetches the accessibility tree, optionally captures a screenshot, and runs Vision-based expectation checks.

### Build

```bash
# Debug build
swift build --target AppleUITester

# Release build (recommended for CI)
swift build -c release --target AppleUITester

# Install to ~/.local/bin
mkdir -p ~/.local/bin
cp .build/release/apple-ui-tester ~/.local/bin/apple-ui-tester
```

### Usage

```
apple-ui-tester --bundle-id <id> [options]
```

#### Required

| Flag | Description |
|------|-------------|
| `--bundle-id <id>` | The app's bundle identifier, e.g. `com.example.MyApp` |

#### Optional

| Flag | Default | Description |
|------|---------|-------------|
| `--host <host>` | `localhost` | Host where UITestingBridge is listening |
| `--port <port>` | `7979` | Port where UITestingBridge is listening |
| `--expectations <json>` | — | JSON array of expectation strings for Vision eval |
| `--screenshot` | off | Capture a screenshot before running Vision eval |
| `--output <path>` | stdout | Write the JSON report to a file instead of stdout |

#### Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Bridge unreachable |
| `2` | One or more Vision eval expectations failed |

### Example

```bash
# Boot simulator and launch app
xcrun simctl boot "iPhone 16"
xcrun simctl launch booted com.example.MyApp

# Wait a moment for UITestingBridge to start, then run
apple-ui-tester \
  --bundle-id com.example.MyApp \
  --screenshot \
  --expectations '["Main screen is visible","Navigation is accessible","No error messages shown"]' \
  --output /tmp/ux-report.json

cat /tmp/ux-report.json
```

### JSON Report Schema

```json
{
  "bundleId": "com.example.MyApp",
  "bridgeReachable": true,
  "axTree": { "role": "application", "children": [...] },
  "screenshot": { "captured": true, "path": "/tmp/ux-screenshot-1234567890.png" },
  "evalReport": {
    "sceneName": "com.example.MyApp",
    "results": [
      { "expectation": "Main screen is visible", "passed": true, "reasoning": "..." },
      { "expectation": "No error messages shown", "passed": false, "reasoning": "..." }
    ]
  },
  "errors": []
}
```

### Prerequisites

- Xcode 15+ with command-line tools
- `ANTHROPIC_API_KEY` environment variable set (required for `--screenshot` + `--expectations`)
- App under test must embed `UITestingBridge` and call `UITestingBridge.start()` in its debug entry point:

```swift
#if DEBUG
UITestingBridge.start()
#endif
```

## Integrating UITestingBridge

Add the package to your app target:

```swift
// Package.swift
.package(url: "https://github.com/your-org/AppleUITesting", from: "1.0.0")

// In your target dependencies
.product(name: "UITestingBridge", package: "AppleUITesting")
```

Then start the bridge on app launch (debug only):

```swift
import UITestingBridge

@main
struct MyApp: App {
    init() {
        #if DEBUG
        UITestingBridge.start()
        #endif
    }
    var body: some Scene { ... }
}
```
