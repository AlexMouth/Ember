import AppKit
import SwiftUI

/// Self-update from GitHub Releases: checks the latest release, downloads the ZIP,
/// swaps the app bundle once Ember has quit, then relaunches it.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repo = "AlexMouth/Ember"

    enum State: Equatable {
        case idle, checking, upToDate
        case available(version: String, url: URL)
        case downloading(Double)  // 0...1
        case installing
        case failed(String)
    }

    @Published var state: State = .idle
    private var timer: Timer?

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }

    var hasUpdate: Bool { if case .available = state { return true } else { return false } }

    func startAutoCheck() {
        check(silent: true)
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in Updater.shared.check(silent: true) }
        }
    }

    nonisolated static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    func check(silent: Bool = false) {
        switch state { case .checking, .downloading, .installing: return; default: break }
        if !silent { state = .checking }
        Task {
            do {
                var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
                req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                req.timeoutInterval = 15
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200,
                      let j = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tag = j["tag_name"] as? String else {
                    throw NSError(domain: "Updater", code: 1, userInfo: [NSLocalizedDescriptionKey: "Impossible de lire la dernière version (dépôt privé ou hors ligne)."])
                }
                let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                let assets = j["assets"] as? [[String: Any]] ?? []
                let zip = assets.compactMap { $0["browser_download_url"] as? String }.first { $0.hasSuffix(".zip") }
                if Self.newer(v, than: current), let z = zip, let u = URL(string: z) {
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
        guard case .available(_, let url) = state else { return }
        let target = Bundle.main.bundleURL
        guard target.pathExtension == "app", !target.path.contains("/.build/") else {
            state = .failed("Ember ne tourne pas depuis une app installée. Installez-la dans /Applications pour activer la mise à jour.")
            return
        }
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            state = .failed("Dossier d'installation non modifiable : \(target.deletingLastPathComponent().path)")
            return
        }
        state = .downloading(0)
        Task {
            do {
                let progress = DownloadProgress { f in Task { @MainActor in
                    if case .downloading = Updater.shared.state { Updater.shared.state = .downloading(f) }
                } }
                let (tmp, resp) = try await URLSession.shared.download(from: url, delegate: progress)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("ember-update-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                let zip = work.appendingPathComponent("Ember.zip")
                try FileManager.default.moveItem(at: tmp, to: zip)
                let out = work.appendingPathComponent("out")
                try Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path])
                let newApp = out.appendingPathComponent("Ember.app")
                guard FileManager.default.fileExists(atPath: newApp.path) else { throw URLError(.cannotParseResponse) }
                try Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
                state = .installing
                let script = """
                while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
                rm -rf "$1" && ditto "$2" "$1" && xattr -cr "$1"
                open "$1"
                rm -rf "$3"
                """
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/sh")
                p.arguments = ["-c", script, "sh", target.path, newApp.path, work.path]
                try p.run()
                NSApp.terminate(nil)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private static func run(_ exe: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        p.standardError = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 { throw NSError(domain: "Updater", code: 3, userInfo: [NSLocalizedDescriptionKey: "\(exe) a échoué"]) }
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
