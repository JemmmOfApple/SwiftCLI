import ArgumentParser
import Foundation

// MARK: - Command

struct UpdateAnalyzer: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pod-analyze",
        abstract: "Scan Podfile and Podfile.lock, fetch latest versions (trunk/git), and show what would update if you delete Podfile.lock.",
        aliases: ["pod"]
    )

    @Option(name: [.short, .long], help: "Path to the directory with Podfile (defaults to current directory).")
    var path: String?

    @Flag(name: .long, help: "Output JSON report.")
    var json: Bool = false

    @Flag(name: .long, help: "Show only outdated / updatable entries.")
    var onlyOutdated: Bool = false

    @Flag(name: .long, help: "Include beta/RC versions when comparing.")
    var allowPrerelease: Bool = false

    @Flag(name: .long, help: "Verbose logs to stderr.")
    var verbose: Bool = false

    @Flag(name: .long, help: "Disable emojis in statuses (useful for CI).")
    var noEmoji: Bool = false

    func run() throws {
        let dir = URL(fileURLWithPath: path ?? FileManager.default.currentDirectoryPath)
        let podfileURL = dir.appendingPathComponent("Podfile")
        let lockURL = dir.appendingPathComponent("Podfile.lock")

        guard FileManager.default.fileExists(atPath: podfileURL.path) else {
            throw ValidationError("Podfile not found: \(podfileURL.path)")
        }
        guard FileManager.default.fileExists(atPath: lockURL.path) else {
            throw ValidationError("Podfile.lock not found: \(lockURL.path)")
        }

        let podfileText = try String(contentsOf: podfileURL, encoding: .utf8)
        let lockText = try String(contentsOf: lockURL, encoding: .utf8)

        let podSpecs = PodfileParser.parse(podfileText, verbose: verbose)  // constraints + source
        let locked = LockParser.parse(lockText, verbose: verbose)          // locked versions + SHAs

        let names = Set(podSpecs.keys).union(locked.lockedVersions.keys).sorted { $0.lowercased() < $1.lowercased() }

        let resolver = VersionResolver(allowPrerelease: allowPrerelease, verbose: verbose)

        var rows: [Report.Row] = []

        for name in names {
            let spec = podSpecs[name] ?? PodSpec(name: name, requirement: .any, source: .trunk)
            let lockedVer = locked.lockedVersions[name]
            let lockedSHA = locked.lockedShas[name]

            var latest: String?
            var latestSat: String?
            var status: Report.Status = .unknown
            var note: String?

            switch spec.source {
            case .trunk:
                if let versions = resolver.trunkVersions(for: name) {
                    latest = versions.max()?.description
                    if case .any = spec.requirement {
                        latestSat = latest
                    } else {
                        latestSat = versions.filter { spec.requirement.matches($0, allowPrerelease: allowPrerelease) }.max()?.description
                    }
                    if let lv = lockedVer, let lat = latest, let lvv = SemVer(lv), let lav = SemVer(lat) {
                        status = (lvv == lav) ? .upToDate : .outdated
                    } else if lockedVer != nil {
                        status = .unknown
                    } else {
                        status = .notInstalled
                    }
                } else {
                    note = "trunk info failed"
                    status = (lockedVer == nil) ? .notInstalled : .unknown
                }

            case let .git(url, constraint):
                if let head = resolver.remoteGitHead(url: url, constraint: constraint) {
                    latest = head
                    latestSat = head
                    if let lsha = lockedSHA {
                        status = (lsha == head) ? .upToDate : .outdated
                    } else {
                        status = .unknown
                    }
                } else {
                    note = "git head check failed"
                    status = (lockedSHA == nil) ? .notInstalled : .unknown
                }
            }

            let wouldUpdate: Bool = {
                switch spec.source {
                case .trunk:
                    guard let lv = lockedVer, let ls = latestSat, let lvv = SemVer(lv), let lsv = SemVer(ls) else { return false }
                    return lvv < lsv
                case .git:
                    guard let lsha = lockedSHA, let head = latestSat else { return false }
                    return lsha != head
                }
            }()

            rows.append(.init(
                name: name,
                locked: lockedVer,
                lockedSHA: lockedSHA,
                constraint: spec.requirement.raw,
                source: spec.source.description,
                latestSatisfying: latestSat,
                latest: latest,
                wouldUpdateIfDeleteLock: wouldUpdate,
                status: status,
                note: note
            ))
        }

        if onlyOutdated {
            rows = rows.filter { $0.wouldUpdateIfDeleteLock || $0.status == .outdated }
        }

        let report = Report(rows: rows, generatedAt: ISO8601DateFormatter().string(from: Date()))

        if json {
            let data = try JSONEncoder.pretty.encode(report)
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        } else {
            report.printFixedTable(noEmoji: noEmoji)
        }
    }
}

