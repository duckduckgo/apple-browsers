//
//  BrowserTools.swift
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
import MCP

public struct BrowserToolsConfiguration: Sendable {
    /// Port the browser's automation server listens on (`-automationPort`).
    public var port: Int
    /// Path to a Debug or Review `DuckDuckGo.app`, used by `browser_launch` when no `app_path` argument is given.
    public var appPath: String?
    /// Optional bearer token, forwarded to the browser on launch and sent with every request.
    public var authToken: String?
    /// How long `browser_launch` waits for the browser to become ready.
    public var launchTimeout: TimeInterval

    public init(port: Int = 8788, appPath: String? = nil, authToken: String? = nil, launchTimeout: TimeInterval = 60) {
        self.port = port
        self.appPath = appPath
        self.authToken = authToken
        self.launchTimeout = launchTimeout
    }
}

/// MCP tool surface for driving the browser. Every tool is a thin adapter over an AutomationServer route,
/// so this type has no knowledge of tabs or web views beyond the HTTP contract.
public struct BrowserTools: Sendable {
    public let transport: AutomationTransport
    public let configuration: BrowserToolsConfiguration
    public let launcher: BrowserLaunching

    public init(transport: AutomationTransport,
                configuration: BrowserToolsConfiguration,
                launcher: BrowserLaunching = ProcessBrowserLauncher()) {
        self.transport = transport
        self.configuration = configuration
        self.launcher = launcher
    }

    // MARK: - Registration

