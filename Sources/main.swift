import Foundation
import ArgumentParser

struct SwiftCLIApp: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftcli",
        abstract: "A Swift CLI tool with useful commands.",
        subcommands: [
            CleanAll.self,
            Extract.self,
            Network.self,
            UpdateAnalyzer.self,
            GitActivity.self
        ]
    )
}

SwiftCLIApp.main()
