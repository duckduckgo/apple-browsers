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
// Usage: ax dump [depth] [web] | find <text> | findmain <text> | press <idOrText> [nth=<n>]
//        | clickel <idOrText> [nth=<n>] | hover <idOrText> [nth=<n>] | click x y [cmd]
//        | type <text> | key <code> [cmd|shift|opt|ctrl]... | activate | frame | front | winrect | setwin x y w h
//        | grants | appearance [light|dark]
// Refusals exit nonzero before anything is done: APP NOT RUNNING, NOT FRONTMOST, NOT FOUND, AMBIGUOUS, DISABLED, OFF WINDOW,
// NOT FOCUSED. Each action's last line is changed=yes|no: whether the accessibility tree changed after it.
let args = CommandLine.arguments.dropFirst()
let cmd = args.first ?? "dump"
let rest = Array(args.dropFirst())

// grants: whether this process holds Accessibility and Screen Recording. Reads only: never prompts, needs no app.
if cmd == "grants" {
    print("accessibility=\(AXIsProcessTrusted()) screen-recording=\(CGPreflightScreenCaptureAccess())"); exit(0)
}
// appearance [light|dark]: the system-wide appearance, set if given, then read back. Needs no app. Only verify.sh calls
// it, and only in a VM. SkyLight's own switch, as System Settings uses it: osascript to System Events would raise an
// Automation prompt in an ssh session.
if cmd == "appearance" {
    let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    guard let set = dlsym(sky, "SLSSetAppearanceThemeLegacy"), let get = dlsym(sky, "SLSGetAppearanceThemeLegacy") else {
        print("NO APPEARANCE SWITCH: SkyLight's SLSSetAppearanceThemeLegacy is missing on this macOS"); exit(2)
    }
    if let want = rest.first {
        guard want == "light" || want == "dark" else { print("appearance: light or dark"); exit(64) }
        unsafeBitCast(set, to: (@convention(c) (Bool) -> Void).self)(want == "dark")
        usleep(500_000)
    }
    print(unsafeBitCast(get, to: (@convention(c) () -> Bool).self)() ? "dark" : "light"); exit(0)
}
guard let target = ProcessInfo.processInfo.environment["VERIFY_APP"], !target.isEmpty else {
    print("Set VERIFY_APP to the app name, e.g. verify-<topic>"); exit(1)
}
// By the bundle's file name, not localizedName: under another language the app's InfoPlist.strings name it "DuckDuckGo".
guard let app = NSWorkspace.shared.runningApplications.first(where: { ($0.bundleURL?.lastPathComponent ?? "").contains(target) }) else {
    print("APP NOT RUNNING: \(target)"); exit(1)
}
let root = AXUIElementCreateApplication(app.processIdentifier)
// Nothing is read or acted on while another app is in front: a popover or menu closes when the app loses the front, so
// a "gone" read there could pass on the wrong state. Only `front` (which says so) and `activate` run then.
if cmd != "front" && cmd != "activate" && NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
    print("NOT FRONTMOST: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "nothing") is in front; nothing read or done")
    exit(2)
}

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
// The one element a press/clickel/hover targets. Matches are tiered: exact AX id, then exact title/desc/value, then
// contains; the first non-empty tier wins. More than one match there is refused (exit 2, listing them) unless the
// query ends with nth=<n> (0-based, in tree order): it never guesses.
func findOne(_ words: [String]) -> AXUIElement {
    var words = words, nth: Int?
    if let last = words.last, last.hasPrefix("nth="), let n = Int(last.dropFirst(4)) { nth = n; words.removeLast() }
    let q = words.joined(separator: " ")
    var tiers: [[AXUIElement]] = [[], [], []]
    walk(root, depth: 0, max: 60) { e, _ in
        let texts = [str(e, kAXTitleAttribute), str(e, kAXDescriptionAttribute), str(e, kAXValueAttribute)]
        if str(e, "AXIdentifier") == q { tiers[0].append(e) } else if texts.contains(q) { tiers[1].append(e) } else if matches(e, q) { tiers[2].append(e) }
        return true
    }
    let found = tiers.first { !$0.isEmpty } ?? []
    if found.isEmpty { print("NOT FOUND: \(q)"); exit(2) }
    if let nth {
        guard nth >= 0, nth < found.count else { print("NOT FOUND: \(q) nth=\(nth) (\(found.count) matches)"); exit(2) }
        return found[nth]
    }
    if found.count > 1 {
        print("AMBIGUOUS: \(found.count) elements match \(q); add nth=<n>:")
        for (i, e) in found.enumerated() { print("  nth=\(i) \(describe(e))") }
        exit(2)
    }
    return found[0]
}
// A target the user couldn't act on is refused before anything happens: disabled, or with its center outside its
// window (scrolled away, collapsed, hidden). Menu items open outside every window, so only their enabled state counts.
func actionable(_ e: AXUIElement) -> AXUIElement {
    if (attr(e, kAXEnabledAttribute) as? Bool) == false { print("DISABLED: \(describe(e))"); exit(2) }
    let role = str(e, kAXRoleAttribute)
    if role == kAXMenuItemRole || role == kAXMenuBarItemRole { return e }
    let f = frame(e), center = CGPoint(x: f.midX, y: f.midY)
    let windows = attr(e, kAXWindowAttribute).map { [$0 as! AXUIElement] } ?? (attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    guard f.width > 0, f.height > 0, windows.contains(where: { frame($0).contains(center) }) else {
        print("OFF WINDOW: its center is outside its window (scroll it into view first): \(describe(e))"); exit(2)
    }
    return e
}
// What the app shows through AX, as one number: each element's role, id, texts, value, enabled, focused and selected
// state and frame (scrolling moves frames), and which element has keyboard focus. Equal before and after an action:
// the action changed nothing the tree shows. One IPC per element; at most 20000 elements.
let digestAttributes = [kAXRoleAttribute, "AXIdentifier", kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute,
                        kAXEnabledAttribute, kAXFocusedAttribute, kAXSelectedAttribute, kAXPositionAttribute,
                        kAXSizeAttribute, kAXChildrenAttribute] as CFArray
func digest() -> Int {
    var h = Hasher(), seen = 0
    func visit(_ e: AXUIElement, _ depth: Int) {
        var values: CFArray?
        seen += 1
        guard seen < 20000, AXUIElementCopyMultipleAttributeValues(e, digestAttributes, [], &values) == .success,
              let list = values as? [AnyObject] else { return }
        for v in list {
            if let s = v as? String {
                h.combine(s)
            } else if let n = v as? NSNumber {
                h.combine(n.doubleValue)
            } else if CFGetTypeID(v) == AXValueGetTypeID() {
                var p = CGPoint.zero, z = CGSize.zero
                if AXValueGetValue(v as! AXValue, .cgPoint, &p) { h.combine(p.x); h.combine(p.y) }
                if AXValueGetValue(v as! AXValue, .cgSize, &z) { h.combine(z.width); h.combine(z.height) }
            } else if let kids = v as? [AXUIElement], depth < 60 {
                h.combine(kids.count); kids.forEach { visit($0, depth + 1) }
            } else {
                h.combine(0)
            }
        }
    }
    visit(root, 0)
    if let f = attr(root, kAXFocusedUIElementAttribute) { h.combine(describe(f as! AXUIElement)) }
    return h.finalize()
}
// Run an action, then print whether the tree changed within 1.5 s (`changed=yes|no`, the last line). harness.py lists
// actions that changed nothing under Warnings: there the proof's own reads must show the effect.
func acting(_ action: () -> Void) {
    let before = digest()
    action()
    let end = Date().addingTimeInterval(1.5)
    var changed = false
    repeat { usleep(100_000); changed = digest() != before } while !changed && Date() < end
    print("changed=\(changed ? "yes" : "no")")
}
// Text goes only to a focused element that takes it: a frontmost window can have no keyboard focus (seen in a VM).
func refuseUnfocusedTyping() {
    guard let f = attr(root, kAXFocusedUIElementAttribute) else { print("NOT FOCUSED: no element has keyboard focus; click the field first"); exit(2) }
    let e = f as! AXUIElement
    var settable = DarwinBoolean(false)
    AXUIElementIsAttributeSettable(e, kAXValueAttribute as CFString, &settable)
    let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"]
    guard settable.boolValue || textRoles.contains(str(e, kAXRoleAttribute)) else {
        print("NOT FOCUSED: the focused element takes no text; click the field first: \(describe(e))"); exit(2)
    }
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
case "findmain":
    // find, in the main (front) window only: other windows' tabs and toolbars don't count.
    guard let w = attr(root, kAXMainWindowAttribute) else { print("NO MAIN WINDOW"); exit(2) }
    let q = rest.joined(separator: " ")
    walk(w as! AXUIElement, depth: 0, max: 60) { e, _ in
        if matches(e, q) { print(describe(e)) }
        return true
    }
case "press":
    let e = actionable(findOne(rest))
    acting {
        let r = AXUIElementPerformAction(e, kAXPressAction as CFString)
        print("press \(describe(e)) -> \(r.rawValue)")
    }
case "clickel":
    let e = actionable(findOne(rest))
    let f = frame(e)
    acting {
        app.activate(); usleep(200_000)
        mouseClick(CGPoint(x: f.midX, y: f.midY))
        print("clicked \(describe(e))")
    }
case "click":
    // click <x> <y> [cmd] [shift] [opt] [ctrl] [middle]
    let words = Array(rest.dropFirst(2))
    acting {
        app.activate(); usleep(200_000)
        mouseClick(CGPoint(x: Double(rest[0])!, y: Double(rest[1])!), flags: modifierFlags(words), middle: words.contains("middle"))
        print("clicked \(rest[0]),\(rest[1]) \(words.joined(separator: " "))")
    }
case "hover":
    // hover <idOrText>: moves the pointer to the element's center without clicking, for hover states.
    let e = actionable(findOne(rest))
    let f = frame(e)
    acting {
        app.activate(); usleep(200_000)
        let src = CGEventSource(stateID: .hidSystemState)
        CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: f.midX, y: f.midY), mouseButton: .left)?.post(tap: .cghidEventTap)
        print("hovered \(describe(e))")
    }
