//
//  ax.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AppKit
import ApplicationServices

// Drives the verify build through the accessibility tree and real mouse/keyboard events.
// verify.sh builds it into ../.bin/ax and calls it; in a VM it runs over ssh.
// The process that runs it needs the Accessibility grant (and Screen Recording for screenshots).
// Target: the app whose name contains $VERIFY_APP (e.g. "verify-tool-prompt").
// Usage: ax dump [depth] [web] | find <text> | press <idOrText> | clickel <idOrText> | hover <idOrText> | click x y [cmd]
//        | type <text> | key <code> [cmd|shift|opt|ctrl]... | activate | frame | front | winrect
let args = CommandLine.arguments.dropFirst()
let cmd = args.first ?? "dump"
let rest = Array(args.dropFirst())

guard let target = ProcessInfo.processInfo.environment["VERIFY_APP"], !target.isEmpty else {
    print("Set VERIFY_APP to the app name, e.g. verify-<topic>"); exit(1)
}
guard let app = NSWorkspace.shared.runningApplications.first(where: { ($0.localizedName ?? "").contains(target) }) else {
    print("APP NOT RUNNING: \(target)"); exit(1)
}
let root = AXUIElementCreateApplication(app.processIdentifier)

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ name: String) -> String {
    guard let v = attr(e, name) else { return "" }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return ""
}
func frame(_ e: AXUIElement) -> CGRect {
    var p = CGPoint.zero, s = CGSize.zero
    if let pv = attr(e, kAXPositionAttribute) { AXValueGetValue(pv as! AXValue, .cgPoint, &p) }
    if let sv = attr(e, kAXSizeAttribute) { AXValueGetValue(sv as! AXValue, .cgSize, &s) }
    return CGRect(origin: p, size: s)
}
func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func describe(_ e: AXUIElement) -> String {
    let f = frame(e)
    var parts = [str(e, kAXRoleAttribute)]
    let sub = str(e, kAXSubroleAttribute); if !sub.isEmpty { parts.append("(\(sub))") }
    let id = str(e, "AXIdentifier"); if !id.isEmpty { parts.append("id=\(id)") }
    let t = str(e, kAXTitleAttribute); if !t.isEmpty { parts.append("title=\"\(t.prefix(120))\"") }
    let d = str(e, kAXDescriptionAttribute); if !d.isEmpty { parts.append("desc=\"\(d.prefix(120))\"") }
    let v = str(e, kAXValueAttribute); if !v.isEmpty { parts.append("value=\"\(v.prefix(200).replacingOccurrences(of: "\n", with: "⏎"))\"") }
    parts.append("@\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height))")
    return parts.joined(separator: " ")
}
func walk(_ e: AXUIElement, depth: Int, max: Int, visit: (AXUIElement, Int) -> Bool) {
    guard visit(e, depth), depth < max else { return }
    for c in children(e) { walk(c, depth: depth + 1, max: max, visit: visit) }
}
func matches(_ e: AXUIElement, _ q: String) -> Bool {
    [str(e, "AXIdentifier"), str(e, kAXTitleAttribute), str(e, kAXDescriptionAttribute), str(e, kAXValueAttribute)]
        .contains { $0 == q || $0.localizedCaseInsensitiveContains(q) }
}
func findFirst(_ q: String) -> AXUIElement? {
    var exact: AXUIElement?, loose: AXUIElement?
    walk(root, depth: 0, max: 60) { e, _ in
        if exact != nil { return false }
        if str(e, "AXIdentifier") == q { exact = e; return false }
        if loose == nil, matches(e, q) { loose = e }
        return true
    }
    return exact ?? loose
}
func mouseClick(_ p: CGPoint, flags: CGEventFlags = [], middle: Bool = false) {
    let src = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(80_000)
    let (downType, upType, button): (CGEventType, CGEventType, CGMouseButton) = middle
        ? (.otherMouseDown, .otherMouseUp, .center) : (.leftMouseDown, .leftMouseUp, .left)
    let down = CGEvent(mouseEventSource: src, mouseType: downType, mouseCursorPosition: p, mouseButton: button)
    down?.flags = flags; down?.post(tap: .cghidEventTap)
    usleep(60_000)
    let up = CGEvent(mouseEventSource: src, mouseType: upType, mouseCursorPosition: p, mouseButton: button)
    up?.flags = flags; up?.post(tap: .cghidEventTap)
}
func modifierFlags(_ words: [String]) -> CGEventFlags {
    var flags: CGEventFlags = []
    if words.contains("cmd") { flags.insert(.maskCommand) }
    if words.contains("shift") { flags.insert(.maskShift) }
    if words.contains("opt") { flags.insert(.maskAlternate) }
    if words.contains("ctrl") { flags.insert(.maskControl) }
    return flags
}

