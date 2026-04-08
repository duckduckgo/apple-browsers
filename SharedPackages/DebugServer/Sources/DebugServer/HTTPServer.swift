import Foundation

/// The running state of an HTTP server.
public enum ServerState: Sendable, Equatable {
    case stopped
    case starting
    case running(port: UInt16)
    case failed(String)
}

/// A local HTTP server for debug tooling.
public protocol HTTPServerProtocol: RouteRegistrable {

    /// The current state of the server.
    var state: ServerState { get }

    /// Called when the server state changes.
    var stateDidChange: (@Sendable (ServerState) -> Void)? { get set }

    /// Starts listening for connections on the configured port.
    func start() throws

    /// Stops the server and closes all active connections.
    func stop()
}
