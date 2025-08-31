import ArgumentParser
import SwiftParser
import SwiftSyntax
import Foundation

extension String {
    var propertyName: String {
        return self.prefix(1).lowercased() + self.dropFirst()
    }
}

struct Extract: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Analyze Swift files, extract class names, and replace common prefixes to prepare reusable templates."
    )
    
    @Argument(help: "The path to the directory or Swift file to analyze.")
    var path: String
    
    func run() throws {
        let fileManager = FileManager.default
        var swiftFiles: [String] = []
        
        if fileManager.fileExists(atPath: path) {
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            
            if isDirectory.boolValue {
                // Get all Swift files in the directory
                swiftFiles = try findSwiftFiles(in: path)
            } else if path.hasSuffix(".swift") {
                swiftFiles = [path]
            } else {
                throw ValidationError("The provided path is not a Swift file or directory.")
            }
        } else {
            throw ValidationError("The path '\(path)' does not exist.")
        }
        
        var allClassNames: [String] = []
        
        for file in swiftFiles {
            let sourceCode = try String(contentsOfFile: file, encoding: .utf8)
            let classNames = try extractClassNames(from: sourceCode)
            allClassNames.append(contentsOf: classNames)
        }
        
        if allClassNames.isEmpty {
            print("No class declarations found in the files.")
        } else {
            print("Classes Found:")
            allClassNames.forEach { print("- \($0)") }
            let mostCommonPrefix = findMostCommonPrefixes(strings: allClassNames).keys.first ?? ""
            
            for file in swiftFiles {
                let sourceCode = try String(contentsOfFile: file, encoding: .utf8)
                replacePrefixInFile(fileContent: sourceCode, filePath: file, prefix: mostCommonPrefix, replacement: "___VARIABLE_moduleName___")
                renameFileIfNecessary(filePath: file, prefix: mostCommonPrefix, replacement: "___VARIABLE_moduleName___")
            }
        }
        
        
    }
    
    private func findSwiftFiles(in directory: String) throws -> [String] {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(atPath: directory)
        var swiftFiles: [String] = []
        
        while let file = enumerator?.nextObject() as? String {
            if file.hasSuffix(".swift") {
                swiftFiles.append((directory as NSString).appendingPathComponent(file))
            }
        }
        return swiftFiles
    }
    
    private func extractClassNames(from sourceCode: String) throws -> [String] {
        let sourceFile = Parser.parse(source: sourceCode)
        let visitor = ClassNameVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        return visitor.classNames
    }
    
    func findMostCommonPrefixes(strings: [String]) -> [String: [String]] {
        guard !strings.isEmpty else { return [:] }
        
        let sortedStrings = strings.sorted()
        var prefixCount: [String: Int] = [:]
        var prefixToStrings: [String: [String]] = [:]
        var maxCount = 0
        
        for i in 0..<sortedStrings.count - 1 {
            let prefix = commonPrefix(between: sortedStrings[i], and: sortedStrings[i + 1])
            if !prefix.isEmpty {
                prefixCount[prefix, default: 0] += 1
                prefixToStrings[prefix, default: []].append(contentsOf: [sortedStrings[i], sortedStrings[i + 1]])
                
                if prefixCount[prefix]! > maxCount {
                    maxCount = prefixCount[prefix]!
                }
            }
        }
        
        let mostCommonPrefixes = prefixCount.filter { $0.value == maxCount }.keys
        var result: [String: [String]] = [:]
        for prefix in mostCommonPrefixes {
            result[prefix] = Array(Set(prefixToStrings[prefix]!))
        }
        
        return result
    }
    
    func commonPrefix(between str1: String, and str2: String) -> String {
        let minLength = min(str1.count, str2.count)
        for i in 0..<minLength {
            let index = str1.index(str1.startIndex, offsetBy: i)
            if str1[index] != str2[index] {
                return String(str1[str1.startIndex..<index])
            }
        }
        return String(str1.prefix(minLength))
    }
    
    func replacePrefixInFile(fileContent: String, filePath: String, prefix: String, replacement: String) {
        do {
            let lines = fileContent.split(separator: "\n", omittingEmptySubsequences: false)
            let updatedLines = lines.map { line -> String in
                if line.contains(prefix) {
                    return line.replacingOccurrences(of: prefix, with: replacement)
                } else if line.contains(prefix.propertyName) {
                    return line.replacingOccurrences(of: prefix, with: replacement.propertyName)
                } else {
                    return String(line)
                }
            }
            let updatedContent = updatedLines.joined(separator: "\n")
            
            try updatedContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        } catch {
            print("Error updating file \(filePath): \(error)")
        }
    }
    
    func renameFileIfNecessary(filePath: String, prefix: String, replacement: String) {
        let fileManager = FileManager.default
        let fileName = (filePath as NSString).lastPathComponent
        if fileName.contains(prefix) {
            let newFileName = fileName.replacingOccurrences(of: prefix, with: replacement)
            let newFilePath = (filePath as NSString).deletingLastPathComponent + "/" + newFileName
            do {
                try fileManager.moveItem(atPath: filePath, toPath: newFilePath)
            } catch {
                print("Error renaming file \(filePath): \(error)")
            }
        }
    }
    
    func createPlistConfiguration(at path: String) {
        let plistContent: [String: Any] = [
            "Identifier": "com.___VARIABLE_moduleName___",
            "Kind": "Xcode.IDEKit.TextSubstitutionTemplateKind",
            "Description": "A custom Xcode template",
            "Summary": "Generates a template based on module name",
            "Version": 1,
            "Options": [
                [
                    "Identifier": "moduleName",
                    "Default": "MyModule",
                    "Description": "The name of the module"
                ]
            ]
        ]
        
        let plistURL = URL(fileURLWithPath: path).appendingPathComponent("TemplateInfo.plist")
        do {
            let plistData = try PropertyListSerialization.data(fromPropertyList: plistContent, format: .xml, options: 0)
            try plistData.write(to: plistURL)
            print("Created TemplateInfo.plist at \(plistURL.path)")
        } catch {
            print("Error creating plist: \(error)")
        }
    }
}

final class ClassNameVisitor: SyntaxVisitor {
    var classNames: [String] = []
    
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        classNames.append(node.name.text)
        return .visitChildren
    }
}
