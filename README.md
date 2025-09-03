## 🚀 SwiftCLI

✨ Your personal CLI assistant for iOS/macOS development.
Clean Xcode caches, analyze CocoaPods updates, explore git activity, track tasks, and more — all from the terminal.

## 🔧 Features
- 🧹 clean          → Clear Xcode DerivedData, caches, simulators.
- 📦 pod-analyze    → Scan Podfile + Podfile.lock, fetch latest pod versions (trunk/git), and show what would update.
- 🌿 gitlog         → Pretty commit history grouped by date or branch.
- ⏱ task-session    → Start, pause, resume, stop tasks; generate time reports.
- 🧩 extract        → Analyze Swift files, extract class names, and replace common prefixes to prepare reusable templates.

💡 Built with swift-argument-parser

## 📥 Installation
- git clone https://github.com/freemacson/SwiftCLI
- cd swiftcli
- make install


This will build swiftcli in release mode and install it into /usr/local/bin/swiftcli.

## ⚡️ Usage

List all available commands:

swiftcli --help

Examples:

- swiftcli clean
- swiftcli pod-analyze --only-outdated
- swiftcli gitlog --group date
- swiftcli task-session start "OBBA-5123 Fix login bug"
- swiftcli extract ./Sources/FeatureModule

## 🙌 Acknowledgements
- [swift-argument-parser](https://github.com/apple/swift-argument-parser)
- [swift-syntax](https://github.com/apple/swift-syntax)
