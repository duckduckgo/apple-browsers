import Foundation

/// Represents a parsed HTTP request.
public protocol HTTPRequestProtocol: Sendable {
    var method: HTTPMethod { get }
    var path: String { get }
    var queryParameters: [String: String] { get }
    var headers: [String: String] { get }
    var body: Data? { get }
}

/// Concrete HTTP request parsed from raw data.
public struct HTTPRequest: HTTPRequestProtocol {
    public let method: HTTPMethod
    public let path: String
    public let queryParameters: [String: String]
    public let headers: [String: String]
    public let body: Data?

    public init(
        method: HTTPMethod,
        path: String,
        queryParameters: [String: String] = [:],
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.queryParameters = queryParameters
        self.headers = headers
        self.body = body
    }
}