switch cmd {
case "activate":
    app.activate()
case "dump":
    let max = Int(rest.first ?? "") ?? 12
    let skipWeb = !rest.contains("web")
    walk(root, depth: 0, max: max) { e, d in
        print(String(repeating: "  ", count: d) + describe(e))
        let role = str(e, kAXRoleAttribute)
        return !(skipWeb && role == "AXWebArea") && role != "AXMenuBar"
    }
case "find":
    let q = rest.joined(separator: " ")
    walk(root, depth: 0, max: 60) { e, _ in
        if matches(e, q) { print(describe(e)) }
        return true
    }
case "press":
    let q = rest.joined(separator: " ")
    guard let e = findFirst(q) else { print("NOT FOUND: \(q)"); exit(2) }
    let r = AXUIElementPerformAction(e, kAXPressAction as CFString)
    print("press \(describe(e)) -> \(r.rawValue)")
case "clickel":
    let q = rest.joined(separator: " ")
    guard let e = findFirst(q) else { print("NOT FOUND: \(q)"); exit(2) }
    let f = frame(e)
    app.activate(); usleep(200_000)
    mouseClick(CGPoint(x: f.midX, y: f.midY))
    print("clicked \(describe(e))")
case "click":
    // click <x> <y> [cmd] [shift] [opt] [ctrl] [middle]
    app.activate(); usleep(200_000)
    let words = Array(rest.dropFirst(2))
    mouseClick(CGPoint(x: Double(rest[0])!, y: Double(rest[1])!), flags: modifierFlags(words), middle: words.contains("middle"))
    print("clicked \(rest[0]),\(rest[1]) \(words.joined(separator: " "))")
case "hover":
    // hover <idOrText>: moves the pointer to the element's center without clicking, for hover states.
    let q = rest.joined(separator: " ")
    guard let e = findFirst(q) else { print("NOT FOUND: \(q)"); exit(2) }
    let f = frame(e)
    app.activate(); usleep(200_000)
    let src = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: f.midX, y: f.midY), mouseButton: .left)?.post(tap: .cghidEventTap)
    print("hovered \(describe(e))")
case "type":
    let text = rest.joined(separator: " ")
    let src = CGEventSource(stateID: .hidSystemState)
    for ch in text.utf16 {
        var c = ch
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
        up?.post(tap: .cghidEventTap)
        usleep(15_000)
    }
    print("typed \(text.count) chars")
case "key":
    let code = CGKeyCode(rest[0])!
    var flags: CGEventFlags = []
    if rest.contains("cmd") { flags.insert(.maskCommand) }
    if rest.contains("shift") { flags.insert(.maskShift) }
    if rest.contains("opt") { flags.insert(.maskAlternate) }
    if rest.contains("ctrl") { flags.insert(.maskControl) }
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true); down?.flags = flags; down?.post(tap: .cghidEventTap)
    usleep(40_000)
    let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false); up?.flags = flags; up?.post(tap: .cghidEventTap)
    print("key \(code) \(flags.rawValue)")
case "front":
    // Whether the target app is frontmost: screenshots are only safe then.
    print(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier ? "yes" : "no")
case "winrect":
    // The first window's frame as x,y,w,h for screencapture -R.
    guard let w = (attr(root, kAXWindowsAttribute) as? [AXUIElement])?.first else { print("NO WINDOW"); exit(2) }
    let f = frame(w)
    print("\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))")
case "frame":
    for w in (attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { print(describe(w)) }
default:
    print("unknown \(cmd)")
}
