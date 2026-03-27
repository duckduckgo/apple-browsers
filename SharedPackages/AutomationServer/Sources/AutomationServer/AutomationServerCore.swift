//
//  AutomationServerCore.swift
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
import os.log
#if os(macOS)
import AppKit
#endif

public extension Logger {
    static var automationServer = { Logger(subsystem: Bundle.main.bundleIdentifier ?? "DuckDuckGo", category: "Automation Server") }()
}

public typealias ConnectionResult = Result<String, AutomationServerError>
public typealias ConnectionResultWithPath = (String, ConnectionResult)

/// Actor for managing per-connection request queues to ensure sequential processing
public actor PerConnectionQueue {
    private var isProcessing = false
    private var queue: [Data] = []
    private var buffer = Data() // Buffer for incomplete HTTP requests
    private let maxRequestSize = 1_048_576 // 1MB - must match AutomationServerCore.maxRequestSize

    public init() {}

    public func enqueue(
        content: Data,
        processor: @escaping (Data) async -> ConnectionResultWithPath,
        responder: @escaping (ConnectionResultWithPath) -> Void
    ) async {
        // Append to buffer
        self.buffer.append(content)

        // Check if buffer has exceeded maximum size without forming a complete request
        // This prevents unbounded buffer growth from malformed or excessive input
        if self.buffer.count > self.maxRequestSize {
            Logger.automationServer.error("Buffer exceeded maximum size (\(self.buffer.count) > \(self.maxRequestSize)). Rejecting malformed request.")
            self.buffer.removeAll()
            self.queue.removeAll()
            // Send error response for oversized/malformed request
            responder(("buffer_overflow", .failure(.requestTooLarge)))
            return
        }

        // Extract complete HTTP requests from buffer
        while let completeRequest = extractCompleteRequest() {
            self.queue.append(completeRequest)
        }

        guard !self.isProcessing else { return }
        self.isProcessing = true

        while !self.queue.isEmpty {
            let request = self.queue.removeFirst()
            let connectionResultWithPath = await processor(request)
            responder(connectionResultWithPath)
        }

        self.isProcessing = false
    }

    /// Extracts a complete HTTP request from the buffer if available
    /// Returns nil if the request is incomplete
    private func extractCompleteRequest() -> Data? {
        guard !self.buffer.isEmpty else { return nil }

        // Convert buffer to string for parsing
        guard let bufferString = String(data: self.buffer, encoding: .utf8) else { return nil }

        // Find end of headers (double CRLF or double LF)
        // Must use the EARLIEST delimiter position, not the first type found
        let headerEndMarkers = ["\r\n\r\n", "\n\n"]
        var headerEndIndex: String.Index?
        var earliestPosition: String.Index?

        for marker in headerEndMarkers {
            if let range = bufferString.range(of: marker) {
                let position = range.upperBound
                if earliestPosition == nil || position < earliestPosition! {
                    earliestPosition = position
                    headerEndIndex = position
                }
            }
        }

        guard let endOfHeaders = headerEndIndex else {
            // Headers incomplete, wait for more data
            return nil
        }

        // Extract headers
        let headerSection = String(bufferString[..<endOfHeaders])

        // Parse Content-Length header
        guard let contentLength = parseContentLength(from: headerSection) else {
            return nil
        }

        // Calculate total request size
        // Convert character position to byte count by encoding the header substring as UTF-8
        let headerSubstring = bufferString[..<endOfHeaders]
        let headerBytes = headerSubstring.utf8.count
        let totalRequestSize = headerBytes + contentLength

        // Check if we have the complete request
        guard self.buffer.count >= totalRequestSize else {
            // Request incomplete, wait for more data
            return nil
        }

        // Extract complete request
        let requestData = self.buffer.prefix(totalRequestSize)
        self.buffer.removeFirst(totalRequestSize)

        return requestData
    }

    /// Parses the Content-Length header from the HTTP header section
    /// Returns nil if parsing fails (and clears the buffer as needed)
    private func parseContentLength(from headerSection: String) -> Int? {
        let lines = headerSection.components(separatedBy: CharacterSet.newlines)
        for line in lines {
            let lowercaseLine = line.lowercased()
            if lowercaseLine.hasPrefix("content-length:") {
                let parts = line.components(separatedBy: ":")
                guard parts.count >= 2 else {
                    // Content-Length header present but malformed
                    Logger.automationServer.error("Malformed Content-Length header. Clearing buffer to recover.")
                    self.buffer.removeAll()
                    return nil
                }

                let valueString = parts[1].trimmingCharacters(in: .whitespaces)
                guard let length = Int(valueString) else {
                    // Content-Length value is not a valid integer
                    Logger.automationServer.error("Non-numeric Content-Length value '\(valueString)'. Clearing buffer to recover.")
                    self.buffer.removeAll()
                    return nil
                }

                // Validate Content-Length is within acceptable bounds
                // Prevent negative values (underflow) and excessively large values (overflow/DoS)
                guard length >= 0 && length <= self.maxRequestSize else {
                    // Malformed request with invalid Content-Length, clear buffer to allow subsequent requests
                    Logger.automationServer.error("Invalid Content-Length (\(length)). Clearing buffer to recover.")
                    self.buffer.removeAll()
                    return nil
                }
                return length
            }
        }
        // No Content-Length header found, default to 0
        return 0
    }
}

