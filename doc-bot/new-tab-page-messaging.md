---
alwaysApply: false
title: "New Tab Page Messaging & JSON-RPC Implementation"
description: "JSON-RPC messaging patterns and content-scope-scripts integration for New Tab Page"
keywords: ["macOS only","NTP messaging", "JSON-RPC", "content-scope-scripts", "user script communication", "WebKit messaging", "message handlers", "NewTabPageUserScript", "WKScriptMessageHandler"]
---

# NTP Messaging Architecture

## JSON-RPC 2.0 Implementation

The New Tab Page uses JSON-RPC 2.0 specification for communication between JavaScript and native code.

### Message Format
```swift
// ✅ CORRECT - JSON-RPC message structure
struct JSONRPCMessage: Codable {
    let jsonrpc: String = "2.0"
    let method: String
    let params: [String: Any]?
    let id: Int?
}

struct JSONRPCResponse: Codable {
    let jsonrpc: String = "2.0"
    let result: Any?
    let error: JSONRPCError?
    let id: Int
}

struct JSONRPCError: Codable {
    let code: Int
    let message: String
    let data: Any?
}
```

### WebKit Message Handler Setup
```swift
// ✅ CORRECT - Message handler registration
final class NewTabPageUserContentController: WKUserContentController {
    func setupMessageHandlers() {
        // Single message handler for all NTP communication
        addScriptMessageHandler(
            NewTabPageUserScript.shared,
            name: "newTabPageMessage"
        )
    }
}

// ✅ CORRECT - Message handling implementation
extension NewTabPageUserScript: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let method = body["method"] as? String,
              let id = body["id"] as? Int else {
            return
        }
        
        Task {
            do {
                let result = try await handleMethod(method, params: body["params"])
                sendResponse(result: result, id: id, to: message.webView)
            } catch {
                sendError(error, id: id, to: message.webView)
            }
        }
    }
}
```

## Content-Scope-Scripts Integration

### Script Injection
```swift
// ✅ CORRECT - Content scope script injection
final class NewTabPageUserContentController {
    func injectContentScopeScripts() {
        // Load bundled content-scope-scripts
        guard let scriptURL = Bundle.main.url(
            forResource: "newTabPage",
            withExtension: "js",
            subdirectory: "content-scope-scripts"
        ) else { return }
        
        let script = try String(contentsOf: scriptURL)
        let userScript = WKUserScript(
            source: script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        
        addUserScript(userScript)
    }
}
```

### Frontend API Exposure
```javascript
// ✅ CORRECT - Frontend API pattern (from content-scope-scripts)
window.newTabPage = {
    widgets: {
        favorites: {
            getData: () => sendMessage('favorites_getData'),
            add: (url) => sendMessage('favorites_add', { url }),
            delete: (id) => sendMessage('favorites_delete', { id }),
            reorder: (ids) => sendMessage('favorites_reorder', { ids })
        },
        privacyStats: {
            getData: () => sendMessage('privacyStats_getData'),
            showDetails: () => sendMessage('privacyStats_showDetails')
        }
        // ... other widgets
    }
};

function sendMessage(method, params = {}) {
    return new Promise((resolve, reject) => {
        const id = generateId();
        pendingRequests[id] = { resolve, reject };
        
        webkit.messageHandlers.newTabPageMessage.postMessage({
            jsonrpc: '2.0',
            method,
            params,
            id
        });
    });
}
```

## Message Routing

### Client Registration
```swift
// ✅ CORRECT - Dynamic client registration
final class NewTabPageUserScript {
    private var clients: [String: any NewTabPageClient] = [:]
    
    func registerClient<T: NewTabPageClient>(
        _ client: T,
        for prefix: String
    ) {
        clients[prefix] = client
    }
    
    private func handleMethod(
        _ method: String,
        params: [String: Any]?
    ) async throws -> Any {
        // Extract prefix from method (e.g., "favorites" from "favorites_getData")
        let prefix = method.split(separator: "_").first.map(String.init) ?? ""
        
        guard let client = clients[prefix] else {
            throw JSONRPCError(
                code: -32601,
                message: "Method not found",
                data: nil
            )
        }
        
        let message = Message(name: method, params: params ?? [:])
        return try await client.handle(message: message)
    }
}
```

