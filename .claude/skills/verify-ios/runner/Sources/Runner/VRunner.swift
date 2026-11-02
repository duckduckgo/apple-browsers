//
//  VRunner.swift
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

import XCTest
import Network

/// Long-lived XCUITest runner for the verify-ios skill. One test method serves JSON commands on
/// 127.0.0.1:$VRUNNER_PORT and runs each on the main thread. Every action resolves its locator fresh, refuses
/// ambiguous, missing, disabled and non-hittable targets, and returns an `after` observation so false successes show.
final class VRunner: XCTestCase {

    struct Job {
        let body: [String: Any]
        let done: ([String: Any]) -> Void
    }

    private var queue: [Job] = []
    private let lock = NSLock()
    private var stop = false
    private var app: XCUIApplication!
    private var issues: [String] = []
    /// Per-worktree secret from the driver. Every command must carry it, so another worktree's driver (or any other
    /// local process) that reaches this port is refused instead of driving the wrong simulator.
    private var token = ""

    override func setUp() {
        continueAfterFailure = true
    }

    /// XCUITest reports failed element lookups (an element that vanished between check and tap) as test issues,
    /// which would end the long-lived test. Keep them as command errors instead.
    override func record(_ issue: XCTIssue) {
        issues.append(issue.compactDescription)
    }

    func testServe() throws {
        let env = ProcessInfo.processInfo.environment
        let port = UInt16(env["VRUNNER_PORT"] ?? "") ?? 8820
        token = env["VRUNNER_TOKEN"] ?? ""
        app = XCUIApplication(bundleIdentifier: env["VRUNNER_BUNDLE"] ?? "com.duckduckgo.mobile.ios")
        if env["VRUNNER_WAIT_ANIMATIONS"] != "1" { Self.skipAnimationIdle() }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: .global())
        while !stop {
            lock.lock()
            let job = queue.isEmpty ? nil : queue.removeFirst()
            lock.unlock()
            if let job { job.done(handle(job.body)) } else { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        }
        listener.cancel()
    }

    /// PRIVATE API (same approach as WebDriverAgent): keep XCTest's event-loop idle wait but skip its animation
    /// idle wait, which never completes while DDG's context menus animate (a 60 s stall per action).
    private static var swizzled = false
    private static func skipAnimationIdle() {
        guard !swizzled, let cls = NSClassFromString("XCUIApplicationProcess") else { return }
        swizzled = true
        let s1 = NSSelectorFromString("waitForQuiescenceIncludingAnimationsIdle:")
        if let method = class_getInstanceMethod(cls, s1) {
            typealias Fn = @convention(c) (AnyObject, Selector, Bool) -> Void
            let orig = unsafeBitCast(method_getImplementation(method), to: Fn.self)
            let block: @convention(block) (AnyObject, Bool) -> Void = { obj, _ in orig(obj, s1, false) }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
        let s2 = NSSelectorFromString("waitForQuiescenceIncludingAnimationsIdle:isPreEvent:")
        if let method = class_getInstanceMethod(cls, s2) {
            typealias Fn = @convention(c) (AnyObject, Selector, Bool, Bool) -> Void
            let orig = unsafeBitCast(method_getImplementation(method), to: Fn.self)
            let block: @convention(block) (AnyObject, Bool, Bool) -> Void = { obj, _, pre in orig(obj, s2, false, pre) }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
    }

    // MARK: http

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .global())
        read(connection, Data())
    }

