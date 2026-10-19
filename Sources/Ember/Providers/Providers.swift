import Foundation

// MARK: - Claude Code

struct ClaudeCode: UsageProvider {
    let id = "claude"
    let name = "Claude Code"
    let symbol = "sparkle"
    var paths: [String] { ["~/.claude/projects/**/*.jsonl", "~/.config/claude/projects/**/*.jsonl"] }
    func installed() -> Bool { exists("~/.claude") || exists("~/.config/claude") }

    func scan(cache: FileCache) -> ScanOutput {
        var out = ScanOutput()
        var seen = Set<String>()
        let all = files(under: "~/.claude/projects", ext: ".jsonl") + files(under: "~/.config/claude/projects", ext: ".jsonl")
        cache.prune(keeping: Set(all), prefix: home + "/.claude/projects")
        for f in all {
            let es = cache.entries(for: f) { parse(f) }
            for e in es where seen.insert(e.key).inserted { out.entries.append(e) }
        }
        return out
    }

    private func parse(_ path: String) -> [Entry] {
        var best: [String: Entry] = [:]
        readLines(path) { line in
            // Cheap pre-filter: only assistant lines carry usage.
            guard line.contains("\"usage\"") , let d = json(line),
                d["type"] as? String == "assistant",
                let msg = d["message"] as? [String: Any],
                let u = msg["usage"] as? [String: Any],
                let model = msg["model"] as? String, model != "<synthetic>",
                let tsText = d["timestamp"] as? String, let ts = Day.parse(tsText)
            else { return }
            let key = (msg["id"] as? String ?? "") + "|" + (d["requestId"] as? String ?? d["uuid"] as? String ?? "")
            let e = Entry(
                key: key, ts: ts.timeIntervalSince1970, model: model,
                project: shortProject(d["cwd"] as? String ?? ""),
                input: int(u["input_tokens"]), output: int(u["output_tokens"]),
                cacheRead: int(u["cache_read_input_tokens"]), cacheWrite: int(u["cache_creation_input_tokens"]))
            // Streaming writes the same message several times; the last has final counts.
            if let old = best[key], old.output > e.output { return }
            best[key] = e
        }
        return Array(best.values)
    }
}

// MARK: - Codex (rollouts are .jsonl.zst; falls back to the thread table)

struct Codex: UsageProvider {
    let id = "codex"
    let name = "Codex"
    let symbol = "chevron.left.forwardslash.chevron.right"
    var paths: [String] { ["~/.codex/sessions/**/*.jsonl(.zst)", "~/.codex/state_5.sqlite"] }
    func installed() -> Bool { exists("~/.codex") }

