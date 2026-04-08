import Foundation

/// A closure that handles an HTTP request and returns a response.
public typealias RouteHandler = @Sendable (HTTPRequest) throws -> HTTPResponse

/// Provides route registration capabilities.
public protocol RouteRegistrable: AnyObject {

    /// Registers a handler for the given method and path.
    ///
    /// - Parameters:
    ///   - path: The URL path to match (e.g., "/api/chats").
    ///   - method: The HTTP method to match.
    ///   - handler: A closure invoked when a matching request is received.
    func addRoute(_ path: String, method: HTTPMethod, handler: @escaping RouteHandler)

    /// Registers a handler for requests whose path starts with the given prefix.
    ///
    /// Prefix routes are checked only when no exact route matches.
    ///
    /// - Parameters:
    ///   - pathPrefix: The URL path prefix to match (e.g., "/api/chats/").
    ///   - method: The HTTP method to match.
    ///   - handler: A closure invoked when a matching request is received.
    func addPrefixRoute(_ pathPrefix: String, method: HTTPMethod, handler: @escaping RouteHandler)

    /// Registers a static HTML response for the given path (GET only).
    ///
    /// - Parameters:
    ///   - path: The URL path to match.
    ///   - htmlString: The HTML content to serve.
    func addStaticRoute(_ path: String, htmlString: String)
}
