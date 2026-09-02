//
//  DebugControlHTTP.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

#if DEBUG

import Foundation

struct DebugControlRequest {
    let method: String
    let path: String
    let query: [String: String]
    let body: Data

    var json: [String: Any] {
        guard !body.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return [:] }
        return object
    }

    func string(_ name: String) -> String? {
        if let value = json[name] as? String { return value }
        return query[name]
    }

    func bool(_ name: String, default defaultValue: Bool) -> Bool {
        if let value = json[name] as? Bool { return value }
        if let value = query[name] { return value == "1" || value.lowercased() == "true" }
        return defaultValue
    }

    func int(_ name: String) -> Int? {
        if let value = json[name] as? Int { return value }
        if let value = query[name] { return Int(value) }
        return nil
    }

    func double(_ name: String) -> Double? {
        if let value = json[name] as? Double { return value }
        if let value = query[name] { return Double(value) }
        return nil
    }
}

struct DebugControlResponse {
    let status: Int
    let payload: [String: Any]

    static func ok(_ fields: [String: Any] = [:]) -> DebugControlResponse {
        var payload = fields
        payload["ok"] = true
        return DebugControlResponse(status: 200, payload: payload)
    }

    static func failure(_ error: String, status: Int = 400) -> DebugControlResponse {
        DebugControlResponse(status: status, payload: ["ok": false, "error": error])
    }

    var httpData: Data {
        let body: Data
        if let encoded = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .fragmentsAllowed]) {
            body = encoded
        } else {
            body = Data(#"{"ok":false,"error":"response is not JSON serializable"}"#.utf8)
        }
        let head = """
        HTTP/1.1 \(status) \(DebugControlResponse.statusText(status))\r
        Content-Type: application/json\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r

        """
        return Data(head.utf8) + body
    }

    private static func statusText(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        default: return "Internal Server Error"
        }
    }
}

/// Accumulates bytes from a single connection until a complete HTTP/1.1 request is available.
struct DebugControlRequestParser {
    enum ParseResult {
        case incomplete
        case request(DebugControlRequest)
        case malformed(String)
    }

    static let maxRequestSize = 8 * 1024 * 1024

    private var buffer = Data()

    mutating func append(_ data: Data) -> ParseResult {
        buffer.append(data)
        guard buffer.count <= Self.maxRequestSize else {
            buffer.removeAll()
            return .malformed("request exceeds \(Self.maxRequestSize) bytes")
        }
        return parse()
    }

    private mutating func parse() -> ParseResult {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = buffer.firstRange(of: separator) else { return .incomplete }

        let headerData = buffer[buffer.startIndex..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            buffer.removeAll()
            return .malformed("headers are not valid UTF-8")
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .malformed("empty request") }
        let requestLineParts = requestLine.split(separator: " ")
        guard requestLineParts.count >= 2 else {
            buffer.removeAll()
            return .malformed("malformed request line")
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
        guard contentLength >= 0, contentLength <= Self.maxRequestSize else {
            buffer.removeAll()
            return .malformed("invalid Content-Length")
        }

        let bodyStart = headerRange.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= contentLength else { return .incomplete }

        let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
        let body = Data(buffer[bodyStart..<bodyEnd])
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)

        let target = String(requestLineParts[1])
        let components = URLComponents(string: target)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] where item.value != nil {
            query[item.name] = item.value
        }

        return .request(DebugControlRequest(method: String(requestLineParts[0]).uppercased(),
                                            path: components?.path ?? target,
                                            query: query,
                                            body: body))
    }
}

#endif