case "type":
    let text = rest.joined(separator: " ")
    refuseUnfocusedTyping()
    let src = CGEventSource(stateID: .hidSystemState)
    acting { for ch in text.utf16 {
        var c = ch
        // No modifiers, explicitly: after `key cmd+t` the source's state still holds Cmd, and text typed with it is dropped.
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
        down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
        down?.flags = []; down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
        up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
        up?.flags = []; up?.post(tap: .cghidEventTap)
        usleep(15_000)
    }
    print("typed \(text.count) chars") }
case "key":
    let code = CGKeyCode(rest[0])!
    var flags: CGEventFlags = []
    if rest.contains("cmd") { flags.insert(.maskCommand) }
    if rest.contains("shift") { flags.insert(.maskShift) }
    if rest.contains("opt") { flags.insert(.maskAlternate) }
    if rest.contains("ctrl") { flags.insert(.maskControl) }
    let src = CGEventSource(stateID: .hidSystemState)
    acting {
        let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true); down?.flags = flags; down?.post(tap: .cghidEventTap)
        usleep(40_000)
        let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false); up?.flags = flags; up?.post(tap: .cghidEventTap)
        print("key \(code) \(flags.rawValue)")
    }
case "front":
    // Whether the target app is frontmost: screenshots are only safe then.
    print(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier ? "yes" : "no")
