//
//  BrowserToolsWireFormatTests.swift
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

import XCTest
@testable import AIChat

/// Pins the browser-tools wire format: these shapes are shared with Windows and read by the Duck.ai
/// front end, so changing one changes an agreed contract.
final class BrowserToolsWireFormatTests: XCTestCase {

    // MARK: - initialize

    func testWhenInitializeResultIsEncodedThenItAdvertisesToolsWithListChanged() throws {
        let result = MCPInitializeResult(serverName: "macos-browser", serverVersion: "1.2.3")

        try assertEncodes(result, to: """
        {
          "protocolVersion": "2025-11-25",
          "capabilities": { "tools": { "listChanged": true } },
          "serverInfo": { "name": "macos-browser", "version": "1.2.3" }
        }
        """)
    }

    func testWhenServerVersionIsMissingThenTheKeyIsOmitted() throws {
        let result = MCPInitializeResult(serverName: "macos-browser", serverVersion: nil)

        try assertEncodes(result, to: """
        {
          "protocolVersion": "2025-11-25",
          "capabilities": { "tools": { "listChanged": true } },
          "serverInfo": { "name": "macos-browser" }
        }
        """)
    }

    func testWhenClientDeclaresElicitationFormObjectThenItIsSupported() throws {
        let request = try decodeInitializeRequest("""
        {
          "protocolVersion": "2025-11-25",
          "capabilities": { "elicitation": { "form": {} } },
          "clientInfo": { "name": "duck.ai", "version": "1" }
        }
        """)

        XCTAssertTrue(request.supportsElicitationForm)
        XCTAssertEqual(request.protocolVersion, "2025-11-25")
        XCTAssertEqual(request.clientInfo?.name, "duck.ai")
    }

    /// Only an object declares the capability — a truthy value does not.
    func testWhenElicitationFormIsNotAnObjectThenItIsNotSupported() throws {
        for form in ["true", "\"form\"", "null", "[]"] {
            let request = try decodeInitializeRequest("""
            { "protocolVersion": "2025-11-25", "capabilities": { "elicitation": { "form": \(form) } } }
            """)

            XCTAssertFalse(request.supportsElicitationForm, "expected form: \(form) not to declare support")
        }
    }

    func testWhenCapabilitiesAreAbsentOrMalformedThenTheRequestStillDecodes() throws {
        let payloads = [
            #"{ "protocolVersion": "2025-11-25" }"#,
            #"{ "protocolVersion": "2025-11-25", "capabilities": {} }"#,
            #"{ "protocolVersion": "2025-11-25", "capabilities": { "elicitation": "nonsense" } }"#,
            #"{ }"#
        ]

        for payload in payloads {
            let request = try decodeInitializeRequest(payload)
            XCTAssertFalse(request.supportsElicitationForm, "expected \(payload) not to declare support")
        }
    }

    // MARK: - tools/list

