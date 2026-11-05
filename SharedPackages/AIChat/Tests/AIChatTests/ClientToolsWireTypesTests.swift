//
//  ClientToolsWireTypesTests.swift
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

import AIChat
import Foundation
import Testing

@available(iOS 16, macOS 13, *)
struct ClientToolsWireTypesTests {

    @Test(.timeLimit(.minutes(1)))
    func capabilityDecodingAcceptsAllowedCharactersAndBoundaryValues() throws {
        let names = ["a", "AZaz09_.:-", String(repeating: "a", count: 64)]
        for name in names {
            for version in [1, 9_007_199_254_740_991] {
                let capability = try decode(ClientToolCapability.self, from: [
                    "name": .string(name),
                    "version": .int(version)
                ])
                #expect(capability.name == name)
                #expect(capability.version == version)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        "", String(repeating: "a", count: 65), "list tabs", "tab/name", "tabs\n", "é", "tab😀"
    ])
    func capabilityDecodingRejectsInvalidNames(_ name: String) {
        #expect(throws: (any Error).self) {
            try decode(ClientToolCapability.self, from: ["name": .string(name), "version": 1])
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        JSONValue.int(0), .int(-1), .int(9_007_199_254_740_992), .double(1.5), .bool(true), .string("1"), .null
    ])
    func capabilityDecodingRejectsInvalidVersions(_ version: JSONValue) {
        #expect(throws: (any Error).self) {
            try decode(ClientToolCapability.self, from: ["name": "listOpenTabs", "version": version])
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        #"{"version":1}"#,
        #"{"name":"listOpenTabs"}"#,
        #"{"name":true,"version":1}"#,
        #"{"name":"listOpenTabs","version":1,"permission":"ask"}"#
    ])
    func capabilityDecodingRejectsMissingMistypedAndUnknownFields(_ json: String) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ClientToolCapability.self, from: Data(json.utf8))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func configurationAccepts32CapabilitiesButRejects33() throws {
        let capabilities = try (0..<32).map {
            try ClientToolCapability(name: "tool-\($0)", version: 1)
        }
        _ = try ClientToolsConfiguration(capabilities: capabilities)

        let extraCapability = try ClientToolCapability(name: "extra-tool", version: 1)
        #expect(throws: (any Error).self) {
            try ClientToolsConfiguration(capabilities: capabilities + [extraCapability])
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [1, 2])
    func configurationRejectsDuplicateNamesRegardlessOfVersion(_ version: Int) throws {
        let duplicate = try ClientToolCapability(name: "listOpenTabs", version: version)
        #expect(throws: (any Error).self) {
            try ClientToolsConfiguration(capabilities: [.listOpenTabs, duplicate])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func executeRequestDecodesArgumentsWithoutApplyingAToolSpecificSchema() throws {
        let request = try decode(ExecuteClientToolRequest.self, from: [
            "callId": "call-1",
            "capability": ["name": "listOpenTabs", "version": 1],
            "input": ["limit": 5, "futureField": ["nested": true]]
        ])

        #expect(request.callId == "call-1")
        #expect(request.capability == .listOpenTabs)
        #expect(request.input == ["limit": 5, "futureField": ["nested": true]])
    }

    @Test(.timeLimit(.minutes(1)))
    func executeRequestPreservesExplicitNullInput() throws {
        let request = try decode(ExecuteClientToolRequest.self, from: [
            "callId": "call-1",
            "capability": ["name": "readTabContent", "version": 1],
            "input": .null
        ])

        #expect(request.input == .null)
    }

    @Test(.timeLimit(.minutes(1)))
    func executeRequestPreservesUnknownCapabilityAndUnsupportedVersion() throws {
        let request = try decode(ExecuteClientToolRequest.self, from: [
            "callId": "call-1",
            "capability": ["name": "futureTool", "version": 2],
            "input": [:]
        ])

        #expect(request.capability.name == "futureTool")
        #expect(request.capability.version == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func executeRequestAccepts128CharacterIdentifier() throws {
        let callId = String(repeating: "x", count: 128)
        let request = try decode(ExecuteClientToolRequest.self, from: [
            "callId": .string(callId),
            "capability": ["name": "listOpenTabs", "version": 1],
            "input": [:]
        ])

        #expect(request.callId == callId)
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        "", String(repeating: "x", count: 129), "call 1", "call\n", "call/1", "é"
    ])
    func executeRequestRejectsInvalidIdentifier(_ callId: String) {
        #expect(throws: (any Error).self) {
            try decode(ExecuteClientToolRequest.self, from: [
                "callId": .string(callId),
                "capability": ["name": "listOpenTabs", "version": 1],
                "input": [:]
            ])
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        #"{"capability":{"name":"listOpenTabs","version":1},"input":{}}"#,
        #"{"callId":"call-1","input":{}}"#,
        #"{"callId":"call-1","capability":{"name":"listOpenTabs","version":1}}"#,
        #"{"callId":1,"capability":{"name":"listOpenTabs","version":1},"input":{}}"#,
        #"{"callId":"call-1","capability":null,"input":{}}"#,
        #"{"callId":"call-1","capability":{"name":"listOpenTabs","version":1,"permission":"ask"},"input":{}}"#,
        #"{"callId":"call-1","capability":{"name":"listOpenTabs","version":1},"input":{},"deadlineMs":150000}"#
    ])
    func executeRequestRejectsMalformedMessage(_ json: String) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ExecuteClientToolRequest.self, from: Data(json.utf8))
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        JSONValue.object(["tabs": .array([])]), .null
    ])
    func successEncodingIncludesValueAndOmitsError(_ value: JSONValue) throws {
        let response = ExecuteClientToolResponse.success(callId: "call-1", value: value)

        #expect(try encodedJSON(response) == [
            "callId": "call-1",
            "ok": true,
            "value": value
        ])
    }

    @Test(.timeLimit(.minutes(1)))
    func failureEncodingIncludesOnlyErrorAndPreservesMalformedCallIdentifier() throws {
        let cases: [(String, ClientToolError, String)] = [
            ("call-1", .denied, "denied"),
            ("call 1", .invalidArguments, "invalid_arguments"),
            ("", .invalidArguments, "invalid_arguments")
        ]
        for (callId, error, expectedCode) in cases {
            let response = ExecuteClientToolResponse.failure(callId: callId, error: error)
            #expect(try encodedJSON(response) == [
                "callId": .string(callId),
                "ok": false,
                "error": ["code": .string(expectedCode)]
            ])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func permissionMessageLimitCountsUnicodeScalarsInsteadOfBytesOrGraphemes() throws {
        let messages = [
            String(repeating: "a", count: 4096),
            String(repeating: "e\u{301}", count: 2048)
        ]
        for message in messages {
            _ = try permissionPrompt(message: message)
            #expect(throws: (any Error).self) {
                try permissionPrompt(message: message + "a")
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func permissionPromptRejectsEmptyAndRepeatedChoices() {
        let choices: [[ClientToolPermissionChoice]] = [
            [],
            [.allow, .allow],
            [.allow, .always, .never, .allow]
        ]
        for invalidChoices in choices {
            #expect(throws: (any Error).self) {
                try permissionPrompt(choices: invalidChoices)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func permissionPromptValidatesBothCorrelationIdentifiersAtTheirBoundary() throws {
        let callId = String(repeating: "c", count: 128)
        let requestId = String(repeating: "r", count: 128)
        _ = try ClientToolPermissionRequested(requestId: requestId, callId: callId, message: "", choices: [.allow])

        for invalidId in ["", callId + "c", "invalid id"] {
            #expect(throws: (any Error).self) {
                try ClientToolPermissionRequested(requestId: invalidId, callId: callId, message: "", choices: [.allow])
            }
            #expect(throws: (any Error).self) {
                try ClientToolPermissionRequested(requestId: requestId, callId: invalidId, message: "", choices: [.allow])
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["allow", "always", "never", "decline", "cancel"])
    func permissionAnswerDecodesKnownDecisions(_ decision: String) throws {
        let answer = try decode(RespondToClientToolPermissionRequest.self, from: [
            "callId": "call-1",
            "requestId": "perm-1",
            "decision": .string(decision)
        ])

        #expect(answer.callId == "call-1")
        #expect(answer.requestId == "perm-1")
        #expect(answer.decision.rawValue == decision)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["alwaysAllow", "future_decision", ""])
    func permissionAnswerTreatsUnknownDecisionAsCancel(_ decision: String) throws {
        let answer = try decode(RespondToClientToolPermissionRequest.self, from: [
            "callId": "call-1",
            "requestId": "perm-1",
            "decision": .string(decision)
        ])

        #expect(answer.decision == .cancel)
    }

    @Test(.timeLimit(.minutes(1)))
    func permissionAnswerValidatesBothCorrelationIdentifiersAtTheirBoundary() throws {
        let callId = String(repeating: "c", count: 128)
        let requestId = String(repeating: "r", count: 128)
        let valid: [String: JSONValue] = [
            "callId": .string(callId),
            "requestId": .string(requestId),
            "decision": "allow"
        ]
        let answer = try decode(RespondToClientToolPermissionRequest.self, from: .object(valid))
        #expect(answer.callId == callId)
        #expect(answer.requestId == requestId)

        for field in ["callId", "requestId"] {
            for invalidId in ["", callId + "c", "invalid id"] {
                var invalid = valid
                invalid[field] = .string(invalidId)
                #expect(throws: (any Error).self) {
                    try decode(RespondToClientToolPermissionRequest.self, from: .object(invalid))
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        #"{"requestId":"perm-1","decision":"allow"}"#,
        #"{"callId":"call-1","decision":"allow"}"#,
        #"{"callId":"call-1","requestId":"perm-1"}"#,
        #"{"callId":1,"requestId":"perm-1","decision":"allow"}"#,
        #"{"callId":"call-1","requestId":null,"decision":"allow"}"#,
        #"{"callId":"call-1","requestId":"perm-1","decision":null}"#,
        #"{"callId":"call-1","requestId":"perm-1","decision":true}"#,
        #"{"callId":"call-1","requestId":"perm-1","decision":"allow","remember":true}"#
    ])
    func permissionAnswerRejectsMalformedMessage(_ json: String) {
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RespondToClientToolPermissionRequest.self, from: Data(json.utf8))
        }
    }

    // MARK: - Bridge payloads

    @Test(.timeLimit(.minutes(1)))
    func rawParamsParseIntoTheRequest() throws {
        let params: [String: Any] = ["callId": "call-1", "capability": ["name": "listOpenTabs", "version": 1], "input": ["limit": 5]]

        let request = try #require(ExecuteClientToolRequest.parse(rawParams: params))

        #expect(request.callId == "call-1")
        #expect(request.capability == .listOpenTabs)
        #expect(request.input == ["limit": 5])
    }

    /// An invalid request still settles the call: the reply echoes whatever `callId` is readable.
    @Test(.timeLimit(.minutes(1)), arguments: [
        (#"{"callId":"call-1","capability":{"name":"listOpenTabs","version":1},"input":{},"extra":true}"#, "call-1"),
        (#"{"callId":"call-1","input":{}}"#, "call-1"),
        (#"{"callId":"bad id!","capability":{"name":"listOpenTabs","version":1},"input":{}}"#, "bad id!"),
        (#"{"callId":7,"capability":{"name":"listOpenTabs","version":1},"input":{}}"#, "")
    ])
    func invalidRawParamsAreRejectedEchoingReadableCallID(json: String, expectedCallID: String) throws {
        let params = try JSONSerialization.jsonObject(with: Data(json.utf8))

        #expect(ExecuteClientToolRequest.parse(rawParams: params) == nil)
        #expect(ExecuteClientToolResponse.invalidRequest(rawParams: params) == .failure(callId: expectedCallID, error: .invalidArguments))
    }

    @Test(.timeLimit(.minutes(1)))
    func rawParamsOverInputByteLimitAreRejected() {
        let params: [String: Any] = ["callId": "call-1", "capability": ["name": "searchHistory", "version": 1],
                                     "input": ["query": String(repeating: "a", count: ClientToolPayloadLimits.inputBytes)]]

        #expect(ExecuteClientToolRequest.parse(rawParams: params) == nil)
        #expect(ExecuteClientToolResponse.invalidRequest(rawParams: params) == .failure(callId: "call-1", error: .invalidArguments))
    }

    /// Echoing an oversized id would push the reply itself over the result limit.
    @Test(.timeLimit(.minutes(1)))
    func invalidRequestDropsAnOversizedCallID() {
        let params: [String: Any] = ["callId": String(repeating: "a", count: 129)]

        #expect(ExecuteClientToolResponse.invalidRequest(rawParams: params) == .failure(callId: "", error: .invalidArguments))
    }

    @Test(.timeLimit(.minutes(1)))
    func nonObjectRawParamsAreRejectedWithoutCallID() {
        #expect(ExecuteClientToolRequest.parse(rawParams: "call-1") == nil)
        #expect(ExecuteClientToolResponse.invalidRequest(rawParams: "call-1") == .failure(callId: "", error: .invalidArguments))
    }

    @Test(.timeLimit(.minutes(1)))
    func resultOverByteLimitBecomesExecutionFailed() {
        let oversized = ExecuteClientToolResponse.success(callId: "call-1", value: .string(String(repeating: "a", count: ClientToolPayloadLimits.resultBytes)))
        let small = ExecuteClientToolResponse.success(callId: "call-1", value: ["tabs": []])
        let failure = ExecuteClientToolResponse.failure(callId: "call-1", error: .denied)

        #expect(oversized.limitedToResultBytes() == .failure(callId: "call-1", error: .executionFailed))
        #expect(small.limitedToResultBytes() == small)
        #expect(failure.limitedToResultBytes() == failure)
    }

    @Test(.timeLimit(.minutes(1)))
    func configurationRoundTripsAndRejectsUnknownProtocolVersion() throws {
        let configuration = try ClientToolsConfiguration(capabilities: [.listOpenTabs, .readTabContent])

        let decoded = try JSONDecoder().decode(ClientToolsConfiguration.self, from: JSONEncoder().encode(configuration))

        #expect(decoded == configuration)
        #expect(throws: (any Error).self) {
            try decode(ClientToolsConfiguration.self, from: ["protocolVersion": 2, "capabilities": []])
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        try JSONDecoder().decode(type, from: JSONEncoder().encode(value))
    }

    private func encodedJSON<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    private func permissionPrompt(
        message: String = "Allow Duck.ai to use this tool?",
        choices: [ClientToolPermissionChoice] = [.allow, .always, .never]
    ) throws -> ClientToolPermissionRequested {
        try ClientToolPermissionRequested(requestId: "perm-1", callId: "call-1", message: message, choices: choices)
    }
}
