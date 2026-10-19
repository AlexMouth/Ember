import Foundation

/// Providers are re-evaluated on every refresh: the readers Ember knows, a catalog of
/// well-known AI tools, and anything on disk whose name looks like an AI tool.
/// A new agent installed (or first used) therefore shows up without touching Ember.
enum Discovery {
    /// (id, display name, SF symbol, probes)
    static let catalog: [(String, String, String, [String])] = [
        ("copilot", "GitHub Copilot", "airplane", ["~/.copilot", "~/.config/github-copilot"]),
        ("chatgpt", "ChatGPT (app)", "bubble.left.and.bubble.right", ["/Applications/ChatGPT.app"]),
        ("claude-desktop", "Claude (app)", "text.bubble", ["/Applications/Claude.app"]),
        ("gemini-app", "Gemini (app)", "sparkles", ["/Applications/Gemini.app"]),
        ("kimi", "Kimi (app)", "moon.stars", ["/Applications/Kimi.app"]),
        ("ollama", "Ollama", "cpu", ["~/.ollama", "/Applications/Ollama.app"]),
        ("opencode", "OpenCode", "terminal", ["~/.local/share/opencode", "~/.config/opencode"]),
        ("aider", "Aider", "wrench", ["~/.aider.chat.history.md", "~/.aider"]),
        ("windsurf", "Windsurf", "wind", ["/Applications/Windsurf.app", "~/.windsurf", "~/.codeium"]),
        ("zed", "Zed", "bolt", ["/Applications/Zed.app"]),
        ("antigravity", "Antigravity", "arrow.up.forward.circle", ["/Applications/Antigravity.app", "~/.antigravity"]),
        ("trae", "Trae", "t.circle", ["/Applications/Trae.app"]),
        ("lmstudio", "LM Studio", "cube", ["/Applications/LM Studio.app", "~/.lmstudio"]),
        ("perplexity", "Perplexity", "magnifyingglass", ["/Applications/Perplexity.app"]),
        ("grok", "Grok", "xmark.circle", ["/Applications/Grok.app"]),
        ("mistral", "Mistral / Vibe", "wind", ["~/.vibe", "/Applications/Le Chat.app"]),
        ("qwen", "Qwen Code", "q.circle", ["~/.qwen"]),
        ("goose", "Goose", "bird", ["~/.config/goose", "~/.local/share/goose"]),
        ("amp", "Amp", "bolt.circle", ["~/.amp", "~/.config/amp"]),
        ("droid", "Factory Droid", "gearshape.2", ["~/.factory"]),
        ("cline", "Cline", "terminal.fill", ["~/.cline"]),
        ("continue", "Continue", "arrow.right.circle", ["~/.continue"]),
        ("crush", "Crush", "sparkle", ["~/.config/crush", "~/.local/share/crush"]),
        ("warp", "Warp", "terminal", ["/Applications/Warp.app"]),
        ("deepseek", "DeepSeek", "water.waves", ["/Applications/DeepSeek.app"]),
    ]

    /// Name fragments that make an unknown app or dot-folder look like an AI tool.
    static let keywords = ["claude", "codex", "gpt", "gemini", "copilot", "llm", "openai", "anthropic", "deepseek",
                           "mistral", "grok", "qwen", "kimi", "perplexity", "cursor", "windsurf", "cline", "aider",
                           "ollama", "opencode", "kiro", "agent-cli", "-ai", "ai-"]
    static let ignore = ["ember", "claude code url handler", "chrome", "brave", "chromium", "comet"]

    static func providers() -> [UsageProvider] {
        var list: [UsageProvider] = [ClaudeCode(), Codex(), GeminiCLI(), KiroCLI(), CursorIDE()]
        var known = Set(list.map { $0.id })
        var probed = Set<String>()  // lower-cased paths already covered
        for (id, name, sym, probes) in catalog {
            list.append(Detected(id: id, name: name, symbol: sym, probes: probes, reason: "Détecté automatiquement (aucun journal d'usage exploitable pour l'instant)."))
            known.insert(id)
            probes.forEach { probed.insert(expand($0).lowercased()) }
        }
        // Anything else that looks like an AI tool.
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var candidates: [(String, String)] = []  // (display name, path)
        for dir in ["/Applications", home + "/Applications"] {
            for n in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where n.hasSuffix(".app") {
                candidates.append((String(n.dropLast(4)), dir + "/" + n))
            }
        }
        for n in (try? fm.contentsOfDirectory(atPath: home)) ?? [] where n.hasPrefix(".") && n.count > 2 && !n.dropFirst().contains(".") {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: home + "/" + n, isDirectory: &isDir), isDir.boolValue else { continue }
            candidates.append((String(n.dropFirst()), home + "/" + n))
        }
        for (name, path) in candidates {
            let low = name.lowercased()
            guard keywords.contains(where: { low.contains($0) }), !ignore.contains(where: { low.contains($0) }),
                  !probed.contains(path.lowercased()) else { continue }
            let id = "auto-" + low.replacingOccurrences(of: " ", with: "-")
            if known.contains(id) || known.contains(low) { continue }
            // Skip tools Ember already reads natively.
            let bases = ["claude", "codex", "gemini", "kiro", "cursor", "chatgpt", "kimi", "ollama", "opencode", "aider"]
            if bases.contains(where: { low == $0 || low.hasPrefix($0 + " ") || low.hasPrefix($0 + "-") || low.hasPrefix($0 + "_") }) { continue }
            known.insert(id)
            list.append(Detected(id: id, name: name.prefix(1).uppercased() + name.dropFirst(), symbol: "sparkle.magnifyingglass",
                                 probes: [path], reason: "Nouvel agent détecté automatiquement."))
        }
        return list
    }
}