    private func read(_ connection: NWConnection, _ acc: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, eof, _ in
            guard let self else { return }
            var buf = acc
            if let data { buf.append(data) }
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(bytes: buf[..<range.lowerBound], encoding: .utf8) ?? ""
                let len = head.split(separator: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                let body = buf[range.upperBound...]
                if body.count >= len {
                    let json = (try? JSONSerialization.jsonObject(with: Data(body.prefix(len)))) as? [String: Any] ?? [:]
                    self.lock.lock()
                    self.queue.append(Job(body: json) { out in
                        let data = (try? JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])) ?? Data()
                        let resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
                        connection.send(content: Data(resp.utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
                    })
                    self.lock.unlock()
                    return
                }
            }
            if eof { connection.cancel() } else { self.read(connection, buf) }
        }
    }

    // MARK: commands

    private func handle(_ body: [String: Any]) -> [String: Any] {
        let op = body["op"] as? String ?? ""
        let start = Date()
        issues.removeAll()
        // Fail closed: a runner started without a token refuses everything.
        guard !token.isEmpty, body["token"] as? String == token else {
            return ["ok": false, "code": "UNAUTHORIZED", "message": "missing or wrong runner token", "op": op]
        }
        // A crashed or backgrounded app has no elements: "not found", "hidden" or "not focused" would then be
        // observations of nothing. Refuse to observe or act unless the app is in the foreground.
        let needsApp: Set = ["tree", "find", "get", "wait", "tap", "longpress", "doubletap", "type", "key", "swipe"]
        if needsApp.contains(op) && app.state != .runningForeground {
            return ["ok": false, "code": "APP_NOT_RUNNING", "message": "the app is not in the foreground (state \(app.state.rawValue))",
                    "state": app.state.rawValue, "op": op]
        }
        var out: [String: Any]
        switch op {
        case "ping": out = ["ok": true, "pid": ProcessInfo.processInfo.processIdentifier]
        case "activate":
            app.activate()
            out = ["ok": app.wait(for: .runningForeground, timeout: 10), "state": app.state.rawValue]
        case "launch":
            app.launchArguments = body["args"] as? [String] ?? []
            app.launchEnvironment = body["env"] as? [String: String] ?? [:]
            app.launch()
            out = ["ok": app.state == .runningForeground]
        case "terminate":
            app.terminate()
            out = ["ok": true]
        case "state": out = ["ok": true, "state": app.state.rawValue]
        case "tree":
            if let nodes = tree() {
                out = ["ok": true, "nodes": nodes, "focused": focused().map { $0.identifier } ?? NSNull()]
            } else {
                out = ["ok": false, "code": "SNAPSHOT_FAILED", "message": "could not read the UI tree"]
            }
        case "find":
            let found = matches(body)
            out = ["ok": !found.isEmpty, "matches": found.map(describe)]
        case "get":
            let resolved = resolve(body)
            if let element = resolved.element { out = ["ok": true, "element": describe(element)] } else { out = resolved.error ?? [:] }
        case "wait": out = wait(body)
        case "tap", "longpress", "doubletap": out = act(op, body)
        case "type": out = type(body)
        case "key": out = key(body)
        case "swipe": out = swipe(body)
        case "alert": out = alert(body)
        case "orientation": out = orientation(body)
        case "shutdown":
            stop = true
            out = ["ok": true]
        default: out = ["ok": false, "code": "UNSUPPORTED", "message": "unknown op \(op)"]
        }
        if !issues.isEmpty { out = ["ok": false, "code": "XCTEST_ISSUE", "message": issues.joined(separator: " | ")] }
        out["op"] = op
        out["ms"] = Int(Date().timeIntervalSince(start) * 1000)
        return out
    }

    // MARK: locators

    private func root(_ body: [String: Any]) -> XCUIElement {
        if let scope = body["app"] as? String { return XCUIApplication(bundleIdentifier: scope) }
        return app
    }

    private func query(_ body: [String: Any]) -> XCUIElementQuery {
        let sel = body["sel"] as? [String: String] ?? [:]
        var preds: [NSPredicate] = []
        if let value = sel["id"] { preds.append(NSPredicate(format: "identifier == %@", value)) }
        if let value = sel["label"] { preds.append(NSPredicate(format: "label == %@", value)) }
        if let value = sel["text"] { preds.append(NSPredicate(format: "label == %@ OR value == %@ OR title == %@", value, value, value)) }
        if let value = sel["contains"] { preds.append(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", value, value)) }
        let type = sel["role"].flatMap(elementType) ?? .any
        return root(body).descendants(matching: type).matching(NSCompoundPredicate(andPredicateWithSubpredicates: preds))
    }

    private func matches(_ body: [String: Any]) -> [XCUIElement] {
        let found = query(body)
        return (0..<min(found.count, 20)).map { found.element(boundBy: $0) }
    }

    /// The matches listed in a refusal, for diagnosis only. Elements can vanish while they are read; XCUITest
    /// reports that as an issue, which must not replace the refusal code the caller acts on.
    private func describeMatches(_ body: [String: Any]) -> [[String: Any]] {
        let known = issues.count
        let listed = matches(body).filter { $0.exists }.map(describe)
        issues.removeSubrange(known...)
        return listed
    }

    private func resolve(_ body: [String: Any]) -> (element: XCUIElement?, error: [String: Any]?) {
        let found = query(body)
        let count = found.count
        if let nth = (body["sel"] as? [String: String])?["nth"].flatMap(Int.init) {
            return nth < count ? (found.element(boundBy: nth), nil) : (nil, ["ok": false, "code": "NOT_FOUND", "message": "nth \(nth) of \(count)"])
        }
        if count == 0 { return (nil, ["ok": false, "code": "NOT_FOUND", "message": "no match for \(body["sel"] ?? [:])"]) }
        if count > 1 { return (nil, ["ok": false, "code": "AMBIGUOUS", "message": "\(count) matches", "matches": describeMatches(body)]) }
        return (found.element(boundBy: 0), nil)
    }

    private func unchangedMatches(_ body: [String: Any], _ countAtResolve: Int) -> [String: Any]? {
        let now = query(body).count
        guard now != countAtResolve else { return nil }
        return ["ok": false, "code": "MATCHES_CHANGED", "message": "matches went from \(countAtResolve) to \(now) before acting; retry",
                "matches": describeMatches(body)]
    }

    /// For actions: give a target that is still appearing (a sheet or toolbar animating in) up to `timeout` to exist
    /// before reporting NOT_FOUND. Ambiguity is refused at once; it never resolves itself by waiting.
    private func resolveForAction(_ body: [String: Any]) -> (element: XCUIElement?, error: [String: Any]?) {
        let end = Date().addingTimeInterval(body["timeout"] as? Double ?? 2)
        var resolved = resolve(body)
        while resolved.element == nil, resolved.error?["code"] as? String == "NOT_FOUND", Date() < end {
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            resolved = resolve(body)
        }
        return resolved
    }

    private func elementType(_ role: String) -> XCUIElement.ElementType? {
        ["button": .button, "textfield": .textField, "text-field": .textField, "textview": .textView, "searchfield": .searchField,
         "statictext": .staticText, "text": .staticText, "link": .link, "cell": .cell, "menuitem": .menuItem, "window": .window,
         "webview": .webView, "keyboard": .keyboard, "alert": .alert, "sheet": .sheet, "tab": .tab, "image": .image,
         "other": .other, "switch": .switch][role.lowercased()]
    }

    private func describe(_ element: XCUIElement) -> [String: Any] {
        let frame = element.frame
        return ["type": element.elementType.rawValue, "id": element.identifier, "label": element.label, "value": "\(element.value ?? "")",
                "enabled": element.isEnabled, "hittable": element.isHittable, "frame": [frame.minX, frame.minY, frame.width, frame.height]]
    }

    private func tree() -> [[String: Any]]? {
        guard let snap = try? app.snapshot() else { return nil }
        var out: [[String: Any]] = []
        func walk(_ node: XCUIElementSnapshot, _ depth: Int) {
            let frame = node.frame
            out.append(["d": depth, "type": node.elementType.rawValue, "id": node.identifier, "label": node.label,
                        "value": "\(node.value ?? "")", "enabled": node.isEnabled, "selected": node.isSelected,
                        "frame": [frame.minX, frame.minY, frame.width, frame.height]])
            node.children.forEach { walk($0, depth + 1) }
        }
        walk(snap, 0)
        return out
    }

    private func digest() -> Int {
        guard let snap = try? app.snapshot() else { return 0 }
        var hasher = Hasher()
        func walk(_ node: XCUIElementSnapshot) {
            hasher.combine(node.identifier)
            hasher.combine(node.label)
            hasher.combine("\(node.value ?? "")")
            hasher.combine(node.isEnabled)
            hasher.combine(node.isSelected)
            hasher.combine(node.elementType.rawValue)
            hasher.combine("\(node.frame)")   // scrolling and layout changes move frames without changing labels
            node.children.forEach(walk)
        }
        walk(snap)
        return hasher.finalize()
    }

    private func focused() -> XCUIElement? {
        let found = app.descendants(matching: .any).matching(NSPredicate(format: "hasKeyboardFocus == true"))
        return found.count > 0 ? found.element(boundBy: 0) : nil
    }

    private func keyboardShown() -> Bool {
        app.keyboards.count > 0
    }

    // MARK: actions

    private func actionable(_ element: XCUIElement, timeout: Double) -> [String: Any]? {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            if element.exists && element.isEnabled && element.isHittable { return nil }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < end
        if !element.exists { return ["ok": false, "code": "NOT_FOUND", "message": "element vanished"] }
        if !element.isEnabled { return ["ok": false, "code": "DISABLED", "message": "element is disabled", "element": describe(element)] }
        return ["ok": false, "code": "NOT_HITTABLE", "message": "element is covered or off-screen", "element": describe(element)]
    }

    private func after(_ before: Int, settle: Double = 0.6) -> [String: Any] {
        let end = Date().addingTimeInterval(settle)
        var current = digest()
        while current == before && Date() < end {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            current = digest()
        }
        return ["changed": current != before, "keyboard": keyboardShown(), "focused": focused().map { $0.identifier } as Any]
    }

    private func act(_ op: String, _ body: [String: Any]) -> [String: Any] {
        let resolved = resolveForAction(body)
        guard let element = resolved.element else { return resolved.error ?? [:] }
        let countAtResolve = query(body).count
        if let err = actionable(element, timeout: body["timeout"] as? Double ?? 2) { return err }
        // The element is a live query: if the matches changed while waiting for it to become hittable, the tap
        // could land on a different element than the one resolved. Refuse rather than guess.
        if let err = unchangedMatches(body, countAtResolve) { return err }
        let matched = describe(element)
        let before = digest()
        switch op {
        case "longpress": element.press(forDuration: (body["ms"] as? Double ?? 800) / 1000)
        case "doubletap": element.doubleTap()
        default: element.tap()
        }
        return ["ok": true, "matched": matched, "after": after(before)]
    }

    private func type(_ body: [String: Any]) -> [String: Any] {
        let text = body["text"] as? String ?? ""
        let target: XCUIElement
        if body["sel"] != nil {
            let resolved = resolveForAction(body)
            guard let element = resolved.element else { return resolved.error ?? [:] }
            let countAtResolve = query(body).count
            if let err = actionable(element, timeout: 2) { return err }
            if let err = unchangedMatches(body, countAtResolve) { return err }
            if !(element.value(forKey: "hasKeyboardFocus") as? Bool ?? false) { element.tap() }
            target = element
        } else {
            guard let element = focused() else { return ["ok": false, "code": "NOT_FOCUSED", "message": "no element has keyboard focus"] }
            target = element
        }
        let beforeValue = "\(target.value ?? "")"
        let before = digest()
        target.typeText(text)
        let observed = after(before)
        let afterValue = target.exists ? "\(target.value ?? "")" : "<gone>"
        let landed: Bool
        if text.trimmingCharacters(in: .newlines).isEmpty || afterValue == "<gone>" {
            landed = observed["changed"] as? Bool ?? false
        } else {
            landed = afterValue != beforeValue
        }
        let matched: [String: Any] = target.exists ? describe(target) : ["gone": true]
        return ["ok": landed, "code": landed ? "OK" : "NO_EFFECT", "matched": matched,
                "valueBefore": beforeValue, "valueAfter": afterValue, "after": observed]
    }

    private func key(_ body: [String: Any]) -> [String: Any] {
        let parts = (body["combo"] as? String ?? "").lowercased().split(separator: "+").map(String.init)
        var flags: XCUIElement.KeyModifierFlags = []
        for part in parts.dropLast() {
            switch part {
            case "cmd": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "alt", "opt": flags.insert(.option)
            case "ctrl": flags.insert(.control)
            default: break
            }
        }
        let last = parts.last ?? ""
        let named: [String: String] = ["return": XCUIKeyboardKey.return.rawValue, "escape": XCUIKeyboardKey.escape.rawValue,
                                       "tab": XCUIKeyboardKey.tab.rawValue, "delete": XCUIKeyboardKey.delete.rawValue]
        let before = digest()
        app.typeKey(named[last] ?? last, modifierFlags: flags)
        return ["ok": true, "after": after(before)]
    }

    private func swipe(_ body: [String: Any]) -> [String: Any] {
        let element: XCUIElement
        if body["sel"] != nil {
            let resolved = resolveForAction(body)
            guard let found = resolved.element else { return resolved.error ?? [:] }
            let countAtResolve = query(body).count
            if let err = actionable(found, timeout: body["timeout"] as? Double ?? 2) { return err }
            if let err = unchangedMatches(body, countAtResolve) { return err }
            element = found
        } else {
            element = app
        }
        let before = digest()
        switch body["dir"] as? String ?? "up" {
        case "down": element.swipeDown()
        case "left": element.swipeLeft()
        case "right": element.swipeRight()
        default: element.swipeUp()
        }
        return ["ok": true, "after": after(before)]
    }

    private func wait(_ body: [String: Any]) -> [String: Any] {
        let timeout = body["timeout"] as? Double ?? 5
        let state = body["state"] as? String ?? "visible"
        let end = Date().addingTimeInterval(timeout)
        let nth = (body["sel"] as? [String: String])?["nth"].flatMap(Int.init)
        var polls = 0
        var ambiguous = 0
        repeat {
            polls += 1
            let found = query(body)
            let count = found.count
            // Without nth, a state is only reported for exactly one match: "the first of several" is a guess.
            ambiguous = nth == nil && count > 1 ? count : 0
            let target: XCUIElement? = nth.map { $0 < count ? found.element(boundBy: $0) : nil }
                ?? (count == 1 ? found.element(boundBy: 0) : nil)
            let exists = target?.exists ?? false
            let done: Bool
            switch state {
            case "hidden": done = nth == nil ? count == 0 : !exists
            case "exists": done = exists
            case "enabled": done = exists && (target?.isEnabled ?? false)
            default: done = exists && (target?.isHittable ?? false)   // "visible": on screen and not covered
            }
            if done { return ["ok": true, "polls": polls] }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < end
        if ambiguous > 0 && state != "hidden" {
            return ["ok": false, "code": "AMBIGUOUS", "message": "\(ambiguous) matches; add nth=", "polls": polls,
                    "matches": describeMatches(body)]
        }
        return ["ok": false, "code": "TIMEOUT", "polls": polls]
    }

    /// Reads, or with "set" changes, the device orientation; reports the app window's size so the caller can confirm
    /// the app actually rotated (an app that doesn't support an orientation stays as it was).
    private func orientation(_ body: [String: Any]) -> [String: Any] {
        let names: [String: UIDeviceOrientation] = ["portrait": .portrait, "portraitUpsideDown": .portraitUpsideDown,
                                                    "landscapeLeft": .landscapeLeft, "landscapeRight": .landscapeRight]
        if let wanted = body["set"] as? String {
            guard let value = names[wanted] else {
                return ["ok": false, "code": "UNSUPPORTED", "message": "orientation must be one of \(names.keys.sorted())"]
            }
            XCUIDevice.shared.orientation = value
            RunLoop.current.run(until: Date().addingTimeInterval(1))   // the rotation animation
        }
        let current = names.first { $0.value == XCUIDevice.shared.orientation }?.key ?? "unknown"
        let frame = app.windows.firstMatch.exists ? app.windows.firstMatch.frame : .zero
        return ["ok": true, "orientation": current, "window": [frame.width, frame.height]]
    }

    /// Answers the first alert in the app or SpringBoard (iOS permission alerts belong to SpringBoard).
    private func alert(_ body: [String: Any]) -> [String: Any] {
        let roots: [XCUIApplication] = [app, XCUIApplication(bundleIdentifier: "com.apple.springboard")]
        let deadline = Date().addingTimeInterval(body["timeout"] as? Double ?? 5)
        repeat {
            for root in roots where root.alerts.count > 0 {
                let title = root.alerts.firstMatch.label
                let buttons = root.alerts.buttons
                let labels = (0..<buttons.count).map { buttons.element(boundBy: $0).label }
                var target: XCUIElement?
                if let want = body["button"] as? String {
                    target = labels.contains(want) ? buttons[want] : nil
                } else if labels.count > 2 {
                    // e.g. "Allow Once / Allow While Using App / Don't Allow": "accept" would be a guess
                    return ["ok": false, "code": "AMBIGUOUS", "message": "alert has \(labels.count) buttons; name one with button=",
                            "alert": title, "buttons": labels]
                } else if !labels.isEmpty {
                    target = buttons.element(boundBy: (body["action"] as? String) == "dismiss" ? 0 : labels.count - 1)
                }
                guard let button = target else { return ["ok": false, "code": "NOT_FOUND", "message": "no button", "alert": title, "buttons": labels] }
                if let err = actionable(button, timeout: 2) { return err.merging(["alert": title, "buttons": labels]) { old, _ in old } }
                let pressed = button.label
                let before = digest()
                button.tap()
                let end = Date().addingTimeInterval(3)
                while root.alerts.count > 0 && Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
                let dismissed = root.alerts.count == 0
                return ["ok": dismissed, "code": dismissed ? "OK" : "ALERT_STILL_SHOWN", "pressed": pressed, "alert": title,
                        "buttons": labels, "after": after(before)]
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return ["ok": false, "code": "NOT_FOUND", "message": "no alert"]
    }
}
