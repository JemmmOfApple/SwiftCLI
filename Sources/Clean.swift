import Foundation
import ArgumentParser

// MARK: - Common Cleanup Command

struct CleanAll: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clean",
        abstract: "Perform a full cleanup of all Xcode cache files."
    )

    func run() {
        print("🚀 Performing full Xcode cleanup...")

        DerivedData().run()
        Cache().run()
        Logs().run()
        Modules().run()
        SwiftPackageCache().run()

        print("🎉 Xcode cleanup complete!")
    }
}

struct DerivedData: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Clean Xcode Derived Data.")
    
    func run() {
        print("🧹 Cleaning Derived Data...")
        runCommand("rm -rf ~/Library/Developer/Xcode/DerivedData/*")
        print("✅ Derived Data cleaned!")
    }
}

struct Cache: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Clean Xcode Cache Files.")
    
    func run() {
        print("🧹 Cleaning Xcode Cache Files...")
        runCommand("rm -rf ~/Library/Caches/com.apple.dt.Xcode/*")
        print("✅ Xcode Cache Files cleaned!")
    }
}

//struct DeviceSupport: ParsableCommand {
//    static let configuration = CommandConfiguration(abstract: "Clean iOS Device Support (Unused iOS Versions).")
//    
//    func run() {
//        print("🧹 Cleaning iOS Device Support files...")
//        runCommand("rm -rf ~/Library/Developer/Xcode/iOS\\ DeviceSupport/*")
//        print("✅ iOS Device Support cleaned!")
//    }
//}

struct Logs: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Clean Xcode Logs & User Data.")
    
    func run() {
        print("🧹 Cleaning Xcode Logs & User Data...")
        runCommand("rm -rf ~/Library/Logs/Xcode/*")
        print("✅ Xcode Logs cleaned!")
    }
}

struct Modules: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Clean Xcode Module & Indexing Cache.")
    
    func run() {
        print("🧹 Cleaning Module & Indexing Cache...")
        runCommand("rm -rf ~/Library/Developer/Xcode/ModuleCache.noindex/*")
        print("✅ Module & Indexing Cache cleaned!")
    }
}

struct SwiftPackageCache: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Delete Old Swift Package Manager Cache.")
    
    func run() {
        print("🧹 Cleaning Swift Package Manager Cache...")
        runCommand("rm -rf ~/Library/Caches/org.swift.swiftpm && rm -rf ~/.swiftpm")
        print("✅ Swift Package Manager Cache cleaned!")
    }
}

extension ParsableCommand {
    /// Executes a shell command
    func runCommand(_ command: String) {
        let process = Process()
        process.launchPath = "/bin/zsh"
        process.arguments = ["-c", command]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.launch()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
            print(output)
        }
    }
}
