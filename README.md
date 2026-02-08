# HetznerMount

A native macOS menu bar app that mounts [Hetzner Storage Boxes](https://www.hetzner.com/storage/storage-box/) as Finder volumes via SFTP, using Apple's FileProvider framework.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
[![Build](https://github.com/danielgtmn/hetzner-storage-box-mounter/actions/workflows/build.yml/badge.svg)](https://github.com/danielgtmn/hetzner-storage-box-mounter/actions/workflows/build.yml)

> **Disclaimer:** This project is not affiliated with, endorsed by, or connected to Hetzner Online GmbH. HetznerMount is an independent, third-party tool created by the community. Hetzner and Storage Box are trademarks of Hetzner Online GmbH.

## Installation

Download the latest release from the [Releases page](https://github.com/danielgtmn/hetzner-storage-box-mounter/releases/latest).

1. Unzip `HetznerMount.app.zip`
2. Move `HetznerMount.app` to `/Applications`
3. On first launch: Right-click → **Open** (required for unsigned apps)

> **Note:** The app is currently unsigned. macOS Gatekeeper will block it on double-click. Use Right-click → Open to bypass this once.

## Features

- **Native Finder integration** - Storage Boxes appear in Finder's sidebar under Locations, just like iCloud or Dropbox
- **Multiple Storage Boxes** - Connect and mount several boxes simultaneously, each with its own Finder volume
- **Menu bar app** - Lightweight, runs in the background with a menu bar icon showing mount status
- **Per-box controls** - Mount/unmount, open in Finder, and refresh individually from the menu bar
- **Connection testing** - Verify credentials before saving
- **Launch at Login** - Optional auto-start via macOS native service management
- **User-friendly errors** - SSH/SFTP errors are translated into clear messages

## Screenshots

The app lives in the menu bar and shows all configured Storage Boxes with their mount status:

```
 [icon] HetznerMount
 ──────────────────────
 ● Backup Server       [ON]
   Open in Finder  Refresh
 ○ Media Storage       [OFF]
 ──────────────────────
 Add Storage Box...
 Settings...
 ──────────────────────
 Quit
```

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16+ (for building)
- A Hetzner Storage Box with SSH/SFTP access enabled

## Building from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/danielgtmn/hetzner-storage-box-mounter.git
   cd hetzner-storage-box-mounter
   ```

2. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen) and generate the Xcode project:
   ```bash
   brew install xcodegen
   xcodegen generate
   ```

3. Open in Xcode:
   ```bash
   open HetznerMount.xcodeproj
   ```

4. In **Signing & Capabilities**, select your development team for both targets:
   - `HetznerMount`
   - `FileProviderExtension`

5. Ensure the App Group `group.com.danielgtmn.hetznermount` is registered in your Apple Developer account.

6. Build and run (Cmd+R).

## Architecture

```
HetznerMount.app                    # Main menu bar app (LSUIElement)
├── HetznerMountApp.swift           # App entry point, AppDelegate
├── Services/
│   └── DomainManager.swift         # FileProvider domain management
└── Views/
    ├── MenuBarView.swift           # Menu bar dropdown UI
    ├── StorageBoxListView.swift    # Settings: list + detail editor
    └── SettingsView.swift          # Settings window wrapper

FileProviderExtension.appex         # FileProvider extension (sandboxed)
├── FileProviderExtension.swift     # SFTP ↔ FileProvider bridge
├── FileProviderEnumerator.swift    # Directory listing
└── FileProviderItem.swift          # File/folder metadata

Packages/HetznerMountKit/           # Shared Swift package
├── Models/
│   └── StorageBoxConfig.swift      # Configuration model
├── Storage/
│   └── StorageBoxConfigStore.swift # JSON persistence (UserDefaults)
├── Keychain/
│   └── KeychainManager.swift       # Secure password storage
├── SFTP/
│   ├── SFTPConnectionManager.swift # SSH/SFTP connection lifecycle
│   └── SFTPOperations.swift        # File operations (list, upload, download, delete)
└── Shared/
    ├── AppGroupConstants.swift     # Shared identifiers
    └── UserFacingError.swift       # Error message mapping
```

### Key Design Decisions

- **FileProvider (Replicated)** - Uses `NSFileProviderReplicatedExtension` for native Finder integration instead of FUSE or network mounts
- **Per-box domains** - Each Storage Box is a separate `NSFileProviderDomain` with ID format `com.danielgtmn.hetznermount.storagebox.<UUID>`
- **Shared data via App Groups** - Configurations stored in shared `UserDefaults`, passwords in shared Keychain
- **Citadel** - Pure Swift SSH/SFTP library (no libssh2 dependency) built on SwiftNIO

## Configuration

Each Storage Box needs:

| Field | Description | Example |
|-------|-------------|---------|
| Name | Display name in Finder & menu bar | `Backup Server` |
| Username | Storage Box username | `u453068` |
| Host | Auto-filled from username | `u453068.your-storagebox.de` |
| Port | SSH port (default: 23) | `23` |
| Base Path | Root directory to mount | `/` |
| Password | Stored securely in Keychain | |

## Dependencies

- [Citadel](https://github.com/orlandos-nl/Citadel) (>= 0.12.0) - SSH/SFTP client library

## License

MIT
