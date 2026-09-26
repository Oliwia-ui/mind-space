# Mind Space

Mind Space is a native, offline macOS To Do app for turning unfinished thoughts into a calm, structured plan.

This repository is being rebuilt in **Swift, SwiftUI, and SwiftData** following the clarified native Apple requirement. The previous Tauri draft PR was closed and will not be merged.

## Current foundation

- Native SwiftUI application target
- Shared `MindSpaceCore` module for future iPhone reuse
- Swift Package Manager build and XCTest suite
- Scripted `.app` bundle generation and ad-hoc code-sign verification
- GitHub Actions native build checks

## Local requirements

- macOS 14 or later
- Swift 6 toolchain
- Xcode Command Line Tools for SwiftPM builds
- Full Xcode for Xcode UI-test execution and App Store-style project workflows

## Build and test

```bash
./scripts/test.sh
./scripts/build-app.sh
open "dist/Mind Space.app"
```

The full task model, SwiftData persistence, native Obsidian integration, Mind Space canvas, and structured views are implemented incrementally on the feature branch.
