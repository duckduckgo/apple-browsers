#!/usr/bin/env swift
//
// ddg-db-decrypt.swift
//
// Read DECRYPTED contents of a DuckDuckGo macOS Core Data store (Database.sqlite).
//
// Sensitive columns (named *ENCRYPTED) are stored as:
//     ChaChaPoly.seal( NSKeyedArchiver(value) ).combined
// i.e. CryptoKit ChaCha20-Poly1305, combined = 12B nonce ‖ ciphertext ‖ 16B tag,
// wrapping an NSKeyedArchiver(requiringSecureCoding) archive of an NSURL / NSString /
// NSImage. This tool reverses exactly that (CryptoKit + NSKeyedUnarchiver), so it
// matches the app byte-for-byte, including favicon images.
//
// The 32-byte symmetric key lives in the login keychain and is shared by all
// non-App-Store builds (prod + debug): service "DuckDuckGo Privacy Browser Encryption
// Key v2", account "com.duckduckgo.macos.browser". The key is NEVER hard-coded here.
//
// KEY SOURCES (first match wins):
//   1. --key <base64>
//   2. $DDG_DB_KEY
//   3. keychain via `/usr/bin/security` (may show a one-time auth prompt — click
//      "Always Allow" to make future runs non-interactive)
//
// USAGE:
//   ddg-db-decrypt.swift [global opts] <command> [args]
//
// COMMANDS:
//   tables                       List Z* entity tables (excluding Z_*) with row counts
//   dump <ZTABLE>                Print rows as TSV; *ENCRYPTED columns are decrypted
//                                (URL/String shown inline; image columns show byte size,
//                                 plus WxH pixels when --pixels is given)
//   export-favicons <OUTDIR>     Decrypt favicon images to PNGs in OUTDIR + manifest.tsv
//   key-check                    Confirm the key decrypts a sample value
//
// GLOBAL OPTIONS:
//   --db PATH        SQLite store (default: the .debug container's Database.sqlite)
//   --key BASE64     encryption key (base64); overrides env/keychain
//   --service NAME   keychain service (default: DuckDuckGo Privacy Browser Encryption Key v2)
//   --account NAME   keychain account (default: com.duckduckgo.macos.browser)
//   --limit N        max rows for dump/export-favicons (default: all)
//   --pixels         dump: also decode image columns to report pixel WxH (slower)
//
// EXAMPLES:
//   ddg-db-decrypt.swift tables
//   ddg-db-decrypt.swift dump ZFAVICONMANAGEDOBJECT --limit 20 --pixels
//   ddg-db-decrypt.swift dump ZHISTORYENTRYMANAGEDOBJECT --limit 50
//   ddg-db-decrypt.swift export-favicons ~/Desktop/favicons
//   DDG_DB_KEY=$(security find-generic-password -w -s "DuckDuckGo Privacy Browser Encryption Key v2" -a com.duckduckgo.macos.browser) ddg-db-decrypt.swift key-check
//
import Foundation
import CryptoKit
import AppKit
import SQLite3

let SERVICE_DEFAULT = "DuckDuckGo Privacy Browser Encryption Key v2"
let ACCOUNT_DEFAULT = "com.duckduckgo.macos.browser"
let DB_DEFAULT = ("~/Library/Containers/com.duckduckgo.macos.browser.debug/Data/Library/Application Support/Database.sqlite" as NSString).expandingTildeInPath

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + msg + "\n").utf8))
    exit(1)
}

// ---------------- argument parsing ----------------
var args = Array(CommandLine.arguments.dropFirst())
func popValue(_ names: [String]) -> String? {
    for name in names {
        if let i = args.firstIndex(of: name), i + 1 < args.count {
            let v = args[i + 1]; args.removeSubrange(i...(i + 1)); return v
        }
    }
    return nil
}
func popBool(_ names: [String]) -> Bool {
    for name in names { if let i = args.firstIndex(of: name) { args.remove(at: i); return true } }
    return false
}

let wantHelp = popBool(["-h", "--help"])
let dbPath = popValue(["--db"]) ?? DB_DEFAULT
let keyArg = popValue(["--key"])
let service = popValue(["--service"]) ?? SERVICE_DEFAULT
let account = popValue(["--account"]) ?? ACCOUNT_DEFAULT
let limit = Int(popValue(["--limit"]) ?? "") ?? 0   // 0 == all
let withPixels = popBool(["--pixels"])