### Response Handling
```swift
// ✅ CORRECT - Async response sending
extension NewTabPageUserScript {
    private func sendResponse(
        result: Any,
        id: Int,
        to webView: WKWebView?
    ) {
        let response = [
            "jsonrpc": "2.0",
            "result": result,
            "id": id
        ] as [String: Any]
        
        let jsonData = try? JSONSerialization.data(withJSONObject: response)
        let jsonString = String(data: jsonData!, encoding: .utf8)!
        
        webView?.evaluateJavaScript(
            "window.newTabPage._handleResponse(\(jsonString))"
        )
    }
    
    private func sendError(
        _ error: Error,
        id: Int,
        to webView: WKWebView?
    ) {
        let errorResponse = [
            "jsonrpc": "2.0",
            "error": [
                "code": -32603,
                "message": error.localizedDescription
            ],
            "id": id
        ] as [String: Any]
        
        let jsonData = try? JSONSerialization.data(withJSONObject: errorResponse)
        let jsonString = String(data: jsonData!, encoding: .utf8)!
        
        webView?.evaluateJavaScript(
            "window.newTabPage._handleResponse(\(jsonString))"
        )
    }
}
```

## Message Types & Patterns

### Widget Data Requests
```swift
// ✅ CORRECT - Standard data request pattern
// Method naming: widgetName_action
"favorites_getData"      // Get favorites list
"privacyStats_getData"   // Get privacy statistics
"recentActivity_getData" // Get recent activity

// Response: Widget-specific data model
```

### Widget Actions
```swift
// ✅ CORRECT - Action with parameters
// Method naming: widgetName_action
"favorites_add"          // params: { url: string }
"favorites_delete"       // params: { id: string }
"favorites_reorder"      // params: { ids: string[] }
"rmf_dismiss"           // params: { id: string }

// Response: Updated widget data or null
```

### Configuration Updates
```swift
// ✅ CORRECT - Configuration messaging
"configuration_getValue"     // params: { key: string }
"configuration_setValue"     // params: { key: string, value: any }
"configuration_getAll"       // params: {}

// Response: Configuration value(s)
```

## Error Handling

### Standard JSON-RPC Error Codes
```swift
enum JSONRPCErrorCode: Int {
    case parseError = -32700
    case invalidRequest = -32600
    case methodNotFound = -32601
    case invalidParams = -32602
    case internalError = -32603
    
    // Application-specific errors
    case widgetNotAvailable = -32000
    case actionFailed = -32001
    case unauthorized = -32002
}

// ✅ CORRECT - Error creation
extension JSONRPCError {
    static func methodNotFound(_ method: String) -> Self {
        JSONRPCError(
            code: JSONRPCErrorCode.methodNotFound.rawValue,
            message: "The method '\(method)' was not found",
            data: ["method": method]
        )
    }
}
```

## Testing Message Communication

### Mock Message Handler
```swift
// ✅ CORRECT - Test message handler
final class MockScriptMessageHandler: NSObject, WKScriptMessageHandler {
    var capturedMessages: [(method: String, params: [String: Any]?, id: Int)] = []
    var responseHandler: ((String, [String: Any]?) -> Any)?
    
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any],
              let method = body["method"] as? String,
              let id = body["id"] as? Int else {
            return
        }
        
        let params = body["params"] as? [String: Any]
        capturedMessages.append((method, params, id))
        
        if let handler = responseHandler {
            let result = handler(method, params)
            // Send response back...
        }
    }
}
```

### Integration Testing
```swift
// ✅ CORRECT - Full messaging test
func testFavoritesMessaging() async throws {
    // Setup
    let webView = WKWebView()
    let userScript = NewTabPageUserScript()
    let favoritesClient = MockFavoritesClient()
    
    userScript.registerClient(favoritesClient, for: "favorites")
    
    // Simulate frontend message
    let message = WKScriptMessage(
        body: [
            "jsonrpc": "2.0",
            "method": "favorites_getData",
            "id": 1
        ],
        webView: webView
    )
    
    // Handle message
    userScript.userContentController(
        WKUserContentController(),
        didReceive: message
    )
    
    // Verify
    XCTAssertEqual(favoritesClient.handleCallCount, 1)
    // Verify response was sent back to webView
}
```

## Performance Considerations

### Message Batching
```swift
// ✅ CORRECT - Batch multiple requests
struct BatchRequest: Codable {
    let requests: [JSONRPCMessage]
}

// Frontend can send multiple requests at once
webkit.messageHandlers.newTabPageMessage.postMessage({
    batch: true,
    requests: [
        { jsonrpc: "2.0", method: "favorites_getData", id: 1 },
        { jsonrpc: "2.0", method: "privacyStats_getData", id: 2 }
    ]
});
```

### Message Size Limits
```swift
// ✅ CORRECT - Handle large data sets
extension NewTabPageClient {
    func handleLargeDataSet<T>(_ data: [T], maxSize: Int = 1000) -> [T] {
        if data.count > maxSize {
            // Return paginated or truncated data
            return Array(data.prefix(maxSize))
        }
        return data
    }
}
```