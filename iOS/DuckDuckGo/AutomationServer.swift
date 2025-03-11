//
//  AutomationServer.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Network

extension Logger {
    static var automationServer = { Logger(subsystem: Bundle.main.bundleIdentifier ?? "DuckDuckGo", category: "Automation Server") }()
}

struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        self.encode = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}

enum AutomationServerError: Error {
    case noWindow
    case invalidWindowHandle
    case tabNotFound
    case jsonEncodingFailed
    case unsupportedOSVersion
    case unknownMethod
    case invalidURL
}

typealias ConnectionResult = Result<String, AutomationServerError>
typealias ConnectionResultWithPath = (String, ConnectionResult)

actor PerConnectionQueue {
    private var isProcessing = false
    private var queue: [Data] = []

    func enqueue(
        content: Data,
        processor: @escaping (Data) async -> ConnectionResultWithPath,
        responder: @escaping (ConnectionResultWithPath) -> Void
    ) async {
        queue.append(content)

        guard !isProcessing else { return } // Prevent duplicate loops
        isProcessing = true

        while !queue.isEmpty {
            let request = queue.removeFirst()
            let connectionResultWithPath = await processor(request) // Process request
            responder(connectionResultWithPath)
        }

        isProcessing = false
    }
}

func encodeToJsonString(_ value: Any?) -> String {
    do {
        guard let value else {
            return "null"
        }
        if let encodableValue = value as? Encodable {
            let jsonData = try JSONEncoder().encode(AnyEncodable(encodableValue))
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } else if JSONSerialization.isValidJSONObject(value) {
            let jsonData = try JSONSerialization.data(withJSONObject: value, options: .prettyPrinted)
            return String(data: jsonData, encoding: .utf8) ?? "{}"
        } else {
            Logger.automationServer.error("Have value that can't be encoded: \(String(describing: value))")
            return "{\"error\": \"Value is not a valid JSON object\"}"
        }
    } catch {
        Logger.automationServer.error("Failed to encode: \(String(describing: value))")
        return "{\"error\": \"JSON encoding failed: \(error)\"}"
    }
}

@MainActor
final class AutomationServer {
    let listener: NWListener
    let main: MainViewController
    // Store queues per connection
    var connectionQueues: [ObjectIdentifier: PerConnectionQueue] = [:]

    init(main: MainViewController, port: Int?) {
        let port = port ?? 8788
        self.main = main
        Logger.automationServer.info("Starting automation server on port \(port)")
        do {
            listener = try NWListener(using: .tcp, on: NWEndpoint.Port(integerLiteral: UInt16(port)))
        } catch {
            Logger.automationServer.error("Failed to start listener: \(error)")
            fatalError("Failed to start automation listener: \(error)")
        }
        listener.newConnectionHandler = { connection in
            Task { @MainActor in
                connection.start(queue: .main)
                self.receive(from: connection)
            }
        }

        listener.start(queue: .main)
        // Output server started
        Logger.automationServer.info("Automation server started on port \(port)")
    }
    