// MARK: - Report & fixed-width printing

struct Report: Codable {
    struct Row: Codable {
        let name: String
        let locked: String?
        let lockedSHA: String?
        let constraint: String?
        let source: String
        let latestSatisfying: String?
        let latest: String?
        let wouldUpdateIfDeleteLock: Bool
        let status: Status
        let note: String?
    }
    enum Status: String, Codable { case upToDate, outdated, notInstalled, unknown }

    let rows: [Row]
    let generatedAt: String

    // Fixed column widths + safe truncation
    func printFixedTable(noEmoji: Bool) {
        let cols = FixedCols() // fixed widths

        let headers = ["Pod","Locked","Constraint","Source","Latest Sat.","Latest","Update","Status"]
        print(cols.row(headers) + "  Note")
        print(String(repeating: "—", count: cols.lineWidth + 2 + 4))

        for r in rows {
            let upd = r.wouldUpdateIfDeleteLock ? (noEmoji ? "UPD" : "✅") : (noEmoji ? "—" : "—")
            let st: String = {
                switch r.status {
                case .upToDate:     return noEmoji ? "OK " : "🟢"
                case .outdated:     return noEmoji ? "OLD" : "🟡"
                case .notInstalled: return noEmoji ? "NA " : "⚪️"
                case .unknown:      return noEmoji ? "UNK" : "🔘"
                }
            }()
            let line = cols.row([
                r.name,
                r.locked ?? (r.lockedSHA.map { String($0.prefix(7)) } ?? "—"),
                r.constraint ?? "—",
                r.source,
                r.latestSatisfying ?? "—",
                r.latest ?? "—",
                upd,
                st
            ]) + "  " + (r.note ?? "")
            print(line)
        }
    }
}

// === Fixed-width printing utilities ===

extension String {
    /// middle-ellipsis: "VeryLongNameHere" -> "VeryLong…Here"
    func truncateMiddle(to width: Int) -> String {
        guard width > 0 else { return "" }
        guard count > width else { return self }
        if width == 1 { return "…" }
        let keep = width - 1
        let left = keep / 2
        let right = keep - left
        let start = index(startIndex, offsetBy: left)
        let end = index(endIndex, offsetBy: -right)
        return String(self[..<start]) + "…" + String(self[end...])
    }

    func padRight(_ width: Int) -> String {
        let len = self.count
        return len >= width ? self : self + String(repeating: " ", count: width - len)
    }
}

struct FixedCols {
    /// Tune if needed. 32 is wider for long pod names.
    let widths: [Int] = [32, 10, 16, 18, 18, 14, 8, 8] // Pod, Locked, Constraint, Source, Latest Sat., Latest, Update, Status
    var lineWidth: Int { widths.reduce(0, +) + (widths.count - 1) * 2 }

    func cell(_ s: String?, _ w: Int) -> String {
        let v = (s ?? "—").truncateMiddle(to: w).padRight(w)
        return v
    }
    func row(_ arr: [String?]) -> String {
        zip(arr, widths).map { cell($0.0, $0.1) }.joined(separator: "  ")
    }
}

// MARK: - PodSpec + requirements

struct PodSpec {
    let name: String
    let requirement: Requirement
    let source: Source

    enum Source: Equatable {
        case trunk
        case git(url: String, constraint: GitConstraint)

        var description: String {
            switch self {
            case .trunk: return "trunk"
            case let .git(_, c):
                switch c {
                case .branch(let b): return "git:branch=\(b)"
                case .tag(let t):    return "git:tag=\(t)"
                case .commit(let s): return "git:commit=\(s.prefix(7))"
                }
            }
        }
    }

    enum GitConstraint: Equatable { case branch(String), tag(String), commit(String) }
}

enum Requirement: Equatable {
    case any
    case exact(SemVer)
    case compatibleWith(SemVer)            // ~>
    case range(lower: Bound?, upper: Bound?)
    case raw(String)

    struct Bound: Equatable {
        enum Op: String { case gt = ">", gte = ">=", lt = "<", lte = "<=" }
        let op: Op
        let v: SemVer
    }

