import Foundation

/// Serializes an `HTTPResponse` into raw HTTP response data.
public struct ResponseSerializer: Sendable {

    public init() {}

    /// Converts an `HTTPResponse` into raw bytes suitable for writing to a TCP connection.
    ///
    /// - Parameter response: The response to serialize.
    /// - Returns: The raw HTTP response data.
    public func serialize(_ response: HTTPResponse) -> Data {
        var result = "HTTP/1.1 \(response.status.rawValue) \(response.status.reasonPhrase)\r\n"

        var headers = response.headers
        let bodyData = response.body ?? Data()

        if headers["Content-Length"] == nil {
            headers["Content-Length"] = "\(bodyData.count)"
        }
        if headers["Connection"] == nil {
            headers["Connection"] = "close"
        }

        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            result += "\(key): \(value)\r\n"
        }

        result += "\r\n"

        var data = result.data(using: .utf8) ?? Data()
        data.append(bodyData)
        return data
    }
}
