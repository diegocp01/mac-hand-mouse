import Foundation

@main struct SourceUpdateTests {
    static var checks = 0
    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fatalError(message) }
    }

    static func main() {
        for origin in SourceUpdate.officialOrigins { check(SourceUpdate.isOfficialOrigin(origin), "Official origin is accepted") }
        for origin in ["https://github.com/example/mac-hand-mouse.git", "file:///tmp/repo", "", "/"] {
            check(!SourceUpdate.isOfficialOrigin(origin), "Untrusted update origin is rejected")
        }
        let old = String(repeating: "a", count: 40), latest = String(repeating: "b", count: 40)
        check(UpdateComparison.evaluate(installedCommit: latest, localCommit: latest, remoteCommit: latest,
            installedVersion: "1", sourceVersion: "1", localIsAncestor: true) == .current,
            "Matching installed, checkout, and remote commits are current")
        check(UpdateComparison.evaluate(installedCommit: old, localCommit: latest, remoteCommit: latest,
            installedVersion: "1", sourceVersion: "1", localIsAncestor: true) == .available,
            "An older installed build is updated even after a previous pull")
        check(UpdateComparison.evaluate(installedCommit: old, localCommit: old, remoteCommit: latest,
            installedVersion: "1", sourceVersion: "2", localIsAncestor: true) == .available,
            "A remote fast-forward is available")
        check(UpdateComparison.evaluate(installedCommit: nil, localCommit: latest, remoteCommit: latest,
            installedVersion: "1.7", sourceVersion: "1.7", localIsAncestor: true) == .current,
            "Legacy builds can fall back to version comparison")
        if case .unsafe = UpdateComparison.evaluate(installedCommit: old, localCommit: old, remoteCommit: latest,
            installedVersion: nil, sourceVersion: nil, localIsAncestor: false) { checks += 1 }
        else { fatalError("Divergent checkouts are unsafe") }
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>9.8.7</string></dict></plist>
        """
        check((try? SourceUpdate.propertyListValue("CFBundleShortVersionString", in: plist)) == "9.8.7",
              "The version shown in the update prompt comes from remote main")
        print("Passed \(checks) source-update trust and comparison checks.")
    }
}
