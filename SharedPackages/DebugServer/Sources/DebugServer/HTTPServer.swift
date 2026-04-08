//
//  HTTPServer.swift
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
