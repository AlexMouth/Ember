import AppKit
import SwiftUI

/// Real app icon of each AI, read from the locally installed application bundle
/// (nothing is copied or bundled); falls back to an SF Symbol when the app is absent.
enum IconCache {
    static let apps: [String: [String]] = [
        "claude": ["/Applications/Claude.app"],
        "claude-desktop": ["/Applications/Claude.app"],
        "codex": ["/Applications/Codex.app", "/Applications/ChatGPT.app"],
        "chatgpt": ["/Applications/ChatGPT.app"],
        "gemini": ["/Applications/Gemini.app"],
        "gemini-app": ["/Applications/Gemini.app"],
        "kiro": ["/Applications/Kiro CLI.app", "/Applications/Kiro.app"],
        "cursor": ["/Applications/Cursor.app"],
        "copilot": ["/Applications/Visual Studio Code.app"],
        "ollama": ["/Applications/Ollama.app"],
    ]
    nonisolated(unsafe) private static var cache: [String: NSImage?] = [:]

    static func image(_ id: String) -> NSImage? {
        if let c = cache[id] { return c }
        let img = (apps[id] ?? []).first { FileManager.default.fileExists(atPath: $0) }
            .map { NSWorkspace.shared.icon(forFile: $0) }
        cache[id] = .some(img)
        return img
    }
}

struct ProviderIcon: View {
    let id: String
    var symbol: String = "sparkles"
    var size: CGFloat = 16
    var body: some View {
        if let img = IconCache.image(id) {
            Image(nsImage: img).resizable().interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: symbol).foregroundStyle(color(for: id)).frame(width: size, height: size)
        }
    }
}