let HELP = """
ddg-db-decrypt.swift — read decrypted DuckDuckGo Core Data contents (ChaChaPoly + NSKeyedArchiver)

USAGE:  ddg-db-decrypt.swift [global opts] <command> [args]

COMMANDS:
  tables                     List Z* entity tables (excl. Z_*) with row counts
  dump <ZTABLE>              Decrypt & print rows as TSV (*ENCRYPTED cols decrypted)
  export-favicons <OUTDIR>   Decrypt favicon images to PNGs + manifest.tsv
  key-check                  Verify the key can decrypt a sample value

GLOBAL OPTIONS:
  --db PATH       SQLite store (default: debug container Database.sqlite)
  --key BASE64    encryption key (base64); else $DDG_DB_KEY; else keychain via `security`
  --service NAME  keychain service (default: \(SERVICE_DEFAULT))
  --account NAME  keychain account (default: \(ACCOUNT_DEFAULT))
  --limit N       max rows for dump/export (default: all)
  --pixels        dump: also decode image columns to report pixel WxH (slower)

KEY SOURCES (in order):  --key  >  $DDG_DB_KEY  >  keychain (may prompt; click Always Allow)
"""

if wantHelp { print(HELP); exit(0) }
guard let command = args.first else { print(HELP); exit(2) }
args.removeFirst()

// ---------------- key ----------------
func keychainKeyBase64() -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = ["find-generic-password", "-w", "-s", service, "-a", account]
    let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
    do { try p.run() } catch { return nil }
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { return nil }
    let d = out.fileHandleForReading.readDataToEndOfFile()
    return String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

func loadKey() -> SymmetricKey {
    let b64 = keyArg ?? ProcessInfo.processInfo.environment["DDG_DB_KEY"] ?? keychainKeyBase64()
    guard let b64 = b64, !b64.isEmpty else {
        die("no key available — pass --key, set $DDG_DB_KEY, or allow the keychain read " +
            "(service \"\(service)\", account \"\(account)\").")
    }
    guard let raw = Data(base64Encoded: b64) else { die("key is not valid base64") }
    guard raw.count == 32 else { die("expected a 32-byte key, got \(raw.count) bytes") }
    return SymmetricKey(data: raw)
}

// ---------------- crypto / unarchive ----------------
func decrypt(_ blob: Data, _ key: SymmetricKey) -> Data? {
    guard let box = try? ChaChaPoly.SealedBox(combined: blob) else { return nil }
    return try? ChaChaPoly.open(box, using: key)
}
func asURL(_ d: Data) -> String? {
    (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSURL.self, from: d)).flatMap { ($0 as URL).absoluteString }
}
func asString(_ d: Data) -> String? {
    (try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSString.self, from: d)) as String?
}
func asImage(_ d: Data) -> NSImage? {
    try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSImage.self, from: d)
}
func pixelSize(_ img: NSImage) -> (Int, Int) {
    var w = 0, h = 0
    for r in img.representations { w = max(w, r.pixelsWide); h = max(h, r.pixelsHigh) }
    if w == 0 { w = Int(img.size.width); h = Int(img.size.height) }
    return (w, h)
}
func pngData(_ img: NSImage) -> Data? {
    let bitmaps = img.representations.compactMap { $0 as? NSBitmapImageRep }
    if let best = bitmaps.max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }) {
        return best.representation(using: .png, properties: [:])
    }
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

let isoFmt = ISO8601DateFormatter()
func coreDataDate(_ secondsSince2001: Double) -> String {
    isoFmt.string(from: Date(timeIntervalSinceReferenceDate: secondsSince2001))
}
func uuidFromBlob(_ d: Data) -> String? {
    guard d.count == 16 else { return nil }
    let b = [UInt8](d)
    let u: uuid_t = (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                     b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
    return UUID(uuid: u).uuidString
}

// ---------------- sqlite (read-only) ----------------
enum Cell { case null, int(Int64), real(Double), text(String), blob(Data) }

func openDB() -> OpaquePointer {
    guard FileManager.default.fileExists(atPath: dbPath) else { die("DB not found: \(dbPath)") }
    var db: OpaquePointer?
    guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = db else {
        die("cannot open DB read-only: \(dbPath)")
    }
    return db
}
func query(_ db: OpaquePointer, _ sql: String) -> (cols: [String], rows: [[Cell]]) {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        die("SQL error: \(String(cString: sqlite3_errmsg(db)))")
    }
    defer { sqlite3_finalize(stmt) }
    let n = sqlite3_column_count(stmt)
    var cols = [String]()
    for i in 0..<n { cols.append(String(cString: sqlite3_column_name(stmt, i))) }
    var rows = [[Cell]]()
    while sqlite3_step(stmt) == SQLITE_ROW {
        var row = [Cell]()
        for i in 0..<n {
            switch sqlite3_column_type(stmt, i) {
            case SQLITE_NULL: row.append(.null)
            case SQLITE_INTEGER: row.append(.int(sqlite3_column_int64(stmt, i)))
            case SQLITE_FLOAT: row.append(.real(sqlite3_column_double(stmt, i)))
            case SQLITE_TEXT: row.append(.text(String(cString: sqlite3_column_text(stmt, i))))
            case SQLITE_BLOB:
                if let p = sqlite3_column_blob(stmt, i) {
                    row.append(.blob(Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, i)))))
                } else { row.append(.blob(Data())) }
            default: row.append(.null)
            }
        }
        rows.append(row)
    }
    return (cols, rows)
}
func limitClause() -> String { limit > 0 ? " LIMIT \(limit)" : "" }

