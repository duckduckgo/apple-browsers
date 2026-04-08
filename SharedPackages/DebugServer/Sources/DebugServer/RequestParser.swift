import Foundation

/// Errors that can occur during HTTP request parsing.
public enum RequestParserError: Error, Equatable {
    case emptyData
    case invalidRequestLine
    case unsupportedMethod(String)
    case malformedHeader
    case incompletebody
}

/// Parses raw HTTP data into an `HTTPRequest`.
public struct RequestParser: Sendable {

    public init() {}

    /// Parses raw HTTP request data into a structured `HTTPRequest`.
    ///
    /// - Parameter data: The raw bytes received from the TCP connection.
    /// - Returns: A parsed `HTTPRequest`.
    /// - Throws: `RequestParserError` if the data cannot be parsed.
    public func parse(_ data: Data) throws -> HTTPRequest {
        guard !data.isEmpty else {
            throw RequestParserError.emptyData
        }

        let (headerSection, bodyData) = splitHeaderAndBody(originalData: data)
        guard !headerSection.isEmpty else {
            throw RequestParserError.invalidRequestLine
        }

        let lines = headerSection.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            throw RequestParserError.invalidRequestLine
        }

        let (method, path, queryParameters) = try parseRequestLine(requestLine)
        let headers = try parseHeaders(Array(lines.dropFirst()))

        return HTTPRequest(
            method: method,
            path: path,
            queryParameters: queryParameters,
            headers: headers,
            body: bodyData
        )
    }

    // MARK: - Private

    private static let headerBodySeparator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n

    private func splitHeaderAndBody(originalData: Data) -> (String, Data?) {
        guard let separatorRange = originalData.range(of: Self.headerBodySeparator) else {
            return (String(data: originalData, encoding: .utf8) ?? "", nil)
        }

        let headerData = originalData.subdata(in: 0..<separatorRange.lowerBound)
        let headerSection = String(data: headerData, encoding: .utf8) ?? ""
        let bodyStartIndex = separatorRange.upperBound

        guard bodyStartIndex < originalData.count else {
            return (headerSection, nil)
        }

        let bodyData = originalData.subdata(in: bodyStartIndex..<originalData.count)
        return (headerSection, bodyData.isEmpty ? nil : bodyData)
    }

    private func parseRequestLine(_ line: String) throws -> (HTTPMethod, String, [String: String]) {
        let parts = line.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2 else {
            throw RequestParserError.invalidRequestLine
        }

        let methodString = String(parts[0])
        guard let method = HTTPMethod(rawValue: methodString) else {
            throw RequestParserError.unsupportedMethod(methodString)
        }

        let fullPath = String(parts[1])
        let (path, queryParameters) = parsePathAndQuery(fullPath)

        return (method, path, queryParameters)
    }

    private func parsePathAndQuery(_ fullPath: String) -> (String, [String: String]) {
        let components = fullPath.split(separator: "?", maxSplits: 1)
        let path = String(components[0])

        guard components.count == 2 else {
            return (path, [:])
        }

        let queryString = String(components[1])
        var queryParameters: [String: String] = [:]

        for pair in queryString.split(separator: "&") {
            let keyValue = pair.split(separator: "=", maxSplits: 1)
            let key = String(keyValue[0])
                .removingPercentEncoding ?? String(keyValue[0])
            let value = keyValue.count == 2
                ? (String(keyValue[1]).removingPercentEncoding ?? String(keyValue[1]))
                : ""
            queryParameters[key] = value
        }

        return (path, queryParameters)
    }

    private func parseHeaders(_ lines: [String]) throws -> [String: String] {
        var headers: [String: String] = [:]

        for line in lines where !line.isEmpty {
            guard let colonIndex = line.firstIndex(of: ":") else {
                throw RequestParserError.malformedHeader
            }
            let key = String(line[line.startIndex..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        return headers
    }
}
