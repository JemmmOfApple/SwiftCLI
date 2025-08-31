import ArgumentParser
import Foundation

// MARK: - Command

struct GitActivity: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "gitlog",
        abstract: "Commits in the CURRENT git repo for a period, grouped by branch or date (adaptive widths).",
        aliases: ["ga"]
    )

    @Option(name: .long, help: "Author (email or name). Defaults to git config user.email|user.name.")
    var author: String?

    @Option(name: .long, help: "Start: 30d, 2w, 6m, 1y or date 2025-07-01.")
    var since: String = "30d"

    @Option(name: .long, help: "End date (YYYY-MM-DD). Defaults to now.")
    var until: String?

    @Option(name: .long, help: "Per-branch commit limit (0 = unlimited).")
    var limit: Int = 0

    @Option(name: .long, help: "Grouping: branch or date.")
    var group: String = "branch"

    @Flag(name: .long, help: "Verbose logs to stderr.")
    var verbose: Bool = false

    func run() throws {
        guard let repoRoot = detectRepoRoot() else {
            throw ValidationError("Not inside a git repo (rev-parse --is-inside-work-tree != true).")
        }
        if verbose { fputs("[git-activity] repoRoot=\(repoRoot.path)\n", stderr) }

        let authorFilter = try resolveAuthor(explicit: author, repoRoot: repoRoot, verbose: verbose)
        let sinceDate = try parseSince(since)
        let untilDate = parseUntil(until)

        if verbose {
            fputs("[git-activity] author=\(authorFilter ?? "<any>") since=\(iso8601(sinceDate)) until=\(iso8601(untilDate))\n", stderr)
        }

        let branches = listLocalBranches(repoRoot: repoRoot)
        if branches.isEmpty {
            print("No local branches.")
            return
        }
        if verbose { fputs("[git-activity] branches=\(branches)\n", stderr) }

        var perBranch: [BranchCommits] = []
        for br in branches {
            let commits = gitLog(repoRoot: repoRoot,
                                 branch: br,
                                 author: authorFilter,
                                 since: sinceDate,
                                 until: untilDate,
                                 limit: limit,
                                 verbose: verbose)
            perBranch.append(.init(branch: br, commits: commits))
        }

        // Output
        switch group.lowercased() {
        case "branch": printByBranch(perBranch, since: sinceDate, until: untilDate, author: authorFilter)
        case "date":   printByDate(perBranch, since: sinceDate, until: untilDate, author: authorFilter)
        default:
            print("❌ Unknown --group \(group). Use 'branch' or 'date'.")
        }
    }
}

// MARK: - Models

struct BranchCommits: Codable {
    struct Item: Codable {
        let hash: String
        let date: String  // ISO
        let subject: String
        let authorName: String
        let authorEmail: String
    }
    let branch: String
    let commits: [Item]
}

// MARK: - Printing (adaptive widths)

private func printByBranch(_ data: [BranchCommits], since: Date, until: Date, author: String?) {
    print("🗂  Commits \(author ?? "(any)")  \(iso8601(since)) → \(iso8601(until))")
    print(String(repeating: "—", count: 100))

    // Columns: Hash(7) | Date(10) | Subject(adaptive with cap)
    let hashW = 10  // show 7 chars + padding
    let dateW = 10  // YYYY-MM-DD
    let capSubject = 80

    // Compute the longest subject seen (bounded by cap)
    let maxSubj = data.flatMap { $0.commits }.map { $0.subject.count }.max() ?? 20
    let subjW = min(max(20, maxSubj), capSubject)

    for br in data {
        print("🌿 \(br.branch)  (\(br.commits.count))")
        if br.commits.isEmpty { print(""); continue }
        // Header per branch (optional; comment out if you don't want it)
        // print("  \(pad("Hash", hashW))  \(pad("Date", dateW))  \(pad("Subject", subjW))")
        // print("  \(String(repeating: "─", count: hashW))  \(String(repeating: "─", count: dateW))  \(String(repeating: "─", count: subjW))")
        for c in br.commits {
            let hash = String(c.hash.prefix(7)).padRight(hashW)
            let day  = String(c.date.prefix(10)).padRight(dateW)
            let subj = c.subject.truncateMiddle(to: subjW)
            print("  \(hash)  \(day)  \(subj)")
        }
        print("")
    }

    let total = data.reduce(0) { $0 + $1.commits.count }
    print("Total: \(total)")
}

private func printByDate(_ data: [BranchCommits], since: Date, until: Date, author: String?) {
    print("🗂  Commits \(author ?? "(any)")  \(iso8601(since)) → \(iso8601(until))")
    print(String(repeating: "—", count: 100))

    // Flatten: (branch, item)
    let flat: [(String, BranchCommits.Item)] = data.flatMap { br in
        br.commits.map { (br.branch, $0) }
    }
    // Group by yyyy-mm-dd and sort descending (new → old)
    let grouped = Dictionary(grouping: flat, by: { String($0.1.date.prefix(10)) })
        .sorted { $0.key > $1.key }

    // Adaptive widths with caps
    // Columns per row: Branch(adaptive) | Hash(7 padded to 10) | Subject(adaptive)
    let capBranch = 30
    let capSubject = 80
    let hashW = 10

    // compute branch width by data
    let maxBranch = flat.map { $0.0.count }.max() ?? 10
    let branchW = min(max(10, maxBranch), capBranch)

    // compute subject width by data
    let maxSubj = flat.map { $0.1.subject.count }.max() ?? 20
    let subjW = min(max(20, maxSubj), capSubject)

    for (day, items) in grouped {
        print("📅 \(day)")
        // Header per day (optional)
        // print("  \(pad("Branch", branchW))  \(pad("Hash", hashW))  \(pad("Subject", subjW))")
        // print("  \(String(repeating: "─", count: branchW))  \(String(repeating: "─", count: hashW))  \(String(repeating: "─", count: subjW))")
        for (branch, c) in items {
            let b = branch.truncateMiddle(to: branchW).padRight(branchW)
            let h = String(c.hash.prefix(7)).padRight(hashW)
            let s = c.subject.truncateMiddle(to: subjW)
            print("  \(b)  \(h)  \(s)")
        }
        print("")
    }

    let total = data.reduce(0) { $0 + $1.commits.count }
    print("Total: \(total)")
}