    var raw: String? {
        switch self {
        case .any: return nil
        case .exact(let v): return "= \(v)"
        case .compatibleWith(let v): return "~> \(v)"
        case .range(let l, let u):
            var parts:[String] = []
            if let l { parts.append("\(l.op.rawValue) \(l.v)") }
            if let u { parts.append("\(u.op.rawValue) \(u.v)") }
            return parts.joined(separator: ", ")
        case .raw(let s): return s
        }
    }

    func matches(_ v: SemVer, allowPrerelease: Bool) -> Bool {
        if !allowPrerelease, v.prerelease != nil { return false }
        switch self {
        case .any: return true
        case .exact(let x): return v == x
        case .compatibleWith(let base):
            // ~> 1.2.3 => >=1.2.3 && <1.3.0 ; ~> 1.2 => >=1.2.0 && <2.0.0
            let lower = base
            let upper = (base.patch != 0) ? SemVer(base.major, base.minor + 1, 0) : SemVer(base.major + 1, 0, 0)
            return v >= lower && v < upper
        case .range(let l, let u):
            if let l {
                switch l.op {
                case .gt:  if !(v > l.v) { return false }
                case .gte: if !(v >= l.v) { return false }
                case .lt:  if !(v < l.v) { return false }
                case .lte: if !(v <= l.v) { return false }
                }
            }
            if let u {
                switch u.op {
                case .gt:  if !(v > u.v) { return false }
                case .gte: if !(v >= u.v) { return false }
                case .lt:  if !(v < u.v) { return false }
                case .lte: if !(v <= u.v) { return false }
                }
            }
            return true
        case .raw:
            return true
        }
    }
}

// MARK: - Parsers for Podfile / Podfile.lock

