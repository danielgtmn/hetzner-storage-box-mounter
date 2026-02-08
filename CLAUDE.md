# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

This is an Xcode project (generated via XcodeGen from `project.yml`). Open `HetznerMount.xcodeproj` and build with Cmd+R. Both targets (HetznerMount app + FileProviderExtension) must build successfully.

To regenerate the Xcode project after editing `project.yml`:
```bash
xcodegen generate
```

There are no test targets currently.

## Architecture

**Two-process model**: The main app (menu bar UI) and the FileProvider extension run in separate sandboxed processes. They share data exclusively through App Groups.

```
HetznerMount (main app)          FileProviderExtension (sandboxed)
├── MenuBarView                  ├── NSFileProviderReplicatedExtension
├── StorageBoxListView           ├── FileProviderEnumerator
├── DomainManager ──────────┐    └── FileProviderItem
│   (manages NSFileProvider  │         │
│    domain lifecycle)       │         ▼
└────────────────────────────┘    SFTPOperations → SFTPConnectionManager → Citadel (SSH)
         │                              ▲
         ▼                              │
    App Group UserDefaults ◄────────────┘
    (storage_boxes_v2 JSON)
    App Group Keychain
    (passwords per config UUID)
```

### Shared Package: HetznerMountKit
Local SPM package (`Packages/HetznerMountKit/`) used by both targets. Contains models, SFTP operations, keychain access, and config persistence. The only external dependency is [Citadel](https://github.com/orlandos-nl/Citadel) (pure Swift SSH/SFTP).

### Multi-StorageBox Domain Strategy
- Each storage box config has a `UUID`
- Domain ID format: `com.danielgtmn.hetznermount.storagebox.<UUID>`
- Extension parses UUID from domain identifier to load the correct config
- Remote file paths are base64-encoded in `NSFileProviderItemIdentifier`

### Cross-Process Communication
- **Configs**: JSON array in shared `UserDefaults` (key: `storage_boxes_v2`, suite: `group.com.danielgtmn.hetznermount`)
- **Passwords**: Shared Keychain with account key `<UUID>-<username>`
- **No direct IPC** — the extension discovers its config by parsing the domain identifier

## Key Identifiers

| Identifier | Value |
|---|---|
| App bundle ID | `com.danielgtmn.hetznermount` |
| Extension bundle ID | `com.danielgtmn.hetznermount.fileprovider` |
| App group | `group.com.danielgtmn.hetznermount` |
| Keychain service | `com.danielgtmn.hetznermount.sftp` |
| Domain prefix | `com.danielgtmn.hetznermount.storagebox.` |

**Critical**: Extension bundle ID must be prefixed with the app's bundle ID. App group must match in both entitlements files and `AppGroupConstants.swift`.

## Concurrency Model

- `SFTPConnectionManager` and `SFTPOperations` are Swift `actor`s for thread safety
- All FileProvider callbacks dispatch work into async `Task {}` blocks
- Both app and extension call `signal(SIGPIPE, SIG_IGN)` at startup — Citadel/NIO sends SIGPIPE on connection drops which would otherwise silently kill the process

## Error Handling

`FileProviderExtension.wrapError(_:)` maps Citadel errors to `NSFileProviderError` via string-matching on error descriptions (fragile but necessary — Citadel lacks structured error types). Three categories: authentication → `.notAuthenticated`, file not found → `.noSuchItem`, everything else → `.serverUnreachable`.

## Known Gotchas

- **Missing CFBundleIdentifier** in Info.plist causes `libsystem_secinit` crash. Both plists must have it.
- **Xcode scheme misconfiguration**: If scheme has `wasCreatedForAppExtension="YES"` with MacroExpansion pointing to the extension, Xcode treats the app as an extension host and sends SIGTERM when the extension exits.
- **macOS auto-termination**: LSUIElement menu bar apps get killed by launchd. Prevented by `ProcessInfo.beginActivity(options: .userInitiated)` + `applicationShouldTerminateAfterLastWindowClosed → false`.
- **Xcode "Failed to initialize logging system"** is a known Xcode bug, not an app issue. Check `~/Library/Logs/DiagnosticReports/` for real crash info.
- **Host key validation** is currently `.acceptAnything()` (no verification).
