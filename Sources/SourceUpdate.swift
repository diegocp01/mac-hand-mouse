import Foundation

enum UpdateComparison: Equatable {
    case current
    case available
    case unsafe(String)

    static func evaluate(installedCommit: String?, localCommit: String, remoteCommit: String,
                         installedVersion: String?, sourceVersion: String?, localIsAncestor: Bool) -> Self {
        guard localIsAncestor else { return .unsafe("The local checkout has commits that are not on GitHub.") }
        if let installedCommit, !installedCommit.isEmpty {
            return installedCommit == remoteCommit && localCommit == remoteCommit ? .current : .available
        }
        return localCommit == remoteCommit && installedVersion == sourceVersion ? .current : .available
    }
}

struct UpdateCheck {
    var comparison: UpdateComparison
    var localCommit: String
    var remoteCommit: String
    var remoteVersion: String?
}

enum SourceUpdate {
    static let officialOrigins: Set<String> = [
        "https://github.com/diegocp01/mac-hand-mouse.git",
        "https://github.com/diegocp01/mac-hand-mouse",
        "git@github.com:diegocp01/mac-hand-mouse.git",
        "git@github.com:diegocp01/mac-hand-mouse",
        "ssh://git@github.com/diegocp01/mac-hand-mouse.git",
        "ssh://git@github.com/diegocp01/mac-hand-mouse"
    ]

    static func isOfficialOrigin(_ value: String) -> Bool {
        officialOrigins.contains(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func stateDirectory(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Hand Mouse", isDirectory: true)
    }

    static func checkoutURL(fileManager: FileManager = .default) -> URL? {
        guard let directory = stateDirectory(fileManager: fileManager),
              let data = try? Data(contentsOf: directory.appendingPathComponent("source-checkout")),
              data.count <= 4096, let raw = String(data: data, encoding: .utf8) else { return nil }
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !path.contains("\n"), path != "/" else { return nil }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    static func takeResult(fileManager: FileManager = .default) -> (success: Bool, detail: String)? {
        guard let directory = stateDirectory(fileManager: fileManager) else { return nil }
        let url = directory.appendingPathComponent("update-result")
        guard let data = try? Data(contentsOf: url), data.count <= 8192,
              let text = String(data: data, encoding: .utf8) else { return nil }
        try? fileManager.removeItem(at: url)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return nil }
        return (first == "success", lines.dropFirst().joined(separator: "\n"))
    }

    static func check(checkout: URL, installedCommit: String?, installedVersion: String?) throws -> UpdateCheck {
        guard checkout.path != "/", FileManager.default.fileExists(atPath: checkout.appendingPathComponent(".git").path) else {
            throw UpdateError("The saved source checkout is unavailable. Reinstall Hand Mouse from its GitHub checkout to restore updates.")
        }
        let origin = try git(["config", "--get", "remote.origin.url"], at: checkout).output
        guard isOfficialOrigin(origin) else {
            throw UpdateError("Updates are blocked because this checkout does not use the official Hand Mouse GitHub repository.")
        }
        guard try git(["symbolic-ref", "--short", "HEAD"], at: checkout).output == "main" else {
            throw UpdateError("Switch the source checkout to the main branch before updating.")
        }
        guard try git(["status", "--porcelain", "--untracked-files=normal"], at: checkout).output.isEmpty else {
            throw UpdateError("The source checkout has local changes. Commit or move them before updating Hand Mouse.")
        }
        _ = try git(["fetch", "--quiet", "origin", "main"], at: checkout)
        let local = try git(["rev-parse", "HEAD"], at: checkout).output
        let remote = try git(["rev-parse", "origin/main"], at: checkout).output
        let ancestor = runGit(["merge-base", "--is-ancestor", local, remote], at: checkout).status == 0
        let remotePlist = try git(["show", "origin/main:Info.plist"], at: checkout).output
        let remoteVersion = try? propertyListValue("CFBundleShortVersionString", in: remotePlist)
        return UpdateCheck(comparison: .evaluate(installedCommit: installedCommit, localCommit: local,
            remoteCommit: remote, installedVersion: installedVersion, sourceVersion: remoteVersion,
            localIsAncestor: ancestor), localCommit: local, remoteCommit: remote, remoteVersion: remoteVersion)
    }

    static func propertyListValue(_ key: String, at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return try propertyListValue(key, data: data)
    }

    static func propertyListValue(_ key: String, in text: String) throws -> String {
        guard let data = text.data(using: .utf8) else { throw UpdateError("The source version could not be read.") }
        return try propertyListValue(key, data: data)
    }

    private static func propertyListValue(_ key: String, data: Data) throws -> String {
        guard let dictionary = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let value = dictionary[key] as? String else { throw UpdateError("The source version could not be read.") }
        return value
    }

    private struct CommandResult { var status: Int32; var output: String }

    private static func git(_ arguments: [String], at checkout: URL) throws -> CommandResult {
        let result = runGit(arguments, at: checkout)
        guard result.status == 0 else {
            throw UpdateError(result.output.isEmpty ? "Git could not check for updates." : result.output)
        }
        return result
    }

    private static func runGit(_ arguments: [String], at checkout: URL) -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = checkout
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_SSH_COMMAND"] = "/usr/bin/ssh -oBatchMode=yes -oStrictHostKeyChecking=yes -oConnectTimeout=15"
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return CommandResult(status: -1, output: error.localizedDescription) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            if process.isRunning { process.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return CommandResult(status: process.terminationStatus, output: output)
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
