//
//  PermissionsDebugInspector.swift
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
import Foundation
import FoundationExtensions
import WebKit

/// Serves the debug-only Permissions inspector page at `duck://permissions` (Debug ▸ Permissions ▸ Inspect).
final class PermissionsDebugInspector {
    private let permissionManager: PermissionManagerProtocol
    private let fireproofDomains: DomainFireproofStatusProviding

    init(
        permissionManager: PermissionManagerProtocol,
        fireproofDomains: DomainFireproofStatusProviding = NSApp.delegateTyped.fireproofDomains
    ) {
        self.permissionManager = permissionManager
        self.fireproofDomains = fireproofDomains
    }

    func handle(requestURL: URL, urlSchemeTask: WKURLSchemeTask) {
        switch requestURL.path {
        case "", "/", "/index.html":
            send(Page.html, mimeType: "text/html", for: requestURL, to: urlSchemeTask)
            return
        case "/app.js":
            send(Page.js, mimeType: "text/javascript", for: requestURL, to: urlSchemeTask)
            return
        default:
            break
        }

        guard requestURL.path.hasPrefix("/api/"), let debug = permissionManager as? PermissionManagerDebugging else {
            fail(urlSchemeTask, statusCode: 404, for: requestURL)
            return
        }

        switch apiResponse(for: requestURL, debug: debug) {
        case .data(let data, let mimeType):
            send(data, mimeType: mimeType, for: requestURL, to: urlSchemeTask)
        case .notFound:
            fail(urlSchemeTask, statusCode: 404, for: requestURL)
        }
    }

    // MARK: - API

    private func apiResponse(for requestURL: URL, debug: PermissionManagerDebugging) -> Response {
        let queryItems = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func queryValue(_ name: String) -> String? { queryItems.first { $0.name == name }?.value }

        switch requestURL.path {
        case "/api/list":
            let rows = debug.allPermissionsDebugEntries().map { entry in
                let normalizedDomain = entry.domain.droppingWwwPrefix()
                return Row(entry: entry, isFireproof: fireproofDomains.isFireproof(fireproofDomain: normalizedDomain))
            }
            guard let data = try? JSONEncoder().encode(rows) else { return .notFound }
            return .data(data, "application/json")

        case "/api/remove":
            let identifiers = Self.parseIdentifiers(queryValue("keys") ?? "")
            let removedCount = debug.removePermissionsDebugEntries(withIdentifiers: identifiers)
            return jsonCount(removedCount, key: "removed")

        case "/api/removeAll":
            return jsonCount(debug.removeAllPermissions(), key: "removed")

        default:
            return .notFound
        }
    }

    /// Parses the `keys` param of `/api/remove`: comma-separated opaque storage identifiers.
    private static func parseIdentifiers(_ value: String) -> Set<String> {
        Set(value.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    private func jsonCount(_ count: Int, key: String) -> Response {
        guard let data = try? JSONEncoder().encode([key: count]) else { return .notFound }
        return .data(data, "application/json")
    }

    // MARK: - Responses

    private func send(_ data: Data, mimeType: String, for url: URL, to task: WKURLSchemeTask) {
        // Respond with HTTP 200 (not a bare URLResponse) so the page's `fetch()` sees `response.ok`.
        let headers = ["Content-Type": mimeType, "Content-Length": String(data.count)]
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) else {
            task.didFailWithError(URLError(.badServerResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private func fail(_ task: WKURLSchemeTask, statusCode: Int, for url: URL) {
        guard let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: nil) else {
            task.didFailWithError(URLError(.badServerResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(Data())
        task.didFinish()
    }

}

private enum Response {
    case data(Data, String)
    case notFound
}

private extension PersistedPermissionDecision {
    var debugName: String {
        switch self {
        case .allow: return "allow"
        case .deny: return "deny"
        case .ask: return "ask"
        }
    }

    var autoplayDebugName: String {
        switch self {
        case .allow: return "video and audio"
        case .ask: return "stop videos with sound"
        case .deny: return "never"
        }
    }
}

/// JSON row shape consumed by the inspector page's script. Field names match the
/// `PermissionManagedObject` columns, except `effective`/`isFireproof`, which are runtime state.
private struct Row: Encodable {
    let key: String
    let domainEncrypted: String
    let permissionType: String
    let allow: Bool
    let isRemoved: Bool
    let effective: String
    let effectiveDecision: String
    let isOverridden: Bool
    let isFireproof: Bool

    init(entry: PermissionDebugEntry, isFireproof: Bool) {
        key = entry.storageIdentifier
        domainEncrypted = entry.domain
        permissionType = entry.permissionType
        allow = entry.allow
        isRemoved = entry.isRemoved
        effectiveDecision = entry.effectiveDecision.debugName
        effective = entry.permissionType == PermissionType.autoplayPolicy.rawValue
            ? entry.effectiveDecision.autoplayDebugName
            : effectiveDecision
        isOverridden = entry.isOverridden
        self.isFireproof = isFireproof
    }
}

private enum Page {
    static let html = load("permissions-inspector", withExtension: "html")
    static let js = load("permissions-inspector", withExtension: "js")

    private static func load(_ name: String, withExtension fileExtension: String) -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("\(name).\(fileExtension) is missing from the app bundle")
            return Data()
        }
        return data
    }

}
