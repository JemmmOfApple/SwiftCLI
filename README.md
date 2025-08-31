swiftcli

✨ A developer’s Swiss Army knife for iOS/macOS projects.
A CLI helper written in Swift: clean Xcode caches, analyze CocoaPods updates, track your coding activity, manage task timers, and more.

Features

🧹 clean – Remove Xcode’s DerivedData, caches, simulators.

📦 pod-analyze – Parse Podfile + Podfile.lock, check latest versions from trunk/git, and report what would update if you remove the lock.

🌿 gitlog – Generate commit history grouped by date or branch, formatted for humans.

⏱ task-session – Start, pause, and stop task timers; generate reports by time spent.

🔧 Extensible – Built with swift-argument-parser
.

Install
git clone https://github.com/JemmmOfApple/SwiftCLI
cd swiftcli
make install


This will build the tool in release mode and copy the binary to /usr/local/bin/swiftcli.

Usage

List all commands:

swiftcli --help


Example commands:

swiftcli clean
swiftcli pod-analyze --only-outdated
swiftcli gitlog --group date
swiftcli task-session start "OBBA-5123 Fix login bug"
