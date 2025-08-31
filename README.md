## 🚀 SwiftCLI

✨ Your personal CLI assistant for iOS/macOS development.
Clean Xcode caches, analyze CocoaPods updates, explore git activity, track tasks, and more — all from the terminal.

🔧 Features
🧹 clean          → Clear Xcode DerivedData, caches, simulators.
📦 pod-analyze    → Scan Podfile + Podfile.lock, fetch latest pod versions (trunk/git), and show what would update.
🌿 gitlog         → Pretty commit history grouped by date or branch.
⏱ task-session    → Start, pause, resume, stop tasks; generate time reports.
🧩 extract        → Analyze Swift files, extract class names, and replace common prefixes to prepare reusable templates.

💡 Built with swift-argument-parser

───────────────────────────────────────────────────────────────────────────────────────────────────────────────
📥 Installation
git clone https://github.com/freemacson/SwiftCLI
cd swiftcli
make install


This will build swiftcli in release mode and install it into /usr/local/bin/swiftcli.

───────────────────────────────────────────────────────────────────────────────────────────────────────────────

⚡️ Usage

List all available commands:

swiftcli --help

Examples:

swiftcli clean
swiftcli pod-analyze --only-outdated
swiftcli gitlog --group date
swiftcli task-session start "OBBA-5123 Fix login bug"
swiftcli extract ./Sources/FeatureModule

📊 Example Outputs:

Pod Analyzer:
Pod                            Locked     Constraint   Source       Latest Sat.   Latest   Update   Status   Note
───────────────────────────────────────────────────────────────────────────────────────────────────────────────
Alamofire                      5.4.0      ~> 5.4.0     trunk        5.10.2        5.10.2   ✅       🟡
RxSwift                        6.9.0      —            trunk        6.9.0         6.9.0    —        🟢

...

Git Log:
🌿 develop
──────────────────────────────
ce8bfe     2025-08-15  Flow improves on main screen
9a8a5b     2025-08-06  Fixed bugs on Profile page

...

⏱ Task Session:
Started task: OBBA-5123 Fix login bug
⏱ Active for: 42m

Report (last 7 days):
────────────────────────────────────────────
Task                               Duration
DEV-1234 Fix login bug            1h 25m
DEV-1235 Improve scanner flow     2h 10m
────────────────────────────────────────────
Total                              3h 35m

...

Extract (classes & prefix templating):
$ swiftcli extract ./TemplateSource
Classes Found:
- MyFeatureViewController
- MyFeatureViewModel
- MyFeatureService
Most common prefix: MyFeature
Updated files with ___VARIABLE_moduleName___
Renamed files accordingly
Created TemplateInfo.plist

───────────────────────────────────────────────────────────────────────────────────────────────────────────────

## 🙌 Acknowledgements
- [swift-argument-parser](https://github.com/apple/swift-argument-parser)
- [swift-syntax](https://github.com/apple/swift-syntax)
