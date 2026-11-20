//
//  DeleteAllChatsTestServer.swift
//  DuckDuckGo
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
import Swifter

final class DeleteAllChatsTestServer {
    private let server = HttpServer()
    private(set) var baseURL = ""

    var chatURL: String { baseURL.replacingOccurrences(of: "127.0.0.1", with: "localhost") + "/chat" }
    var websiteURL: String { baseURL + "/website" }

    func start() throws {
        server["/chat"] = { _ in
            .ok(.html("<meta name=viewport content='width=device-width,initial-scale=1'><title>Offline chat</title><h1>Offline chat</h1>"))
        }
        server["/website"] = { _ in
            .ok(.html("<meta name=viewport content='width=device-width,initial-scale=1'><title>Offline website</title><h1>Offline website</h1>"))
        }
        server["/atb.js"] = { _ in
            .ok(.json(["version": "v1-1", "majorVersion": 1, "minorVersion": 1]))
        }
        server["/exti/"] = { _ in .accepted }
        try server.start(0, forceIPv4: true, priority: .userInitiated)
        baseURL = "http://127.0.0.1:\(try server.port())"
    }

    func stop() {
        server.stop()
    }
}