    func receive(from connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: connection.maximumDatagramSize
        ) { (content: Data?, _: NWConnection.ContentContext?, isComplete: Bool, error: NWError?) in
            guard connection.state == .ready else {
                Logger.automationServer.info("Receive aborted as connection is no longer ready.")
                return
            }
            Logger.automationServer.info("Received request - Content: \(String(describing: content)) isComplete: \(isComplete) Error: \(String(describing: error))")

            if let error {
                Logger.automationServer.error("Error in request: \(error)")
                return
            }

            if let content {
                Logger.automationServer.info("Handling content")
                let queue = self.connectionQueues[ObjectIdentifier(connection)] ?? PerConnectionQueue()
                self.connectionQueues[ObjectIdentifier(connection)] = queue
                Task { @MainActor in
                    await queue.enqueue(
                    content: content,
                    processor: { data in
                        return await self.processContentWhenReady(content: data)
                    },
                    responder: { connectionResultWithPath in
                        self.respond(on: connection, connectionResultWithPath: connectionResultWithPath)
                    })
                }
            }
            if isComplete {
                Logger.automationServer.info("Connection marked complete. Cancelling connection.")
                connection.cancel()
                return
            }

            if connection.state == .ready {
                Logger.automationServer.info("Handling not complete, continuing receive.")
                Task { @MainActor in
                    self.receive(from: connection)
                }
            } else {
                Logger.automationServer.info("Connection is no longer ready, stopping receive.")
            }
        }
    }

    func processContentWhenReady(content: Data) async -> ConnectionResultWithPath {
        // Check if loading
        while self.main.currentTab?.isLoading ?? false {
            Logger.automationServer.info("Still loading, waiting...")
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        }

        // Proceed when loading is complete
        return await self.handleConnection(content)
    }
    
    func getQueryStringParameter(url: URLComponents, param: String) -> String? {
        return url.queryItems?.first(where: { $0.name == param })?.value
    }

    func handleConnection(_ content: Data) async -> (String, ConnectionResult) {
        Logger.automationServer.info("Handling request:")
        let stringContent = String(bytes: content, encoding: .utf8) ?? ""
        // Log first line of string:
        if let firstLine = stringContent.components(separatedBy: CharacterSet.newlines).first {
            Logger.automationServer.info("First line: \(firstLine)")
        }

        // Ensure support for regex
        guard #available(iOS 16.0, *) else {
            return ("unknown", .failure(.unsupportedOSVersion))
        }

        // Get url parameter from path
        // GET / HTTP/1.1
        let path = /^(GET|POST) (\/[^ ]*) HTTP/
        guard let match = stringContent.firstMatch(of: path) else {
            return ("unknown", .failure(.unknownMethod))
        }
        Logger.automationServer.info("Path: \(match.2)")
        // Convert the path into a URL object
        guard let url = URLComponents(string: String(match.2)) else {
            Logger.automationServer.error("Invalid URL: \(match.2)")
            return ("unknown", .failure(.invalidURL))
        }
        return (url.path, await handlePath(url))
    }

    func handlePath(_ url: URLComponents) async -> ConnectionResult {
        return switch url.path {
        case "/navigate":
            self.navigate(url: url)
        case "/execute":
            await self.execute(url: url)
        case "/getUrl":
            .success(self.main.currentTab?.webView.url?.absoluteString ?? "")
        case "/getWindowHandles":
            self.getWindowHandles(url: url)
        case "/closeWindow":
            self.closeWindow(url: url)
        case "/switchToWindow":
            self.switchToWindow(url: url)
        case "/newWindow":
            self.newWindow(url: url)
        case "/getWindowHandle":
            self.getWindowHandle(url: url)
        default:
            .failure(.unknownMethod)
        }
    }

    func navigate(url: URLComponents) -> ConnectionResult {
        let navigateUrlString = getQueryStringParameter(url: url, param: "url") ?? ""
        let navigateUrl = URL(string: navigateUrlString)!
        self.main.loadUrl(navigateUrl)
        return .success("done")
    }

    func execute(url: URLComponents) async -> ConnectionResult {
        let script = getQueryStringParameter(url: url, param: "script") ?? ""
        var args: [String: String] = [:]
        // json decode args if present
        if let argsString = getQueryStringParameter(url: url, param: "args") {
            guard let argsData = argsString.data(using: .utf8) else {
                return .failure(.jsonEncodingFailed)
            }
            do {
                let jsonDecoder = JSONDecoder()
                args = try jsonDecoder.decode([String: String].self, from: argsData)
            } catch {
                Logger.automationServer.error("Failed to decode args: \(error)")
                return .failure(.jsonEncodingFailed)
            }
        }
        return await self.executeScript(script, args: args)
    }

    func getWindowHandle(url: URLComponents) -> ConnectionResult {
        let handle = self.main.currentTab
        guard let handle else {
            return .failure(.noWindow)
        }
        return .success(handle.tabModel.uid)
    }

    func getWindowHandles(url: URLComponents) -> ConnectionResult {
        let handles = self.main.tabManager.model.tabs.map({ tab in
            let tabView = self.main.tabManager.controller(for: tab)!
            return tabView.tabModel.uid
        })

        if let jsonData = try? JSONEncoder().encode(handles),
           let jsonString = String(data: jsonData, encoding: .utf8) {
           return .success(jsonString)
        } else {
            return .failure(.jsonEncodingFailed)
        }
    }

    func closeWindow(url: URLComponents) -> ConnectionResult {
        self.main.closeTab(self.main.currentTab!.tabModel)
        return .success("done")
    }

    func switchToWindow(url: URLComponents) -> ConnectionResult {
        guard let handleString = getQueryStringParameter(url: url, param: "handle") else {
            return .failure(.invalidWindowHandle)
        }
        Logger.automationServer.info("Switch to window \(handleString)")
        if let tabIndex = self.main.tabManager.model.tabs.firstIndex(where: { tab in
            guard let tabView = self.main.tabManager.controller(for: tab) else {
                return false
            }
            return tabView.tabModel.uid == handleString
        }) {
            Logger.automationServer.info("found tab \(tabIndex)")
            _ = self.main.tabManager.select(tabAt: tabIndex)
            return .success("done")
        } else {
            return .failure(.noWindow)
        }
    }

    func newWindow(url: URLComponents) -> ConnectionResult {
        self.main.newTab()
        let handle = self.main.tabManager.current(createIfNeeded: true)
        guard let handle else {
            return .failure(.noWindow)
        }
        // Response {handle: "", type: "tab"}
        let response: [String: String] = ["handle": handle.tabModel.uid, "type": "tab"]
        if let jsonData = try? JSONEncoder().encode(response),
        let jsonString = String(data: jsonData, encoding: .utf8) {
            return .success(jsonString)
        } else {
            return .failure(.jsonEncodingFailed)
        }
    }

    func executeScript(_ script: String, args: [String: Any]) async -> ConnectionResult {
        Logger.automationServer.info("Script: \(script), Args: \(args)")
        Logger.automationServer.info("Environment Variables: \(ProcessInfo.processInfo.environment)")
        let result = await main.executeScript(script, args: args)
        Logger.automationServer.info("Have result to execute script: \(String(describing: result))")
        guard let result else {
            return .failure(.unknownMethod)
        }
        switch result {
        case .failure(let error):
            Logger.automationServer.error("Error executing script: \(error)")
            return .failure(.unknownMethod)
        case .success(let value):
            // Try to encode the value to JSON
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            Logger.automationServer.info("Have success value to execute script: \(String(describing: value))")
            
            let jsonString = encodeToJsonString(value)
            return .success(jsonString)
        }
    }

    func responseToString(_ connectionResultWithPath: ConnectionResultWithPath) -> String {
        let (requestPath, responseData) = connectionResultWithPath
        struct Response: Codable {
            var message: String
            var requestPath: String
        }
        var errorCode = 200
        let responseStruct: Response
        switch responseData {
        case .success(let result):
            responseStruct = Response(message: result, requestPath: requestPath)
        case .failure(let error):
            errorCode = 400
            Logger.automationServer.error("Connection Handling Error: \(error) path: \(requestPath)")
            responseStruct = Response(message: encodeToJsonString(["error": error.localizedDescription]), requestPath: requestPath)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        var responseString = ""
        do {
            let data = try encoder.encode(responseStruct)
            responseString = String(data: data, encoding: .utf8) ?? ""
        } catch {
            Logger.automationServer.error("Got error encoding JSON: \(error)")
        }
        let responseHeader = """
        HTTP/1.1 \(errorCode) OK
        Content-Type: application/json
        Connection: close
        
        """
        return responseHeader + "\r\n" + responseString
    }
    
    func respond(on connection: NWConnection, connectionResultWithPath: ConnectionResultWithPath) {
        let (requestPath, responseData) = connectionResultWithPath
        let responseString = responseToString(connectionResultWithPath)
        connection.send(
            content: responseString.data(using: .utf8),
            completion: .contentProcessed({ error in
                if let error = error {
                    Logger.automationServer.error("Error sending response: \(error)")
                }
                connection.cancel()
            })
        )
    }
}