// MARK: - Git helpers

private func detectRepoRoot() -> URL? {
    guard let inside = shell("/usr/bin/env", "git", ["rev-parse", "--is-inside-work-tree"])?.trimmed,
          inside == "true" else { return nil }
    guard let root = shell("/usr/bin/env", "git", ["rev-parse", "--show-toplevel"])?.trimmed,
          !root.isEmpty else { return nil }
    return URL(fileURLWithPath: root)
}

private func listLocalBranches(repoRoot: URL) -> [String] {
    guard let out = shell("/usr/bin/env", "git",
                          ["-C", repoRoot.path, "for-each-ref", "--sort=-committerdate",
                           "--format=%(refname:short)", "refs/heads/"])
    else { return [] }
    return out
        .split(separator: "\n")
        .map { String($0).trimmed }
        .filter { !$0.isEmpty }
}

private func gitLog(repoRoot: URL, branch: String, author: String?, since: Date, until: Date, limit: Int, verbose: Bool) -> [BranchCommits.Item] {
    let sepField = "\u{001F}" // unit separator
    let sepRec = "\u{001E}"   // record separator

    var args = ["-C", repoRoot.path,
                "log", branch,
                "--no-merges",
                "--date=iso-strict",
                "--pretty=format:%H\(sepField)%cd\(sepField)%s\(sepField)%an\(sepField)%ae\(sepRec)",
                "--since", iso8601(since),
                "--until", iso8601(until)]
    if let author, !author.isEmpty { args += ["--author", author] }
    if limit > 0 { args += ["-n", "\(limit)"] }

    guard let out = shell("/usr/bin/env", "git", args), !out.isEmpty else { return [] }
    if verbose { fputs("[git] \(branch): \(out.count) bytes\n", stderr) }

    var items: [BranchCommits.Item] = []
    for raw in out.split(separator: Character(sepRec), omittingEmptySubsequences: true) {
        let fields = raw.split(separator: Character(sepField), omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 5 else { continue }
        items.append(.init(hash: fields[0],
                           date: fields[1],
                           subject: fields[2].trimmed,
                           authorName: fields[3],
                           authorEmail: fields[4].trimmed))
    }
    return items
}

// MARK: - Author & time parsing

private func resolveAuthor(explicit: String?, repoRoot: URL, verbose: Bool) throws -> String? {
    if let a = explicit, !a.isEmpty { return a }
    if let email = shell("/usr/bin/env", "git", ["-C", repoRoot.path, "config", "user.email"])?.trimmed, !email.isEmpty {
        return email
    }
    if let name = shell("/usr/bin/env", "git", ["-C", repoRoot.path, "config", "user.name"])?.trimmed, !name.isEmpty {
        return name
    }
    if let email = shell("/usr/bin/env", "git", ["config", "--global", "user.email"])?.trimmed, !email.isEmpty {
        return email
    }
    if let name = shell("/usr/bin/env", "git", ["config", "--global", "user.name"])?.trimmed, !name.isEmpty {
        return name
    }
    if verbose { fputs("[git-activity] author not resolved; showing all authors\n", stderr) }
    return nil
}

private func parseSince(_ s: String) throws -> Date {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let rel = parseRelative(t) { return rel }
    let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
    if let d = f.date(from: t) { return d }
    throw ValidationError("Bad --since: \(s). Examples: 30d, 2w, 6m, 1y, 2025-07-01")
}

private func parseUntil(_ s: String?) -> Date {
    guard let s = s, !s.isEmpty else { return Date() }
    let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
    return f.date(from: s) ?? Date()
}

private func parseRelative(_ s: String) -> Date? {
    guard s.count >= 2, let num = Int(s.dropLast()) else { return nil }
    let unit = s.last!
    var comp = DateComponents()
    switch unit {
    case "d": comp.day = -num
    case "w": comp.day = -(num * 7)
    case "m": comp.month = -num
    case "y": comp.year = -num
    default: return nil
    }
    return Calendar.current.date(byAdding: comp, to: Date())
}

private func iso8601(_ d: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
    return f.string(from: d)
}

// MARK: - String utils

private func pad(_ s: String, _ w: Int) -> String { s.count >= w ? s : s + String(repeating: " ", count: w - s.count) }

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

// MARK: - Shell

@discardableResult
private func shell(_ launchPath: String, _ tool: String, _ args: [String]) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = [tool] + args
    let out = Pipe(); let err = Pipe()
    p.standardOutput = out; p.standardError = err
    do { try p.run() } catch { return nil }
    p.waitUntilExit()
    return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
}
