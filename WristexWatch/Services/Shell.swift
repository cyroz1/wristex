import Foundation

enum Shell {
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func quotePath(_ path: String) -> String {
        if path == "~" { return "\"$HOME\"" }
        if path.hasPrefix("~/") {
            return "\"$HOME\"/" + quote(String(path.dropFirst(2)))
        }
        return quote(path)
    }
}
