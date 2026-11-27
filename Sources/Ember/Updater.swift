import AppKit
import CryptoKit
import SwiftUI

/// Self-update from GitHub Releases: checks the latest release, downloads the ZIP,
/// verifies its Ed25519 signature (`.sig` asset) against the public key built into Ember,
/// checks the code signature and bundle identity, then swaps the bundle atomically once Ember has quit.
/// The `.sha256` asset is no longer trusted: it comes from the same release as the ZIP, so anyone
/// able to replace one could replace the other. Only the holder of the private key can sign.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "AlexMouth/Ember"
    /// Public half of the release signing key (scripts/sign_update.swift pubkey).
    nonisolated static let publicKey = "gJi2mKJKM6UKmBVkZt/l5WT64sH1Z3fI2EPVa6G94k0="

    enum State: Equatable {
        case idle, checking, upToDate
        case available(version: String, url: URL)
        case downloading(Double)  // 0...1
        case installing
        case failed(String)
    }

    @Published var state: State = .idle
    private var timer: Timer?
    /// URL of the signature asset that goes with the available ZIP.
    private var signatureURL: URL?

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    var hasUpdate: Bool { if case .available = state { return true } else { return false } }

    func startAutoCheck() {
        check(silent: true)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in Updater.shared.check(silent: true) }
        }
    }

    /// Semantic-version comparison: numeric core first, then a release beats any
    /// pre-release of the same core ("1.0" > "1.0-beta"), then pre-release identifiers
    /// compared one by one (numbers numerically, text lexically).
    nonisolated static func newer(_ a: String, than b: String) -> Bool {
        func split(_ v: String) -> (core: [Int], pre: [Substring]) {
            let v = v.hasPrefix("v") ? v.dropFirst() : Substring(v)
            let noBuild = v.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false).first ?? v
            let parts = noBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
            let core = parts[0].split(separator: ".").map { Int($0) ?? 0 }
            let pre = parts.count > 1 ? parts[1].split(separator: ".") : []
            return (core, pre)
        }
        let x = split(a), y = split(b)
        for i in 0..<max(x.core.count, y.core.count) {
            let l = i < x.core.count ? x.core[i] : 0, r = i < y.core.count ? y.core[i] : 0
            if l != r { return l > r }
        }
        switch (x.pre.isEmpty, y.pre.isEmpty) {
        case (true, true): return false
        case (true, false): return true
        case (false, true): return false
        default: break
        }
        for i in 0..<max(x.pre.count, y.pre.count) {
            guard i < x.pre.count else { return false }
            guard i < y.pre.count else { return true }
            let l = x.pre[i], r = y.pre[i]
            if l == r { continue }
            switch (Int(l), Int(r)) {
            case let (li?, ri?): return li > ri
            case (.some, nil): return false   // numeric identifiers sort before text
            case (nil, .some): return true
            default: return l > r
            }
        }
        return false
    }

    /// True when `signature` (base64 text of a `.sig` asset) is a valid Ed25519 signature of `data`
    /// by the key whose public half is `key` (base64).
    nonisolated static func isSigned(_ data: Data, signature: String, key: String = publicKey) -> Bool {
        guard let raw = Data(base64Encoded: key), let pk = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              let sig = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return pk.isValidSignature(sig, for: data)
    }

    /// Requests carry no cookies, no credentials and leave nothing in the disk cache.
    nonisolated static let session = URLSession(configuration: .ephemeral)

    func check(silent: Bool = false) {
        switch state { case .checking, .downloading, .installing: return; default: break }
        if !silent { state = .checking }
        Task {
            do {
                var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                req.timeoutInterval = 15
                let (data, resp) = try await Self.session.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200,
                      let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = j["tag_name"] as? String else {
                    throw Self.error("Impossible de lire la dernière version (dépôt privé ou hors ligne).")
                }
                let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let urls = (j["assets"] as? [[String: Any]] ?? []).compactMap { $0["browser_download_url"] as? String }
                let zip = urls.first { $0.hasSuffix(".zip") }
                if Self.newer(v, than: current), let z = zip, let u = URL(string: z) {
                    signatureURL = urls.first { $0 == z + ".sig" }.flatMap(URL.init(string:))
                    state = .available(version: v, url: u)
                } else {
                    state = silent ? .idle : .upToDate
                }
            } catch {
                state = silent ? .idle : .failed(error.localizedDescription)
            }
        }
    }

    func install() {
        guard case .available(let version, let url) = state else { return }
        let target = Bundle.main.bundleURL
        guard target.pathExtension == "app", !target.path.contains("/.build/") else {
            state = .failed("Ember ne tourne pas depuis une app installée. Installez-la dans /Applications pour activer la mise à jour.")
            return
        }
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            state = .failed("Dossier d'installation non modifiable : \(target.deletingLastPathComponent().path)")
            return
        }
        guard let sigURL = signatureURL else {
            state = .failed("Cette version n'est pas signée : mise à jour refusée. Téléchargez-la manuellement depuis GitHub.")
            return
        }
        state = .downloading(0)
        let bundleID = Bundle.main.bundleIdentifier
        Task {
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("ember-update-\(UUID().uuidString)")
            do {
                var sigReq = URLRequest(url: sigURL); sigReq.timeoutInterval = 15
                let (sigData, sigResp) = try await Self.session.data(for: sigReq)
                guard (sigResp as? HTTPURLResponse)?.statusCode == 200, sigData.count < 1024 else {
                    throw Self.error("Signature de la mise à jour illisible.")
                }
                let signature = String(decoding: sigData, as: UTF8.self)
                let progress = DownloadProgress { f in Task { @MainActor in
                    if case .downloading = Updater.shared.state { Updater.shared.state = .downloading(f) }
                } }
                let (tmp, resp) = try await Self.session.download(from: url, delegate: progress)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let zip = work.appendingPathComponent("Ember.zip")
                try FileManager.default.moveItem(at: tmp, to: zip)
                let newApp = try await Task.detached(priority: .userInitiated) {
                    try Self.verifyAndExtract(zip: zip, work: work, signature: signature, bundleID: bundleID, version: version)
                }.value
                state = .installing
                try Self.launchSwap(target: target, newApp: newApp, work: work)
                NSApp.terminate(nil)
            } catch {
                try? FileManager.default.removeItem(at: work)
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Runs after Ember quits. The new bundle is first copied next to the old one, then
    /// the two are swapped with renames (same volume, so each step is atomic). If any step
    /// fails the old bundle is put back, and Ember is relaunched either way.
    private static func launchSwap(target: URL, newApp: URL, work: URL) throws {
        let script = """
        T="$1"; N="$2"; W="$3"; D="$(dirname "$T")"
        STAGE="$D/.Ember-update.app"; OLD="$D/.Ember-previous.app"
        i=0; while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null && [ $i -lt 300 ]; do sleep 0.2; i=$((i+1)); done
        rm -rf "$STAGE" "$OLD"
        if ditto "$N" "$STAGE" && xattr -cr "$STAGE"; then
          if mv "$T" "$OLD"; then
            if mv "$STAGE" "$T"; then rm -rf "$OLD"; else mv "$OLD" "$T"; fi
          fi
        fi
        rm -rf "$STAGE"
        open "$T"
        rm -rf "$W"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "sh", target.path, newApp.path, work.path]
        try p.run()
    }

    /// Checks the archive's Ed25519 signature, unpacks it and validates the bundle inside
    /// (code signature, identifier, version). Runs off the main thread: ditto can take seconds.
    nonisolated static func verifyAndExtract(zip: URL, work: URL, signature: String, bundleID: String?, version: String) throws -> URL {
        let data = try Data(contentsOf: zip, options: .mappedIfSafe)
        guard isSigned(data, signature: signature) else {
            throw error("La signature de la mise à jour est invalide : installation annulée.")
        }
        let out = work.appendingPathComponent("out")
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path])
        let newApp = out.appendingPathComponent("Ember.app")
        guard FileManager.default.fileExists(atPath: newApp.path) else { throw error("Archive invalide : Ember.app introuvable.") }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
        let info = Bundle(url: newApp)?.infoDictionary
        guard info?["CFBundleIdentifier"] as? String == bundleID else {
            throw error("L'archive ne contient pas Ember (identifiant différent).")
        }
        guard (info?["CFBundleShortVersionString"] as? String) == version else {
            throw error("La version de l'archive ne correspond pas à la release \(version).")
        }
        return newApp
    }

    private nonisolated static func error(_ m: String) -> NSError {
        NSError(domain: "Updater", code: 1, userInfo: [NSLocalizedDescriptionKey: m])
    }

    private nonisolated static func run(_ exe: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        p.standardError = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 { throw error("\((exe as NSString).lastPathComponent) a échoué") }
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void
    init(_ f: @escaping (Double) -> Void) { onProgress = f }
    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didWriteData _: Int64, totalBytesWritten w: Int64, totalBytesExpectedToWrite e: Int64) {
        if e > 0 { onProgress(Double(w) / Double(e)) }
    }
    func urlSession(_ s: URLSession, downloadTask t: URLSessionDownloadTask, didFinishDownloadingTo l: URL) {}
}

/// Status line + action button, reused in the popover and in Settings.
struct UpdateRow: View {
    @ObservedObject var up = Updater.shared
    var body: some View {
        HStack(spacing: 8) {
            switch up.state {
            case .idle, .upToDate:
                Text(up.state == .upToDate ? "Ember est à jour (v\(up.current))" : "Version \(up.current)").foregroundStyle(.secondary)
                Spacer()
                Button("Rechercher") { up.check() }
            case .checking:
                ProgressView().controlSize(.small); Text("Recherche…").foregroundStyle(.secondary); Spacer()
            case .available(let v, _):
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.orange)
                Text("Version \(v) disponible").fontWeight(.medium)
                Spacer()
                Button("Mettre à jour") { up.install() }.emberProminent().tint(.orange)
            case .downloading(let f):
                ProgressView(value: f).frame(width: 90)
                Text("Téléchargement \(Int(f * 100)) %").foregroundStyle(.secondary).monospacedDigit(); Spacer()
            case .installing:
                ProgressView().controlSize(.small); Text("Installation, redémarrage…").foregroundStyle(.secondary); Spacer()
            case .failed(let m):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("Réessayer") { up.state = .idle; up.check() }
            }
        }.font(.callout)
    }
}

/// Shown in the popover only while an update is available or in progress.
struct UpdateBanner: View {
    @ObservedObject var up = Updater.shared
    var body: some View {
        switch up.state {
        case .available, .downloading, .installing: UpdateRow().padding(10).card(radius: 10)
        default: EmptyView()
        }
    }
}
