//
//  ChromeWebStoreUpdateManifestParser.swift
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

import Foundation

/// Validates an update manifest and extracts metadata. A nil result means the server reported no update.
@available(macOS 15.4, iOS 18.4, *)
final class ChromeWebStoreUpdateManifestParser: NSObject, XMLParserDelegate {
    private static let namespace = "http://www.google.com/update2/response"
    private static let protocolVersion = "2.0"
    private static let successStatus = "ok"
    private static let noUpdateStatus = "noupdate"
    private static let maximumDepth = 16
    private static let maximumElementCount = 256
    private static let sha256HexLength = 64
    private let extensionID: String
    private var path: [String] = []
    private var elementCount = 0
    private var appCount = 0
    private var updateCount = 0
    private var invalid = false
    private var update: ChromeWebStoreUpdateChecker.Update?

    private init(extensionID: String) {
        self.extensionID = extensionID
    }

    static func parse(_ data: Data, extensionID: String) throws -> ChromeWebStoreUpdateChecker.Update? {
        guard let xml = String(data: data, encoding: .utf8), !xml.contains("\0"), !xml.contains("<!DOCTYPE") else {
            throw ChromeWebStoreUpdateChecker.Failure.invalidManifest
        }
        // Reject declarations of other encodings before XMLParser can reinterpret the UTF-8 bytes.
        let document = xml.hasPrefix("\u{FEFF}") ? String(xml.dropFirst()) : xml
        if document.hasPrefix("<?xml"), let end = document.range(of: "?>") {
            let declaration = String(document[..<end.lowerBound])
            if declaration.contains("encoding"),
               declaration.range(of: #"encoding\s*=\s*['"]UTF-8['"]"#, options: [.regularExpression, .caseInsensitive]) == nil {
                throw ChromeWebStoreUpdateChecker.Failure.invalidManifest
            }
        }
        let delegate = ChromeWebStoreUpdateManifestParser(extensionID: extensionID)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), !delegate.invalid, delegate.appCount == 1, delegate.updateCount == 1 else {
            throw ChromeWebStoreUpdateChecker.Failure.invalidManifest
        }
        return delegate.update
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        path.append(elementName)
        elementCount += 1
        guard path.count <= Self.maximumDepth, elementCount <= Self.maximumElementCount, namespaceURI == Self.namespace else {
            reject(parser)
            return
        }
        switch path {
        case ["gupdate"]:
            if attributeDict["protocol"] != Self.protocolVersion { reject(parser) }
        case ["gupdate", "app"]:
            appCount += 1
            if appCount != 1 || attributeDict["appid"] != extensionID || attributeDict["status"] != Self.successStatus { reject(parser) }
        case ["gupdate", "app", "updatecheck"]:
            readUpdate(attributeDict, parser: parser)
        case ["gupdate", "daystart"]:
            break
        default:
            reject(parser)
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = path.popLast()
    }

    private func readUpdate(_ attributes: [String: String], parser: XMLParser) {
        updateCount += 1
        guard updateCount == 1 else { reject(parser); return }
        if attributes["status"] == Self.noUpdateStatus { return }
        guard attributes["status"] == Self.successStatus, let version = attributes["version"], ChromeWebStoreUpdateChecker.isValidVersion(version),
              let codebase = attributes["codebase"], let url = URL(string: codebase),
              ChromeWebStoreURL.isAllowedDownloadDestination(url), url.fragment == nil,
              let sizeValue = attributes["size"], !sizeValue.isEmpty, sizeValue.utf8.allSatisfy({ (48...57).contains($0) }),
              let size = Int(sizeValue), size > 0,
              let hash = attributes["hash_sha256"], hash.utf8.count == Self.sha256HexLength,
              hash.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            reject(parser)
            return
        }
        update = ChromeWebStoreUpdateChecker.Update(extensionID: extensionID, version: version, downloadURL: url, size: size, sha256: hash.lowercased())
    }

    private func reject(_ parser: XMLParser) {
        invalid = true
        parser.abortParsing()
    }

}