// ---------------- formatting ----------------
func format(col: String, cell: Cell, key: SymmetricKey) -> String {
    let up = col.uppercased()
    switch cell {
    case .null: return ""
    case .int(let v): return String(v)
    case .real(let v): return up.contains("DATE") ? coreDataDate(v) : String(v)
    case .text(let s): return s
    case .blob(let d):
        if up.hasSuffix("ENCRYPTED") {
            if up.contains("IMAGE") {
                var s = "<image \(d.count)B"
                if withPixels, let plain = decrypt(d, key), let img = asImage(plain) {
                    let (w, h) = pixelSize(img); s += " \(w)x\(h)px"
                }
                return s + ">"
            }
            guard let plain = decrypt(d, key) else { return "<decrypt-failed \(d.count)B>" }
            return asURL(plain) ?? asString(plain) ?? "<\(plain.count)B decrypted>"
        }
        if up == "ZIDENTIFIER", let u = uuidFromBlob(d) { return u }
        return "<\(d.count)B blob>"
    }
}

// ---------------- commands ----------------
func cmdTables() {
    let db = openDB()
    let t = query(db, "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'Z%' AND name NOT LIKE 'Z\\_%' ESCAPE '\\' ORDER BY name;")
    for r in t.rows {
        guard case let .text(name) = r[0] else { continue }
        let c = query(db, "SELECT count(*) FROM \"\(name)\";")
        var count: Int64 = 0
        if case let .int(v) = c.rows.first?.first ?? .int(0) { count = v }
        print("\(name)\t\(count)")
    }
}

func cmdDump() {
    guard let table = args.first else { die("dump needs a table name, e.g. ZFAVICONMANAGEDOBJECT") }
    let key = loadKey()
    let db = openDB()
    let res = query(db, "SELECT * FROM \"\(table)\"\(limitClause());")
    print(res.cols.joined(separator: "\t"))
    for row in res.rows {
        var out = [String]()
        for (i, cell) in row.enumerated() {
            out.append(format(col: res.cols[i], cell: cell, key: key).replacingOccurrences(of: "\t", with: " "))
        }
        print(out.joined(separator: "\t"))
    }
}

func cmdExportFavicons() {
    guard let dir = args.first else { die("export-favicons needs an output directory") }
    let key = loadKey()
    let outDir = (dir as NSString).expandingTildeInPath
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    let db = openDB()
    let res = query(db, "SELECT ZIDENTIFIER, ZURLENCRYPTED, ZIMAGEENCRYPTED FROM ZFAVICONMANAGEDOBJECT\(limitClause());")
    var manifest = "file\tfaviconURL\tencryptedBytes\tpixels\n"
    var ok = 0, fail = 0, idx = 0
    for row in res.rows {
        idx += 1
        var id = "row\(idx)"
        if case let .blob(d) = row[0], let u = uuidFromBlob(d) { id = u }
        else if case let .text(s) = row[0] { id = s }
        var faviconURL = ""
        if case let .blob(d) = row[1], let plain = decrypt(d, key), let u = asURL(plain) { faviconURL = u }
        guard case let .blob(imgBlob) = row[2], !imgBlob.isEmpty,
              let plain = decrypt(imgBlob, key), let img = asImage(plain), let png = pngData(img) else {
            fail += 1; continue
        }
        let (w, h) = pixelSize(img)
        let file = "\(id).png"
        do {
            try png.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(file))
            manifest += "\(file)\t\(faviconURL)\t\(imgBlob.count)\t\(w)x\(h)\n"
            ok += 1
        } catch { fail += 1 }
    }
    try? manifest.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("manifest.tsv"), atomically: true, encoding: .utf8)
    print("exported \(ok) favicon image(s) to \(outDir) (\(fail) skipped). manifest.tsv written.")
}

func cmdKeyCheck() {
    let key = loadKey()
    let db = openDB()
    let res = query(db, "SELECT ZURLENCRYPTED FROM ZFAVICONMANAGEDOBJECT WHERE ZURLENCRYPTED IS NOT NULL LIMIT 1;")
    guard case let .blob(d)? = res.rows.first?.first else { die("no sample row found in ZFAVICONMANAGEDOBJECT") }
    guard let plain = decrypt(d, key), let url = asURL(plain) else {
        die("key did NOT decrypt the sample value — wrong key or wrong DB.")
    }
    print("OK — key decrypts. Sample favicon URL: \(url)")
}

switch command.lowercased() {
case "tables":           cmdTables()
case "dump":             cmdDump()
case "export-favicons":  cmdExportFavicons()
case "key-check":        cmdKeyCheck()
default:                 die("unknown command '\(command)'. Run with --help.")
}