    public func register(on server: Server) async {
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: Self.definitions)
        }
        await server.withMethodHandler(CallTool.self) { params in
            await self.handle(params)
        }
    }

    // MARK: - Tool Definitions

    public enum Name {
        public static let launch = "browser_launch"
        public static let navigate = "browser_navigate"
        public static let getURL = "browser_get_url"
        public static let getTitle = "browser_get_title"
        public static let goBack = "browser_go_back"
        public static let goForward = "browser_go_forward"
        public static let scroll = "browser_scroll"
        public static let execute = "browser_execute"
        public static let screenshot = "browser_screenshot"
        public static let tabList = "browser_tab_list"
        public static let tabNew = "browser_tab_new"
        public static let tabSwitch = "browser_tab_switch"
        public static let tabClose = "browser_tab_close"
        public static let clearWebsiteData = "browser_clear_website_data"
        public static let shutdown = "browser_shutdown"
    }

    public static let definitions: [Tool] = [
        Tool(
            name: Name.launch,
            description: "Launch a Debug/Review build of the DuckDuckGo browser with its automation server enabled and wait until it is ready. Not needed if the browser is already running with -automationPort.",
            inputSchema: schema([
                "app_path": string("Path to DuckDuckGo.app. Defaults to the DDG_APP_PATH environment variable.")
            ])
        ),
        Tool(
            name: Name.navigate,
            description: "Navigate the active tab to a URL and wait for the page to finish loading. Returns the final URL and title.",
            inputSchema: schema(["url": string("Absolute URL to load")], required: ["url"])
        ),
        Tool(name: Name.getURL, description: "Get the URL of the active tab.", inputSchema: schema()),
        Tool(name: Name.getTitle, description: "Get the title of the active tab.", inputSchema: schema()),
        Tool(name: Name.goBack, description: "Go back in the active tab's history.", inputSchema: schema()),
        Tool(name: Name.goForward, description: "Go forward in the active tab's history.", inputSchema: schema()),
        Tool(
            name: Name.scroll,
            description: "Scroll the active tab's viewport by a delta in CSS pixels.",
            inputSchema: schema([
                "x": number("Horizontal delta; positive scrolls right"),
                "y": number("Vertical delta; positive scrolls down")
            ])
        ),
        Tool(
            name: Name.execute,
            description: "Run JavaScript in the active tab and return its JSON-encoded result. The script is the body of an async function: use `return` to produce a value, and `await` is allowed. Named arguments are available as variables.",
            inputSchema: schema([
                "script": string("JavaScript function body to execute in the page"),
                "args": object("Optional named arguments exposed to the script as variables")
            ], required: ["script"])
        ),
        Tool(
            name: Name.screenshot,
            description: "Capture a PNG screenshot of the active tab's web view, optionally cropped to a rectangle in CSS pixels.",
            inputSchema: schema([
                "rect": .object([
                    "type": .string("object"),
                    "description": .string("Optional crop rectangle"),
                    "properties": .object([
                        "x": number("Left edge"), "y": number("Top edge"),
                        "width": number("Width"), "height": number("Height")
                    ]),
                    "required": .array([.string("x"), .string("y"), .string("width"), .string("height")])
                ])
            ])
        ),
        Tool(name: Name.tabList, description: "List all tabs with their stable handle, URL, title and whether each is active.", inputSchema: schema()),
        Tool(
            name: Name.tabNew,
            description: "Open a new tab, optionally loading a URL, and make it active. Returns the new tab's handle.",
            inputSchema: schema(["url": string("Optional URL to load in the new tab")])
        ),
        Tool(
            name: Name.tabSwitch,
            description: "Make the tab with the given handle active.",
            inputSchema: schema(["handle": string("Tab handle from browser_tab_list")], required: ["handle"])
        ),
        Tool(
            name: Name.tabClose,
            description: "Close a tab. Closes the active tab when no handle is given.",
            inputSchema: schema(["handle": string("Optional tab handle from browser_tab_list")])
        ),
        Tool(
            name: Name.clearWebsiteData,
            description: "Clear all website data (cookies, storage, cache) for the active tab's data store. The browser only allows this when it was launched with an AUTOMATION_TOKEN.",
            inputSchema: schema()
        ),
        Tool(name: Name.shutdown, description: "Quit the browser cleanly.", inputSchema: schema())
    ]

    // MARK: - Dispatch

    public func handle(_ params: CallTool.Parameters) async -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            switch params.name {
            case Name.launch:
                return try await launch(appPath: arguments["app_path"]?.stringValue)
            case Name.navigate:
                guard let url = arguments["url"]?.stringValue else { return Self.error("Missing required argument: url") }
                _ = try await transport.post("/navigate", query: ["url": url])
                return try await pageSummary()
            case Name.getURL:
                return .init(content: [.text(text: try await transport.get("/getUrl").message, annotations: nil, _meta: nil)])
            case Name.getTitle:
                return .init(content: [.text(text: try await transport.get("/getTitle").message, annotations: nil, _meta: nil)])
            case Name.goBack:
                _ = try await transport.post("/goBack")
                return try await pageSummary()
            case Name.goForward:
                _ = try await transport.post("/goForward")
                return try await pageSummary()
            case Name.scroll:
                let query = ["x": Self.numberString(arguments["x"]), "y": Self.numberString(arguments["y"])]
                _ = try await transport.post("/scroll", query: query)
                return Self.ok()
            case Name.execute:
                guard let script = arguments["script"]?.stringValue else { return Self.error("Missing required argument: script") }
                var query = ["script": script]
                if let args = arguments["args"], args != .null {
                    query["args"] = try Self.jsonString(args)
                }
                let response = try await transport.post("/execute", query: query)
                return .init(content: [.text(text: response.message, annotations: nil, _meta: nil)])
            case Name.screenshot:
                var query: [String: String] = [:]
                if let rect = arguments["rect"], rect != .null {
                    query["rect"] = try Self.jsonString(rect)
                }
                let response = try await transport.get("/screenshot", query: query)
                return .init(content: [.image(data: response.message, mimeType: "image/png", annotations: nil, _meta: nil)])
            case Name.tabList:
                return .init(content: [.text(text: try await transport.get("/getTabs").message, annotations: nil, _meta: nil)])
            case Name.tabNew:
                let response = try await transport.post("/newWindow")
                var result: [String: Value] = ["handle": .string(Self.handle(fromNewWindowResponse: response.message))]
                if let url = arguments["url"]?.stringValue {
                    _ = try await transport.post("/navigate", query: ["url": url])
                    result["url"] = .string(try await transport.get("/getUrl").message)
                    result["title"] = .string(try await transport.get("/getTitle").message)
                }
                return .init(content: [.text(text: try Self.jsonString(.object(result)), annotations: nil, _meta: nil)])
            case Name.tabSwitch:
                guard let handle = arguments["handle"]?.stringValue else { return Self.error("Missing required argument: handle") }
                _ = try await transport.post("/switchToWindow", query: ["handle": handle])
                return Self.ok()
            case Name.tabClose:
                if let handle = arguments["handle"]?.stringValue {
                    _ = try await transport.post("/switchToWindow", query: ["handle": handle])
                }
                _ = try await transport.post("/closeWindow")
                return Self.ok()
            case Name.clearWebsiteData:
                _ = try await transport.post("/clearWebsiteData")
                return Self.ok()
            case Name.shutdown:
                _ = try await transport.post("/shutdown")
                return Self.ok()
            default:
                return Self.error("Unknown tool: \(params.name)")
            }
        } catch let error as AutomationClientError {
            return Self.error(error.description)
        } catch let error as BrowserLauncherError {
            return Self.error(error.description)
        } catch {
            return Self.error(error.localizedDescription)
        }
    }

    // MARK: - Tool Implementations

    private func launch(appPath argument: String?) async throws -> CallTool.Result {
        guard let appPath = argument ?? configuration.appPath else {
            return Self.error("No app path given. Pass app_path or set DDG_APP_PATH.")
        }
        if let response = try? await transport.get("/contentBlockerReady"), response.message == "true" {
            return .init(content: [.text(text: "Browser already running with automation server on port \(configuration.port).", annotations: nil, _meta: nil)])
        }
        try launcher.launch(appPath: appPath, port: configuration.port, authToken: configuration.authToken)
        try await BrowserReadiness.waitUntilReady(transport: transport, timeout: configuration.launchTimeout)
        return .init(content: [.text(text: "Browser launched from \(appPath); automation server ready on port \(configuration.port).", annotations: nil, _meta: nil)])
    }

    /// The server waits for the active tab to stop loading before answering, so reading URL and title after a
    /// navigation naturally waits for the load to finish.
    private func pageSummary() async throws -> CallTool.Result {
        let url = try await transport.get("/getUrl").message
        let title = try await transport.get("/getTitle").message
        return .init(content: [.text(text: try Self.jsonString(.object(["url": .string(url), "title": .string(title)])), annotations: nil, _meta: nil)])
    }

    // MARK: - Helpers

    static func handle(fromNewWindowResponse message: String) -> String {
        struct NewWindow: Decodable { let handle: String }
        return (try? JSONDecoder().decode(NewWindow.self, from: Data(message.utf8)))?.handle ?? message
    }

    static func numberString(_ value: Value?) -> String {
        guard let value else { return "0" }
        if let double = value.doubleValue { return Self.format(double) }
        if let int = value.intValue { return String(int) }
        return "0"
    }

    private static func format(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }

    static func jsonString(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else { throw AutomationClientError.invalidRequest }
        return string
    }

    static func ok() -> CallTool.Result {
        .init(content: [.text(text: "{\"success\": true}", annotations: nil, _meta: nil)])
    }

    static func error(_ message: String) -> CallTool.Result {
        .init(content: [.text(text: message, annotations: nil, _meta: nil)], isError: true)
    }

    private static func schema(_ properties: [String: Value] = [:], required: [String] = []) -> Value {
        var schema: [String: Value] = ["type": .string("object"), "properties": .object(properties)]
        if !required.isEmpty {
            schema["required"] = .array(required.map { .string($0) })
        }
        return .object(schema)
    }

    private static func string(_ description: String) -> Value {
        .object(["type": .string("string"), "description": .string(description)])
    }

    private static func number(_ description: String) -> Value {
        .object(["type": .string("number"), "description": .string(description)])
    }

    private static func object(_ description: String) -> Value {
        .object(["type": .string("object"), "description": .string(description)])
    }
}