    func testWhenToolsAreListedThenDescriptorsAreEmittedVerbatim() throws {
        let descriptor = BrowserToolDescriptor(
            name: "switchToTab",
            title: "Switch to tab",
            description: "Switch to an open tab in the current window by tabId from listOpenTabs.",
            inputSchema: ["type": "object", "properties": ["tabId": ["type": "string"]], "required": ["tabId"]],
            outputSchema: ["type": "object"],
            annotations: MCPToolAnnotations(readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        )

        try assertEncodes(BrowserToolsListResponse(tools: [descriptor]), to: """
        {
          "tools": [
            {
              "name": "switchToTab",
              "title": "Switch to tab",
              "description": "Switch to an open tab in the current window by tabId from listOpenTabs.",
              "inputSchema": { "type": "object", "properties": { "tabId": { "type": "string" } }, "required": ["tabId"] },
              "outputSchema": { "type": "object" },
              "annotations": {
                "readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false
              }
            }
          ]
        }
        """)
    }

    /// A listing failure is a top-level token, unlike an invocation failure.
    func testWhenSessionIsNotInitializedThenListingReportsATopLevelError() throws {
        try assertEncodes(BrowserToolsListResponse(failure: .notInitialized), to: """
        { "tools": [], "error": "not_initialized" }
        """)
    }

    func testWhenListingSucceedsThenNoErrorKeyIsEmitted() throws {
        let encoded = try encoded(BrowserToolsListResponse(tools: []))

        XCTAssertNil(encoded["error"], "a successful listing must not carry an error token")
    }

    // MARK: - tools/call

    func testWhenToolSucceedsThenResultCarriesStructuredContentAndItsTextForm() throws {
        let response = InvokeBrowserToolResponse(callId: "call_abc",
                                                 result: .success(["tabId": "abc", "title": "Example"]))

        try assertEncodes(response, to: """
        {
          "callId": "call_abc",
          "status": "ok",
          "result": {
            "content": [{ "type": "text", "text": "{\\"tabId\\":\\"abc\\",\\"title\\":\\"Example\\"}" }],
            "isError": false,
            "structuredContent": { "tabId": "abc", "title": "Example" }
          }
        }
        """)
    }

    /// Tool failure is `isError` inside the MCP result. The outer status describes the round trip
    /// only, so it stays `ok` — a failing tool is not a transport error.
    func testWhenToolFailsThenStatusIsStillOkAndTheTokenIsTheTextContent() throws {
        let response = InvokeBrowserToolResponse(callId: "call_abc", result: .failure(.denied))

        try assertEncodes(response, to: """
        {
          "callId": "call_abc",
          "status": "ok",
          "result": {
            "content": [{ "type": "text", "text": "denied" }],
            "isError": true
          }
        }
        """)
    }

    func testWhenToolFailsThenStructuredContentIsOmitted() throws {
        let encoded = try encoded(InvokeBrowserToolResponse(callId: "c", result: .failure(.unavailable)))

        XCTAssertNil(encoded["result"]?["structuredContent"])
    }

    func testWhenCallIsRequestedThenNameCallIdAndArgumentsAreRead() throws {
        let data = try XCTUnwrap(#"{ "name": "listOpenTabs", "callId": "c1", "arguments": { "limit": 20 } }"#.data(using: .utf8))

        let request = try JSONDecoder().decode(InvokeBrowserToolRequest.self, from: data)

        XCTAssertEqual(request.name, "listOpenTabs")
        XCTAssertEqual(request.callId, "c1")
        XCTAssertEqual(request.arguments?["limit"]?.intValue, 20)
    }

    // MARK: - Failure tokens

    /// The front end branches on these strings, so their spelling is part of the contract.
    func testFailureTokenSpellings() {
        XCTAssertEqual(BrowserToolFailure.invalidArguments.rawValue, "invalid_arguments")
        XCTAssertEqual(BrowserToolFailure.notFound.rawValue, "not_found")
        XCTAssertEqual(BrowserToolFailure.unavailable.rawValue, "unavailable")
        XCTAssertEqual(BrowserToolFailure.denied.rawValue, "denied")
        XCTAssertEqual(BrowserToolFailure.cancelled.rawValue, "cancelled")
        XCTAssertEqual(BrowserToolFailure.elicitationUnsupported.rawValue, "elicitation_unsupported")
        XCTAssertEqual(BrowserToolFailure.invalidPermissionChoice.rawValue, "invalid_permission_choice")
        XCTAssertEqual(BrowserToolFailure.notInitialized.rawValue, "not_initialized")
        XCTAssertEqual(BrowserToolFailure.invalidRequest.rawValue, "invalid_request")
    }

    // MARK: - Message names

    /// These are the literal strings on the wire; the Swift case names are incidental.
    func testMCPMessageNames() {
        XCTAssertEqual(AIChatUserScriptMessages.initialize.rawValue, "initialize")
        XCTAssertEqual(AIChatUserScriptMessages.notificationsInitialized.rawValue, "notifications/initialized")
        XCTAssertEqual(AIChatUserScriptMessages.toolsList.rawValue, "tools/list")
        XCTAssertEqual(AIChatUserScriptMessages.toolsCall.rawValue, "tools/call")
    }

    // MARK: -

    private func encoded<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Compares parsed JSON rather than raw strings, so key ordering and whitespace do not make
    /// the assertion brittle.
    private func assertEncodes<T: Encodable>(_ value: T,
                                             to expected: String,
                                             file: StaticString = #filePath,
                                             line: UInt = #line) throws {
        XCTAssertEqual(try encoded(value), try JSONValue(jsonString: expected), file: file, line: line)
    }

    private func decodeInitializeRequest(_ json: String) throws -> MCPInitializeRequest {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try JSONDecoder().decode(MCPInitializeRequest.self, from: data)
    }
}