/// Core automation server implementation that handles HTTP connections and routes requests.
/// Uses a BrowserAutomationProvider for platform-specific browser operations.
@MainActor
public final class AutomationServerCore {
    public let listener: NWListener
    public let provider: BrowserAutomationProvider
    public var connectionQueues: [ObjectIdentifier: PerConnectionQueue] = [:]
    private let authToken: String?
    private let maxRequestSize = 1_048_576 // 1MB

    public init(provider: BrowserAutomationProvider, port: Int?) throws {
        let port = port ?? 8788
        self.provider = provider
        self.authToken = ProcessInfo.processInfo.environment["AUTOMATION_TOKEN"]

        // Validate port is in valid range before UInt16 conversion
        guard port.isValidPort else {
            Logger.automationServer.error("Invalid port number: \(port). Must be in range 1...65535")
            throw AutomationServerError.invalidPort
        }

        Logger.automationServer.info("Starting automation server on port \(port)")

        // Configure listener to bind to localhost only for security
        // Using IPv6 loopback enables dual-stack support for both IPv4 (127.0.0.1) and IPv6 (::1) connections
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv6(.loopback), port: NWEndpoint.Port(integerLiteral: UInt16(port)))

        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                guard let self else { return }
                connection.start(queue: .main)
                self.receive(from: connection)
            }
        }

        listener.start(queue: .main)
        Logger.automationServer.info("Automation server started on port \(port)")
    }

    public func receive(from connection: NWConnection) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: self.maxRequestSize
        ) { (content: Data?, _: NWConnection.ContentContext?, isComplete: Bool, error: NWError?) in
            // Ensure connection queue is cleaned up when request completes or fails
            defer {
                if isComplete || error != nil || connection.state != .ready {
                    self.connectionQueues.removeValue(forKey: ObjectIdentifier(connection))
                }
            }

            guard connection.state == .ready else {
                Logger.automationServer.debug("Receive aborted as connection is no longer ready.")
                return
            }
            Logger.automationServer.debug("Received request - Content: \(String(describing: content)) isComplete: \(isComplete) Error: \(String(describing: error))")

            if let error {
                Logger.automationServer.error("Error in request: \(error)")
                connection.cancel()
                return
            }

            if let content {
                Logger.automationServer.debug("Handling content")
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
                Logger.automationServer.debug("Connection marked complete.")
                // Only cancel immediately if there was no content to process.
                // When content is present, respond() will cancel the connection
                // after successfully sending the response.
                if content == nil {
                    Logger.automationServer.debug("No pending content - cancelling connection.")
                    connection.cancel()
                }
                return
            }

            if connection.state == .ready {
                Logger.automationServer.debug("Handling not complete, continuing receive.")
                Task { @MainActor in
                    self.receive(from: connection)
                }
            } else {
                Logger.automationServer.debug("Connection is no longer ready, stopping receive.")
            }
        }
    }

    public func processContentWhenReady(content: Data) async -> ConnectionResultWithPath {
        let timeout = Date().addingTimeInterval(30) // 30 second timeout
        while provider.isLoading {
            guard Date() < timeout else {
                Logger.automationServer.error("Timeout waiting for content to be ready")
                return ("timeout", .failure(.timeout))
            }
            Logger.automationServer.debug("Still loading, waiting...")
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        }
        return await handleConnection(content)
    }

    public func handleConnection(_ content: Data) async -> ConnectionResultWithPath {
        Logger.automationServer.debug("Handling request")
        let stringContent = String(bytes: content, encoding: .utf8) ?? ""

        if let firstLine = stringContent.components(separatedBy: CharacterSet.newlines).first {
            Logger.automationServer.debug("First line: \(firstLine)")
        }

        // Validate authentication token if configured
        if let expectedToken = authToken {
            let headers = extractHeaders(from: stringContent)
            let authHeader = headers["authorization"] ?? ""
            let expectedValue = "Bearer \(expectedToken)"

            guard authHeader == expectedValue else {
                Logger.automationServer.error("Unauthorized request - invalid or missing auth token")
                return ("unauthorized", .failure(.unauthorized))
            }
        }

        guard let (method, pathString) = extractMethodAndPath(from: stringContent) else {
            return ("unknown", .failure(.unknownMethod))
        }
        Logger.automationServer.debug("Method: \(method) Path: \(pathString)")

        guard let url = URLComponents(string: pathString) else {
            Logger.automationServer.error("Invalid URL: \(pathString)")
            return ("unknown", .failure(.invalidURL))
        }
        return (url.path, await handlePath(url, method: method))
    }

    private func extractMethodAndPath(from httpRequest: String) -> (method: String, path: String)? {
        let pattern = "^(GET|POST) (\\/[^ ]*) HTTP"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: httpRequest, options: [], range: NSRange(httpRequest.startIndex..., in: httpRequest)),
              let methodRange = Range(match.range(at: 1), in: httpRequest),
              let pathRange = Range(match.range(at: 2), in: httpRequest) else {
            return nil
        }
        let method = String(httpRequest[methodRange])
        let path = String(httpRequest[pathRange])
        return (method, path)
    }

    private func extractHeaders(from httpRequest: String) -> [String: String] {
        var headers: [String: String] = [:]

        // Split by double newline to separate headers from body
        // Support both CRLF (\r\n\r\n) and LF (\n\n) delimiters to match extractCompleteRequest
        let headerEndMarkers = ["\r\n\r\n", "\n\n"]
        var headerSection = httpRequest

        for marker in headerEndMarkers {
            if let parts = httpRequest.components(separatedBy: marker).first {
                headerSection = parts
                break
            }
        }

        // Parse each header line
        let lines = headerSection.components(separatedBy: CharacterSet.newlines)
        for line in lines.dropFirst() { // Skip the request line (GET /path HTTP/1.1)
            guard let colonIndex = line.firstIndex(of: ":") else { continue }

            let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        return headers
    }

    public func handlePath(_ url: URLComponents, method: String) async -> ConnectionResult {
        // Route to appropriate handler based on path prefix
        if url.path.hasPrefix("/navigate") || url.path.hasPrefix("/execute") || url.path == "/getUrl" {
            return await handleNavigationPath(url, method: method)
        } else if url.path.contains("Window") {
            return handleWindowPath(url, method: method)
        } else {
            return await handleServerPath(url, method: method)
        }
    }

    private func handleNavigationPath(_ url: URLComponents, method: String) async -> ConnectionResult {
        switch url.path {
        case "/navigate":
            guard method == "GET" || method == "POST" else { return .failure(.methodNotAllowed) }
            return navigate(url: url)
        case "/execute":
            guard method == "POST" else { return .failure(.methodNotAllowed) }
            return await execute(url: url)
        case "/getUrl":
            guard method == "GET" else { return .failure(.methodNotAllowed) }
            return .success(provider.currentURL?.absoluteString ?? "")
        default:
            return .failure(.unknownMethod)
        }
    }

    private func handleWindowPath(_ url: URLComponents, method: String) -> ConnectionResult {
        switch url.path {
        case "/getWindowHandles":
            guard method == "GET" else { return .failure(.methodNotAllowed) }
            return getWindowHandles(url: url)
        case "/closeWindow":
            guard method == "POST" else { return .failure(.methodNotAllowed) }
            return closeWindow(url: url)
        case "/switchToWindow":
            guard method == "POST" else { return .failure(.methodNotAllowed) }
            return switchToWindow(url: url)
        case "/newWindow":
            guard method == "POST" else { return .failure(.methodNotAllowed) }
            return newWindow(url: url)
        case "/getWindowHandle":
            guard method == "GET" else { return .failure(.methodNotAllowed) }
            return getWindowHandle(url: url)
        default:
            return .failure(.unknownMethod)
        }
    }

    private func handleServerPath(_ url: URLComponents, method: String) async -> ConnectionResult {
        switch url.path {
        case "/shutdown":
            guard method == "POST" else { return .failure(.methodNotAllowed) }
            return shutdown()
        case "/screenshot":
            guard method == "GET" || method == "POST" else { return .failure(.methodNotAllowed) }
            return await takeScreenshot(url: url)
        case "/contentBlockerReady":
            guard method == "GET" else { return .failure(.methodNotAllowed) }
            return contentBlockerReady()
        default:
            return .failure(.unknownMethod)
        }
    }

    /// Cleanly shut down the automation server and terminate the app.
    /// This allows the webdriver to close the app without triggering a crash dialog.
    public func shutdown() -> ConnectionResult {
        Logger.automationServer.info("Shutdown requested - stopping automation server and terminating app")

        // Cancel the listener to stop accepting new connections
        listener.cancel()

        // Clear connection queues
        connectionQueues.removeAll()

        Logger.automationServer.info("Automation server shut down, scheduling app termination")

        // Schedule app termination after a short delay to allow this response to be sent
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Logger.automationServer.info("Terminating app")
            #if os(macOS)
            NSApplication.shared.terminate(nil)
            #else
            // iOS doesn't support programmatic termination
            // Use exit(0) as last resort for testing scenarios
            exit(0)
            #endif
        }

        return .success("shutdown")
    }

    // MARK: - Route Handlers

    public func navigate(url: URLComponents) -> ConnectionResult {
        let navigateUrlString = getQueryStringParameter(url: url, param: "url") ?? ""
        guard let navigateUrl = URL(string: navigateUrlString) else {
            return .failure(.invalidURL)
        }
        guard provider.navigate(to: navigateUrl) else {
            return .failure(.noWindow)
        }
        return .success("done")
    }

    public func execute(url: URLComponents) async -> ConnectionResult {
        let script = getQueryStringParameter(url: url, param: "script") ?? ""
        var args: [String: Any] = [:]

        if let argsString = getQueryStringParameter(url: url, param: "args") {
            guard let argsData = argsString.data(using: .utf8) else {
                return .failure(.jsonEncodingFailed)
            }
            do {
                let jsonDecoder = JSONDecoder()
                if let decodedArgs = try JSONSerialization.jsonObject(with: argsData, options: []) as? [String: Any] {
                    args = decodedArgs
                } else {
                    Logger.automationServer.error("Failed to decode args: not a dictionary")
                    return .failure(.jsonEncodingFailed)
                }
            } catch {
                Logger.automationServer.error("Failed to decode args: \(error)")
                return .failure(.jsonEncodingFailed)
            }
        }
        return await executeScript(script, args: args)
    }

    public func getWindowHandle(url: URLComponents) -> ConnectionResult {
        guard let handle = provider.currentTabHandle else {
            return .failure(.noWindow)
        }
        return .success(handle)
    }

    public func getWindowHandles(url: URLComponents) -> ConnectionResult {
        let handles = provider.getAllTabHandles()

        if let jsonData = try? JSONEncoder().encode(handles),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return .success(jsonString)
        } else {
            return .failure(.jsonEncodingFailed)
        }
    }

    public func closeWindow(url: URLComponents) -> ConnectionResult {
        guard provider.currentTabHandle != nil else {
            return .failure(.noWindow)
        }
        provider.closeCurrentTab()
        return .success("done")
    }

    public func switchToWindow(url: URLComponents) -> ConnectionResult {
        guard let handleString = getQueryStringParameter(url: url, param: "handle") else {
            return .failure(.invalidWindowHandle)
        }
        Logger.automationServer.debug("Switch to window \(handleString)")

        if provider.switchToTab(handle: handleString) {
            return .success("done")
        }
        return .failure(.tabNotFound)
    }

    public func newWindow(url: URLComponents) -> ConnectionResult {
        guard let handle = provider.newTab() else {
            return .failure(.noWindow)
        }

        let response: [String: String] = ["handle": handle, "type": "tab"]
        if let jsonData = try? JSONEncoder().encode(response),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return .success(jsonString)
        } else {
            return .failure(.jsonEncodingFailed)
        }
    }

    public func takeScreenshot(url: URLComponents) async -> ConnectionResult {
        // Parse optional rect parameter for element screenshots
        var rect: CGRect?
        if let rectString = getQueryStringParameter(url: url, param: "rect"),
           let rectData = rectString.data(using: .utf8),
           let rectDict = try? JSONDecoder().decode([String: CGFloat].self, from: rectData),
           let x = rectDict["x"],
           let y = rectDict["y"],
           let width = rectDict["width"],
           let height = rectDict["height"] {
            rect = CGRect(x: x, y: y, width: width, height: height)
        }

        guard let screenshotData = await provider.takeScreenshot(rect: rect) else {
            return .failure(.screenshotFailed)
        }
        return .success(screenshotData.base64EncodedString())
    }

    /// Check if the content blocker rules have been compiled and are ready
    /// WebDriver should wait for this before considering the browser ready for testing
    public func contentBlockerReady() -> ConnectionResult {
        let isReady = provider.isContentBlockerReady
        Logger.automationServer.debug("Content blocker ready: \(isReady)")
        return .success(isReady ? "true" : "false")
    }

    public func executeScript(_ script: String, args: [String: Any]) async -> ConnectionResult {
        Logger.automationServer.debug("Script: \(script), Args: \(args)")

        let result = await provider.executeScript(script, args: args)

        switch result {
        case .success(let value):
            Logger.automationServer.debug("Have result to execute script: \(String(describing: value))")
            let jsonString = encodeToJsonString(value)
            return .success(jsonString)
        case .failure(let error):
            Logger.automationServer.error("Error executing script: \(error)")
            return .failure(.scriptExecutionFailed)
        }
    }

    // MARK: - Response Handling

    public func responseToString(_ connectionResultWithPath: ConnectionResultWithPath) -> String {
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
        let statusText = errorCode == 200 ? "OK" : "Bad Request"
        // HTTP requires CRLF (\r\n) line endings and \r\n\r\n to terminate headers
        return "HTTP/1.1 \(errorCode) \(statusText)\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n\(responseString)"
    }

    public func respond(on connection: NWConnection, connectionResultWithPath: ConnectionResultWithPath) {
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

    // MARK: - Helpers

    public func getQueryStringParameter(url: URLComponents, param: String) -> String? {
        return url.queryItems?.first(where: { $0.name == param })?.value
    }
}
