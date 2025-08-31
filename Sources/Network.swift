import Foundation
import ArgumentParser

let configFilePath = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".network_aliases.json").path

struct Network: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A CLI tool to add network aliases and switch between them.",
        subcommands: [Add.self, Switch.self, List.self],
        defaultSubcommand: Switch.self
    )
    
    struct NetworkAlias: Codable {
        let key: String
        let name: String
    }
    
    /// Load saved network aliases from JSON file
    static func loadAliases() -> [NetworkAlias] {
        guard FileManager.default.fileExists(atPath: configFilePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: configFilePath)),
              let aliases = try? JSONDecoder().decode([NetworkAlias].self, from: data) else {
            return []
        }
        return aliases
    }
    
    /// Save network aliases to JSON file
    static func saveAliases(_ aliases: [NetworkAlias]) {
        if let data = try? JSONEncoder().encode(aliases) {
            FileManager.default.createFile(atPath: configFilePath, contents: data)
        }
    }
    
    /// Execute shell command
    static func runCommand(_ command: String) {
        let process = Process()
        process.launchPath = "/bin/zsh"
        process.arguments = ["-c", command]
        process.launch()
        process.waitUntilExit()
    }
}

// MARK: - Add a New Network Alias
struct Add: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Add a new network alias.")
    
    @Option(name: .shortAndLong, help: "Network service name as seen in System Preferences")
    var name: String
    
    @Option(name: .shortAndLong, help: "Shortcut key for switching")
    var key: String
    
    func run() {
        var aliases = Network.loadAliases()
        
        if aliases.contains(where: { $0.key == key }) {
            print("❌ Alias key '\(key)' already exists. Choose a different key.")
            return
        }
        
        let alias = Network.NetworkAlias(key: key, name: name)
        aliases.append(alias)
        Network.saveAliases(aliases)
        
        print("✅ Added network alias: \(key) → \(name)")
    }
}

// MARK: - Switch Between Network Aliases
struct Switch: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Switch between saved network aliases.")
    
    @Argument(help: "The alias key to activate")
    var key: String
    
    func run() {
        let aliases = Network.loadAliases()
        
        guard let selectedAlias = aliases.first(where: { $0.key == key }) else {
            print("❌  No network alias found for key '\(key)'. Use 'network' to check available aliases.")
            return
        }
        
        // Disable all networks first
        for alias in aliases {
            let disableCommand = "networksetup -setnetworkserviceenabled \"\(alias.name)\" off"
            Network.runCommand(disableCommand)
        }
        
        // Enable the selected network
        let enableCommand = "networksetup -setnetworkserviceenabled \"\(selectedAlias.name)\" on"
        Network.runCommand(enableCommand)
        
        print("🔄 Switched to: \(selectedAlias.name) ✅")
    }
}

// MARK: - List All Saved Network Aliases
struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List all saved network aliases.")
    
    func run() {
        let aliases = Network.loadAliases()
        
        if aliases.isEmpty {
            print("⚠️  No network aliases found. Use 'network add' to add one.")
        } else {
            print("📋 Saved Network Aliases:")
            for alias in aliases {
                print("🔹 \(alias.key) → \(alias.name)")
            }
        }
    }
}

// MARK: - Activate All Saved Networks
struct Reset: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Enable all saved network aliases.")
    
    func run() {
        let aliases = Network.loadAliases()
        
        if aliases.isEmpty {
            print("⚠️ No saved networks found. Use 'my-cli network add' to add aliases.")
            return
        }
        
        for alias in aliases {
            let enableCommand = "networksetup -setnetworkserviceenabled \"\(alias.name)\" on"
            Network.runCommand(enableCommand)
            print("✅ Activated: \(alias.name)")
        }
        
        print("🌍 All saved networks are now enabled! ✅")
    }
}
