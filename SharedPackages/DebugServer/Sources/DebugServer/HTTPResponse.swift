import Foundation

/// An HTTP response to send back to the client.
public struct HTTPResponse: Sendable {
    public let status: HTTPStatusCode
    public let headers: [String: String]
    public let body: Data?

    public init(
        status: HTTPStatusCode,
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.status = status
        self.headers = headers
        self.body = body
    }
}

// MARK: - Convenience Initializers

public extension HTTPResponse {

    /// Creates a response with a JSON body and appropriate Content-Type header.
    static func json(_ data: Data, status: HTTPStatusCode = .ok) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }

    /// Creates a response with an HTML body and appropriate Content-Type header.
    static func html(_ string: String, status: HTTPStatusCode = .ok) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: string.data(using: .utf8)
        )
    }

    /// Creates a plain text response.
    static func text(_ string: String, status: HTTPStatusCode = .ok) -> HTTPResponse {
        HTTPResponse(
            status: status,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: string.data(using: .utf8)
        )
    }

    /// Creates an empty response with a given status code.
    static func empty(status: HTTPStatusCode = .noContent) -> HTTPResponse {
        HTTPResponse(status: status)
    }
}