case "winrect":
    // The first window's frame as x,y,w,h for screencapture -R.
    guard let w = (attr(root, kAXWindowsAttribute) as? [AXUIElement])?.first else { print("NO WINDOW"); exit(2) }
    let f = frame(w)
    print("\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))")
case "setwin":
    // Move and resize the first window to x y w h (top-left origin, points); winrect reads it back.
    let n = rest.compactMap { Double($0) }
    guard n.count == 4, let w = (attr(root, kAXWindowsAttribute) as? [AXUIElement])?.first else { print("setwin x y w h: NO WINDOW or bad args"); exit(2) }
    var p = CGPoint(x: n[0], y: n[1]), s = CGSize(width: n[2], height: n[3])
    // Size, move, size again: a move can't take a window past the screen's edge at its old size, nor a resize at its old origin.
    let size = { AXUIElementSetAttributeValue(w, kAXSizeAttribute as CFString, AXValueCreate(.cgSize, &s)!) }
    _ = size()
    let moved = AXUIElementSetAttributeValue(w, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
    let sized = size()
    guard moved == .success, sized == .success else { print("setwin: AX refused (move \(moved.rawValue), size \(sized.rawValue))"); exit(2) }
case "frame":
    for w in (attr(root, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { print(describe(w)) }
default:
    print("unknown \(cmd)")
}
