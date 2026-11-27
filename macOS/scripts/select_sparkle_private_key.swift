#!/usr/bin/swift

// swiftlint:disable file_header

// Writes the Sparkle private key whose public key matches SUPublicEDKey of the app in a DMG.
//
// Usage: select_sparkle_private_key.swift <path-to-dmg> <output-key-file>
//
// Candidate keys come from the environment variables listed in `candidateNames`, so they never appear
// in process arguments. Each one is a base64 key as exported by Sparkle's `generate_keys -x`:
// - 32 bytes: the seed (keys generated with Sparkle 2),
// - 96 bytes: the legacy format, a 64-byte private key followed by the 32-byte public key.

import CryptoKit
import Foundation

let candidateNames = ["SPARKLE_PRIVATE_KEY", "SPARKLE_PRIVATE_KEY_V2"]

func fail(_ message: String) -> Never {
    print("::error::\(message)")
    exit(1)
}

func publicKey(ofPrivateKey base64Key: String) -> String? {
    guard let secret = Data(base64Encoded: base64Key) else {
        return nil
    }
    switch secret.count {
    case 32:
        return try? Curve25519.Signing.PrivateKey(rawRepresentation: secret).publicKey.rawRepresentation.base64EncodedString()
    case 96:
        return secret.suffix(32).base64EncodedString()
    default:
        return nil
    }
}

@discardableResult
func run(_ executable: String, _ arguments: [String]) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return false
    }
    process.waitUntilExit()
    return process.terminationStatus == 0
}

func appPublicKey(inDMGAt dmgPath: String) -> Result<String, Error> {
    struct DMGError: Error, CustomStringConvertible {
        let description: String
    }

    let mountPoint = FileManager.default.temporaryDirectory.appendingPathComponent("sparkle-key-dmg-\(UUID().uuidString)")
    guard run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mountPoint.path, dmgPath]) else {
        return .failure(DMGError(description: "Could not mount \(dmgPath)"))
    }
    defer {
        run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"])
    }

    let apps = ((try? FileManager.default.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.pathExtension == "app" }
    guard apps.count == 1 else {
        return .failure(DMGError(description: "Expected one app at the top level of \(dmgPath), found \(apps.count)"))
    }

    let infoPlistURL = apps[0].appendingPathComponent("Contents/Info.plist")
    guard let data = try? Data(contentsOf: infoPlistURL),
          let infoPlist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let key = infoPlist["SUPublicEDKey"] as? String else {
        return .failure(DMGError(description: "SUPublicEDKey is missing from \(apps[0].lastPathComponent) in \(dmgPath)"))
    }
    return .success(key)
}

guard CommandLine.arguments.count == 3 else {
    fail("Usage: \(CommandLine.arguments[0]) <path-to-dmg> <output-key-file>")
}
let dmgPath = CommandLine.arguments[1]
let outputPath = CommandLine.arguments[2]

let appKey: String
switch appPublicKey(inDMGAt: dmgPath) {
case .success(let key):
    appKey = key
case .failure(let error):
    fail("\(error)")
}

let environment = ProcessInfo.processInfo.environment
let candidates = candidateNames.map { name in
    let key = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return (name: name, key: key, publicKey: publicKey(ofPrivateKey: key))
}

guard let match = candidates.first(where: { $0.publicKey == appKey }) else {
    let summary = candidates.map { "\($0.name): \($0.publicKey ?? "missing or invalid")" }.joined(separator: ", ")
    fail("No Sparkle private key matches SUPublicEDKey \(appKey) of the app in \(dmgPath). Public keys of the candidates: \(summary)")
}

try? FileManager.default.removeItem(atPath: outputPath)
guard FileManager.default.createFile(atPath: outputPath, contents: Data(match.key.utf8), attributes: [.posixPermissions: 0o600]) else {
    fail("Could not write the private key to \(outputPath)")
}
print("Using \(match.name) (public key \(appKey)) for \(dmgPath)")