    static var zstd: String? {
        ["/opt/homebrew/bin/zstd", "/usr/local/bin/zstd", "/usr/bin/zstd"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func scan(cache: FileCache) -> ScanOutput {
        var out = ScanOutput()
        let rollouts = files(under: "~/.codex/sessions", ext: ".jsonl.zst") + files(under: "~/.codex/sessions", ext: ".jsonl")
        var covered = Set<String>()
        var latestQuota: (Double, [QuotaWindow])?
        for f in rollouts {
            let id = Codex.sessionID(f)
            covered.insert(id)
            let es = cache.entries(for: f) { parse(f) }
            out.entries += es
            // Quota snapshots are cached as a pseudo-entry in the same file cache.
            if let q = es.first(where: { $0.key.hasPrefix("quota|") }), latestQuota == nil || q.ts > latestQuota!.0 {
                latestQuota = (q.ts, Codex.decodeQuota(q.model, ts: q.ts))
            }
            for q in es where q.key.hasPrefix("quota|") {
                for w in Codex.decodeQuota(q.model, ts: q.ts) {
                    guard let r = w.resetsAt else { continue }
                    out.quotaSamples.append(QuotaSample(provider: "codex", label: w.label, t: q.ts, used: w.usedPercent,
                                                        resets: r.timeIntervalSince1970, src: "journal local"))
                }
            }
        }
        out.entries.removeAll { $0.key.hasPrefix("quota|") }
        if let q = latestQuota, Date().timeIntervalSince1970 - q.0 < 14 * 86400 { out.quotas = q.1 }

        // Threads whose rollout could not be read: use the stored total with a blended rate.
        let db = expand("~/.codex/state_5.sqlite")
        SQL.query(db, "select id, model, cwd, tokens_used, updated_at from threads where tokens_used > 0") { st in
            let id = SQL.text(st, 0)
            if covered.contains(id) { return }
            let total = SQL.int(st, 3)
            out.entries.append(Entry(
                key: "codex|" + id, ts: Double(SQL.int(st, 4)), model: SQL.text(st, 1).isEmpty ? "gpt-5" : SQL.text(st, 1),
                project: shortProject(SQL.text(st, 2)),
                input: Int(Double(total) * 0.85), output: Int(Double(total) * 0.15), cacheRead: 0, cacheWrite: 0, estimated: true))
        }
        return out
    }

    static func sessionID(_ path: String) -> String {
        let n = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let base = n.hasSuffix(".jsonl") ? String(n.dropLast(6)) : n
        // rollout-YYYY-MM-DDTHH-MM-SS-<uuid>
        return String(base.suffix(36))
    }

    static func encodeQuota(_ w: [(String, Double, Double?)]) -> String {
        w.map { "\($0.0),\($0.1),\($0.2 ?? 0)" }.joined(separator: ";")
    }
    static func decodeQuota(_ s: String, ts: Double) -> [QuotaWindow] {
        s.split(separator: ";").compactMap { part in
            let p = part.split(separator: ",")
            guard p.count == 3, let used = Double(p[1]), let reset = Double(p[2]) else { return nil }
            return QuotaWindow(provider: "codex", label: String(p[0]), usedPercent: used,
                               resetsAt: reset > 0 ? Date(timeIntervalSince1970: reset) : nil, source: "journal local")
        }
    }

    private func readRollout(_ path: String) -> String? {
        if path.hasSuffix(".zst") {
            guard let z = Codex.zstd else { return nil }
            let p = Process()
            p.executableURL = URL(fileURLWithPath: z)
            p.arguments = ["-dc", path]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            do { try p.run() } catch { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return String(data: data, encoding: .utf8)
        }
        return (try? String(contentsOfFile: path, encoding: .utf8))
    }

    private func parse(_ path: String) -> [Entry] {
        guard let text = readRollout(path) else { return [] }
        var cwd = "", model = "gpt-5", lastTs = 0.0
        var usage: [String: Any]?
        var quota: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let isTok = line.contains("\"token_count\"")
            let isMeta = line.contains("\"session_meta\"") || line.contains("\"turn_context\"")
            guard isTok || isMeta, let d = json(line) else { continue }
            if let t = d["timestamp"] as? String, let dt = Day.parse(t) { lastTs = dt.timeIntervalSince1970 }
            guard let p = d["payload"] as? [String: Any] else { continue }
            if d["type"] as? String == "session_meta", let c = p["cwd"] as? String { cwd = c }
            if d["type"] as? String == "turn_context", let m = p["model"] as? String { model = m }
            if p["type"] as? String == "token_count" {
                if let info = p["info"] as? [String: Any], let t = info["total_token_usage"] as? [String: Any] { usage = t }
                if let rl = p["rate_limits"] as? [String: Any] {
                    var w: [(String, Double, Double?)] = []
                    for k in ["primary", "secondary"] {
                        if let x = rl[k] as? [String: Any], let used = x["used_percent"] as? Double {
                            let mins = int(x["window_minutes"])
                            let label = mins >= 1440 ? "\(mins / 1440) j" : "\(mins / 60) h"
                            w.append((label, used, (x["resets_at"] as? Double)))
                        }
                    }
                    if !w.isEmpty { quota = Codex.encodeQuota(w) }
                }
            }
        }
        guard let u = usage else { return [] }
        let cached = int(u["cached_input_tokens"])
        var es = [Entry(
            key: "codex|" + Codex.sessionID(path), ts: lastTs, model: model, project: shortProject(cwd),
            input: max(0, int(u["input_tokens"]) - cached), output: int(u["output_tokens"]),
            cacheRead: cached, cacheWrite: int(u["cache_write_input_tokens"]))]
        if let q = quota {
            es.append(Entry(key: "quota|" + path, ts: lastTs, model: q, project: "", input: 0, output: 0, cacheRead: 0, cacheWrite: 0))
        }
        return es
    }
}

// MARK: - Gemini CLI

struct GeminiCLI: UsageProvider {
    let id = "gemini"
    let name = "Gemini CLI"
    let symbol = "diamond"
    var paths: [String] { ["~/.gemini/tmp/*/chats/*.json"] }
    func installed() -> Bool { exists("~/.gemini") }

    func scan(cache: FileCache) -> ScanOutput {
        var out = ScanOutput()
        for f in files(under: "~/.gemini/tmp", ext: ".json") where f.contains("/chats/") {
            out.entries += cache.entries(for: f) { parse(f) }
        }
        return out
    }

    private func parse(_ path: String) -> [Entry] {
        guard let data = FileManager.default.contents(atPath: path),
            let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let msgs = d["messages"] as? [[String: Any]]
        else { return [] }
        let proj = path.components(separatedBy: "/tmp/").last?.components(separatedBy: "/").first ?? ""
        return msgs.compactMap { m in
            guard m["type"] as? String == "gemini", let t = m["tokens"] as? [String: Any],
                let ts = (m["timestamp"] as? String).flatMap(Day.parse)
            else { return nil }
            let cached = int(t["cached"])
            return Entry(
                key: "gemini|" + (m["id"] as? String ?? UUID().uuidString), ts: ts.timeIntervalSince1970,
                model: m["model"] as? String ?? "gemini", project: proj.count > 20 ? "gemini" : proj,
                input: max(0, int(t["input"]) - cached), output: int(t["output"]) + int(t["thoughts"]) + int(t["tool"]),
                cacheRead: cached, cacheWrite: 0)
        }
    }
}

// MARK: - Kiro CLI (Amazon Q) — conversations only; credits are not stored locally

struct KiroCLI: UsageProvider {
    let id = "kiro"
    let name = "Kiro CLI"
    let symbol = "curlybraces"
    var paths: [String] { ["~/Library/Application Support/kiro-cli/data.sqlite3 (conversations)"] }
    func installed() -> Bool { exists("~/Library/Application Support/kiro-cli") || exists("/Applications/Kiro CLI.app") }

    func scan(cache: FileCache) -> ScanOutput {
        // Kiro bills in credits, not tokens, and keeps no token counts on disk.
        // Message counts are exposed so the provider shows activity instead of a false cost.
        var out = ScanOutput()
        let db = expand("~/Library/Application Support/kiro-cli/data.sqlite3")
        SQL.query(db, "select key, conversation_id, value, updated_at from conversations_v2") { st in
            let key = SQL.text(st, 0), cid = SQL.text(st, 1), value = SQL.text(st, 2)
            let turns = value.components(separatedBy: "\"user\":{").count - 1
            guard turns > 0 else { return }
            out.entries.append(Entry(
                key: "kiro|" + cid, ts: Double(SQL.int(st, 3)) / 1000, model: "kiro", project: shortProject(key),
                input: 0, output: 0, cacheRead: 0, cacheWrite: 0, estimated: true))
        }
        return out
    }
}

// MARK: - Cursor — conversations from the local state DB; token counts are estimated

struct CursorIDE: UsageProvider {
    let id = "cursor"
    let name = "Cursor"
    let symbol = "cursorarrow.rays"
    static let db = "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    var paths: [String] { [Self.db + " (conversations)"] }
    func installed() -> Bool { exists("/Applications/Cursor.app") || exists("~/.cursor") }

    func scan(cache: FileCache) -> ScanOutput {
        // Cursor bills server-side and stores tokenCount = 0 locally. Input comes from the
        // conversation's context size, output from the assistant text length (~4 chars/token).
        var out = ScanOutput()
        let path = expand(Self.db)
        var outChars: [String: Int] = [:]
        SQL.query(path, """
            select substr(key, 10, 36), sum(length(json_extract(value, '$.text')))
            from cursorDiskKV where key like 'bubbleId:%' and json_extract(value, '$.type') = 2 group by 1
            """) { st in outChars[SQL.text(st, 0)] = SQL.int(st, 1) }
        SQL.query(path, """
            select json_extract(value, '$.composerId'), json_extract(value, '$.modelConfig.modelName'),
                   json_extract(value, '$.contextTokensUsed'), coalesce(json_extract(value, '$.lastUpdatedAt'), json_extract(value, '$.createdAt'))
            from cursorDiskKV where key like 'composerData:%'
            """) { st in
            let cid = SQL.text(st, 0)
            let ctx = SQL.int(st, 2), chars = outChars[cid] ?? 0
            guard !cid.isEmpty, cid != "empty-state-draft", ctx > 0 || chars > 0 else { return }
            let model = SQL.text(st, 1)
            out.entries.append(Entry(
                key: "cursor|" + cid, ts: Double(SQL.int(st, 3)) / 1000, model: model.isEmpty ? "cursor" : model,
                project: "cursor", input: ctx, output: chars / 4, cacheRead: 0, cacheWrite: 0, estimated: true))
        }
        return out
    }
}

// MARK: - Providers with no usable local token data (detected only)

struct Detected: UsageProvider {
    let id: String
    let name: String
    let symbol: String
    let probes: [String]
    let reason: String
    var paths: [String] { probes }
    func installed() -> Bool { probes.contains(where: exists) }
    func scan(cache: FileCache) -> ScanOutput { ScanOutput() }
}
