// Ed25519 signing for Ember updates. The private key never enters the repository.
//
//   swift scripts/sign_update.swift genkey        creates the key (once) and prints the public key
//   swift scripts/sign_update.swift pubkey        prints the public key to paste in Updater.swift
//   swift scripts/sign_update.swift sign <file>   writes <file>.sig (base64 signature of the file bytes)
//   swift scripts/sign_update.swift verify <file> checks <file>.sig against the key
//
// Key location: $EMBER_SIGNING_KEY, else ~/.config/ember/update-signing.key (base64, mode 0600).
// Back it up somewhere safe: without it, installed copies of Ember can no longer self-update.
import CryptoKit
import Foundation

let keyPath = ProcessInfo.processInfo.environment["EMBER_SIGNING_KEY"]
    ?? NSString(string: "~/.config/ember/update-signing.key").expandingTildeInPath

func fail(_ m: String) -> Never { FileHandle.standardError.write(Data((m + "\n").utf8)); exit(1) }

func loadKey() -> Curve25519.Signing.PrivateKey {
    guard let s = try? String(contentsOfFile: keyPath, encoding: .utf8),
          let raw = Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines)),
          let k = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else { fail("Clé introuvable ou illisible : \(keyPath) (lancez d'abord `genkey`)") }
    return k
}

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "genkey":
    if FileManager.default.fileExists(atPath: keyPath) { fail("Une clé existe déjà : \(keyPath). Supprimez-la vous-même pour en créer une autre.") }
    let k = Curve25519.Signing.PrivateKey()
    let dir = (keyPath as NSString).deletingLastPathComponent
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    guard FileManager.default.createFile(atPath: keyPath, contents: Data(k.rawRepresentation.base64EncodedString().utf8),
                                         attributes: [.posixPermissions: 0o600]) else { fail("Écriture impossible : \(keyPath)") }
    print(k.publicKey.rawRepresentation.base64EncodedString())
case "pubkey":
    print(loadKey().publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard let f = args.dropFirst().first, let data = FileManager.default.contents(atPath: f) else { fail("Fichier à signer introuvable") }
    let sig = try loadKey().signature(for: data)
    try Data(sig.base64EncodedString().utf8).write(to: URL(fileURLWithPath: f + ".sig"))
    guard loadKey().publicKey.isValidSignature(sig, for: data) else { fail("Signature invalide") }
    print("Signé : \(f).sig")
case "verify":
    guard let f = args.dropFirst().first, let data = FileManager.default.contents(atPath: f),
          let s = try? String(contentsOfFile: f + ".sig", encoding: .utf8),
          let sig = Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines)) else { fail("Fichier ou .sig introuvable") }
    guard loadKey().publicKey.isValidSignature(sig, for: data) else { fail("Signature INVALIDE") }
    print("Signature valide")
default:
    fail("Usage : swift scripts/sign_update.swift genkey | pubkey | sign <fichier> | verify <fichier>")
}
