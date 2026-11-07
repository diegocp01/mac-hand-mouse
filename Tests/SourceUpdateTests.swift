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
        check(UpdateComparison.evaluate(installedCommit: latest, remoteCommit: latest,
            installedVersion: "1", sourceVersion: "1") == .current,
            "Matching installed and remote commits are current")
        check(UpdateComparison.evaluate(installedCommit: old, remoteCommit: latest,
            installedVersion: "1", sourceVersion: "1") == .available,
            "An older installed build is updated even after a previous pull")
        check(UpdateComparison.evaluate(installedCommit: old, remoteCommit: latest,
            installedVersion: "1", sourceVersion: "2") == .available,
            "A newer remote commit is available")
        check(UpdateComparison.evaluate(installedCommit: nil, remoteCommit: latest,
            installedVersion: "1.7", sourceVersion: "1.7") == .current,
            "Legacy builds can fall back to version comparison")
        check(UpdateComparison.evaluate(installedCommit: nil, remoteCommit: latest,
            installedVersion: "1.7", sourceVersion: "1.8") == .available,
            "Legacy builds detect a newer version")
        check(UpdateComparison.evaluate(installedCommit: nil, remoteCommit: latest,
            installedVersion: nil, sourceVersion: nil) == .available,
            "Missing legacy version metadata does not hide an update")
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>9.8.7</string></dict></plist>
        """
        check((try? SourceUpdate.propertyListValue("CFBundleShortVersionString", in: plist)) == "9.8.7",
              "The version shown in the update prompt comes from remote main")
        print("Passed \(checks) source-update trust and comparison checks.")
    }
}