enum PodfileParser {
    static func parse(_ text: String, verbose: Bool) -> [String: PodSpec] {
        var result:[String:PodSpec] = [:]
        // matches: pod 'Name', 'constraint', :git => 'url', :branch => 'develop'
        let re = try! NSRegularExpression(pattern: #"pod\s+['"]([^'"]+)['"]\s*(?:,(.*))?"#)
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("pod ") else { continue }
            let ns = line as NSString
            guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            let name = ns.substring(with: m.range(at: 1))
            let tail = (m.range(at: 2).location != NSNotFound) ? ns.substring(with: m.range(at: 2)) : ""

            let opts = parseOptions(tail)
            if let git = opts["git"] {
                if let br = opts["branch"] {
                    result[name] = PodSpec(name: name, requirement: .any, source: .git(url: git, constraint: .branch(br)))
                } else if let tag = opts["tag"] {
                    result[name] = PodSpec(name: name, requirement: .any, source: .git(url: git, constraint: .tag(tag)))
                } else if let cm = opts["commit"] {
                    result[name] = PodSpec(name: name, requirement: .any, source: .git(url: git, constraint: .commit(cm)))
                } else {
                    result[name] = PodSpec(name: name, requirement: .any, source: .git(url: git, constraint: .branch("main")))
                }
                if verbose { fputs("[parse] \(name) <- \(result[name]!.source.description)\n", stderr) }
                continue
            }

            // version constraints inside quotes
            let q = try! NSRegularExpression(pattern: #"'([^']+)'"#)
            let qs = q.matches(in: tail, range: NSRange(location: 0, length: (tail as NSString).length))
                .map { (tail as NSString).substring(with: $0.range(at: 1)) }

            let req: Requirement
            if qs.isEmpty { req = .any }
            else if qs.count == 1 { req = parseOne(qs[0]) }
            else {
                var lower: Requirement.Bound?
                var upper: Requirement.Bound?
                for s in qs {
                    if let b = parseBound(s) {
                        switch b.op { case .gt, .gte: lower = b; case .lt, .lte: upper = b }
                    }
                }
                req = (lower == nil && upper == nil) ? .raw(qs.joined(separator: ", ")) : .range(lower: lower, upper: upper)
            }
            result[name] = PodSpec(name: name, requirement: req, source: .trunk)
            if verbose { fputs("[parse] \(name) req=\(req.raw ?? "any") source=trunk\n", stderr) }
        }
        return result
    }

    private static func parseOptions(_ tail: String) -> [String:String] {
        // :key => 'value' | :key => "value"
        var map:[String:String] = [:]
        let re = try! NSRegularExpression(pattern: #":([a-zA-Z_]+)\s*=>\s*['"]([^'"]+)['"]"#)
        let ns = tail as NSString
        for m in re.matches(in: tail, range: NSRange(location: 0, length: ns.length)) {
            map[ns.substring(with: m.range(at: 1))] = ns.substring(with: m.range(at: 2))
        }
        return map
    }

    private static func parseOne(_ s: String) -> Requirement {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("~>"), let v = SemVer(String(t.dropFirst(2)).trimmed) { return .compatibleWith(v) }
        if t.hasPrefix("="), let v = SemVer(String(t.dropFirst()).trimmed) { return .exact(v) }
        if let b = parseBound(t) {
            return .range(lower: (b.op == .gt || b.op == .gte) ? b : nil,
                          upper: (b.op == .lt || b.op == .lte) ? b : nil)
        }
        if let v = SemVer(t) { return .exact(v) }
        return .raw(t)
    }

    private static func parseBound(_ s: String) -> Requirement.Bound? {
        let parts = s.split(separator: " ")
        guard parts.count == 2,
              let op = Requirement.Bound.Op(rawValue: String(parts[0])),
              let v = SemVer(String(parts[1])) else { return nil }
        return .init(op: op, v: v)
    }
}

struct LockInfo { let lockedVersions:[String:String]; let lockedShas:[String:String] }

enum LockParser {
    static func parse(_ text: String, verbose: Bool) -> LockInfo {
        var versions:[String:String] = [:]
        var shas:[String:String] = [:]
        var inPods = false
        var currentName: String? = nil

        for raw in text.components(separatedBy: .newlines) {
            if raw.hasPrefix("PODS:") { inPods = true; continue }
            if raw.hasPrefix("DEPENDENCIES:") || raw.hasPrefix("SPEC REPOS:") { inPods = false }

            let line = raw.trimmingCharacters(in: .whitespaces)

            if inPods, line.hasPrefix("- ") {
                if let (name, ver) = parsePodLine(line) {
                    versions[name] = ver
                    if verbose { fputs("[lock] \(name) -> \(ver)\n", stderr) }
                }
            }

            // CHECKOUT OPTIONS: section (SHA for git pods)
            if raw.hasPrefix("CHECKOUT OPTIONS:") { currentName = nil; continue }
            if raw.hasSuffix(":") && !raw.contains(" ") {
                // e.g. "ForterSDK:"
                currentName = raw.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if raw.contains(":commit:"), let name = currentName {
                let sha = raw.components(separatedBy: ":commit:").last?.trimmingCharacters(in: .whitespaces)
                if let sha, !sha.isEmpty {
                    shas[name] = sha
                    if verbose { fputs("[lock] \(name) sha=\(sha)\n", stderr) }
                }
            }
        }
        return .init(lockedVersions: versions, lockedShas: shas)
    }

    private static func parsePodLine(_ line: String) -> (String,String)? {
        let re = try! NSRegularExpression(pattern: #"^\-\s+([A-Za-z0-9_\-\+\.\/]+)\s+\(([^)]+)\)"#)
        let ns = line as NSString
        guard let m = re.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let full = ns.substring(with: m.range(at: 1))
        let ver  = ns.substring(with: m.range(at: 2))
        let top  = full.split(separator: "/").first.map(String.init) ?? full
        return (top, ver)
    }
}

// MARK: - Version resolver (CLI) with thread-safe cache

final class VersionResolver {
    // thread-safe cache without actors (CLI-friendly)
    private static let cacheQueue = DispatchQueue(label: "UpdateAnalyzer.cache.queue")
    nonisolated(unsafe) private static var _cache: [String:[SemVer]] = [:]

    let allowPrerelease: Bool
    let verbose: Bool

    init(allowPrerelease: Bool, verbose: Bool) {
        self.allowPrerelease = allowPrerelease
        self.verbose = verbose
    }

    func trunkVersions(for pod: String) -> [SemVer]? {
        // read from cache
        if let cached = Self.cacheQueue.sync(execute: { Self._cache[pod] }) {
            return cached
        }

        guard let txt = shell("/usr/bin/env", "pod", "trunk", "info", pod) else {
            if verbose { fputs("[cli] pod trunk info failed for \(pod)\n", stderr) }
            return nil
        }
        if verbose { fputs("[cli] pod trunk info OK for \(pod)\n", stderr) }

        var out:[SemVer] = []

        // Preferred: bullet list under "Versions:"
        let ns = txt as NSString
        let bulletRe = try! NSRegularExpression(pattern: #"(?m)^\s*-\s+([0-9][0-9A-Za-z\.\-\+]+)\b"#)
        for m in bulletRe.matches(in: txt, range: NSRange(location: 0, length: ns.length)) {
            let s = ns.substring(with: m.range(at: 1))
            if let v = SemVer(s, allowPrerelease: allowPrerelease) { out.append(v) }
        }

        // Fallback: single-line list
        if out.isEmpty, let line = txt.components(separatedBy: .newlines).first(where: { $0.contains("Versions:") }) {
            let raw = line.split(separator: ":", maxSplits: 1).dropFirst().joined(separator: ":")
            let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            out.append(contentsOf: parts.compactMap { SemVer($0, allowPrerelease: allowPrerelease) })
        }

        if out.isEmpty {
            if verbose { fputs("[cli] no versions parsed for \(pod)\n", stderr) }
            return nil
        }

        // write to cache
        Self.cacheQueue.sync { Self._cache[pod] = out }
        return out
    }

    func remoteGitHead(url: String, constraint: PodSpec.GitConstraint) -> String? {
        switch constraint {
        case .commit(let sha): return sha
        case .branch(let b):   return gitLsRemote(url: url, ref: "refs/heads/\(b)")
        case .tag(let t):      return gitLsRemote(url: url, ref: "refs/tags/\(t)")
        }
    }

    private func gitLsRemote(url: String, ref: String) -> String? {
        // typical case
        if let out = shell("/usr/bin/env", "git", "ls-remote", url, ref),
           let first = out.split(separator: "\n").first {
            return first.split(separator: "\t").first.map(String.init)
        }
        // private HTTPS with token
        if let token = ProcessInfo.processInfo.environment["GIT_HTTP_TOKEN"], url.hasPrefix("https://") {
            if let out = shell("/usr/bin/env","git","-c","http.extraHeader=Authorization: Bearer \(token)","ls-remote",url,ref),
               let first = out.split(separator: "\n").first {
                return first.split(separator: "\t").first.map(String.init)
            }
        }
        if verbose { fputs("[git] ls-remote failed url=\(url) ref=\(ref)\n", stderr) }
        return nil
    }
}

// MARK: - SemVer

struct SemVer: Comparable, Hashable, Codable, CustomStringConvertible {
    let major:Int, minor:Int, patch:Int
    let prerelease:String?

    init(_ major:Int,_ minor:Int,_ patch:Int, prerelease:String?=nil) {
        self.major=major; self.minor=minor; self.patch=patch; self.prerelease=prerelease
    }

    init?(_ s:String, allowPrerelease: Bool = true) {
        let parts = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let nums = parts[0].split(separator: ".").map { Int($0) ?? 0 }
        guard nums.count >= 1 else { return nil }
        self.major = nums[safe:0] ?? 0
        self.minor = nums[safe:1] ?? 0
        self.patch = nums[safe:2] ?? 0
        self.prerelease = parts.count > 1 ? String(parts[1]) : nil
        if !allowPrerelease, self.prerelease != nil { return nil }
    }

    static func == (l:Self, r:Self) -> Bool { l.major==r.major && l.minor==r.minor && l.patch==r.patch && l.prerelease==r.prerelease }
    static func <  (l:Self, r:Self) -> Bool {
        if l.major != r.major { return l.major < r.major }
        if l.minor != r.minor { return l.minor < r.minor }
        if l.patch != r.patch { return l.patch < r.patch }
        switch (l.prerelease, r.prerelease) {
        case (nil, nil): return false
        case (nil, _?): return false
        case (_?, nil): return true
        case let (lp?, rp?): return lp < rp
        }
    }

    var description:String { prerelease == nil ? "\(major).\(minor).\(patch)" : "\(major).\(minor).\(patch)-\(prerelease!)" }
}

// MARK: - Helpers

private extension Array { subscript(safe i:Int) -> Element? { (0..<count).contains(i) ? self[i] : nil } }
private extension String { var trimmed:String { trimmingCharacters(in: .whitespacesAndNewlines) } }
private extension JSONEncoder { static var pretty: JSONEncoder { let e = JSONEncoder(); e.outputFormatting=[.prettyPrinted,.sortedKeys]; return e } }

@discardableResult
private func shell(_ launchPath: String, _ args: String...) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    let out = Pipe(); let err = Pipe()
    p.standardOutput = out; p.standardError = err
    do { try p.run() } catch { return nil }
    p.waitUntilExit()
    // CocoaPods sometimes exits with code 1 while still outputting useful info — return stdout anyway.
    return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
}
