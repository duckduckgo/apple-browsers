//
//  main.swift
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

import BrowserMCPTools
import Foundation
import MCP

// stdio MCP server that drives a Debug/Review build of the DuckDuckGo browser through its
// AutomationServer. Configuration comes from the environment:
//   DDG_AUTOMATION_PORT  port passed to the browser as -automationPort (default 8788)
//   DDG_APP_PATH         DuckDuckGo.app used by browser_launch
//   AUTOMATION_TOKEN     optional bearer token, forwarded to the browser on launch

let environment = ProcessInfo.processInfo.environment
let port = environment["DDG_AUTOMATION_PORT"].flatMap(Int.init) ?? 8788
let configuration = BrowserToolsConfiguration(
    port: port,
    appPath: environment["DDG_APP_PATH"],
    authToken: environment["AUTOMATION_TOKEN"]
)
let tools = BrowserTools(
    transport: HTTPAutomationClient(port: port, authToken: configuration.authToken),
    configuration: configuration
)

let server = Server(
    name: "ddg-browser",
    version: "1.0.0",
    capabilities: .init(tools: .init())
)
await tools.register(on: server)

try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
