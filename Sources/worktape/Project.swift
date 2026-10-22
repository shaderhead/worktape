import Foundation

struct Project {
    let root: String

    var name: String { (root as NSString).lastPathComponent }
    var recordings: String { (root as NSString).appendingPathComponent(".worktapes") }

    static func containing(_ directory: String) -> Project? {
        var directory = (directory as NSString).standardizingPath
        while true {
            var isDirectory: ObjCBool = false
            let project = Project(root: directory)
            if FileManager.default.fileExists(atPath: project.recordings, isDirectory: &isDirectory), isDirectory.boolValue {
                return project
            }
            guard directory != "/" else { return nil }
            directory = (directory as NSString).deletingLastPathComponent
        }
    }
}

func timestamp() -> String {
    timestampFormatter.string(from: Date())
}

private let timestampFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    return formatter
}()
