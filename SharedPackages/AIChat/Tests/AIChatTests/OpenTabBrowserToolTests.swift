//
//  OpenTabBrowserToolTests.swift
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
import Testing
import AIChat

@MainActor
struct OpenTabBrowserToolTests {
    private let context = BrowserToolCallContext(ownerTabID: "owner", isBurner: false)

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func opensTheApprovedAddressAndPromptsAgainForTheNextCall() async throws {
        let kyoto = "http://kyoto.example/wiki/Kyoto?test=manual#History"
        let osaka = "https://osaka.example/wiki/Osaka"
        var openedAddresses: [String] = []
        let tool = OpenTabBrowserTool { url, _ in
            openedAddresses.append(url.absoluteString)
            return "new-tab"
        }
        let permissions = ClientToolTestPermissions()
        permissions.storedDecisions[tool.name] = .allow
        let coordinator = ClientToolPermissionCoordinator(permissions: permissions)
        let configuration = ClientToolTestConfiguration()
        configuration.isRequestAccessEnabled = true
        let catalog = BrowserToolCatalog(tools: [tool], configuration: configuration)
        let invoker = BrowserToolInvoker(catalog: catalog, clientToolPermissions: coordinator)
        let source = ClientToolTestSource()
        source.onPush = { [weak source] prompt in
            guard let source else { return false }
            if prompt.callID == "kyoto" {
                #expect(openedAddresses.isEmpty)
                coordinator.respond(to: prompt, decision: .allowOnce, from: source)
            } else {
                #expect(openedAddresses == [kyoto])
                coordinator.respond(to: prompt, decision: .dontAllow, from: source)
            }
            return true
        }
        let first = try makeRequest(callID: "kyoto", input: ["url": .string(kyoto)])
        let second = try makeRequest(callID: "osaka", input: ["url": .string(osaka)])

        let allowed = await invoker.invokeClientTool(first, context: context, permissionPrompter: source)
        let denied = await invoker.invokeClientTool(second, context: context, permissionPrompter: source)

        #expect(allowed == .success(callId: "kyoto", value: ["tabId": "new-tab"]))
        #expect(denied == .failure(callId: "osaka", error: .denied))
        #expect(source.prompts.map(\.callID) == ["kyoto", "osaka"])
        #expect(source.prompts.map(\.target) == [kyoto, osaka])
        #expect(source.prompts.allSatisfy { !$0.offersAlways && !$0.offersAllowForChat && $0.accessToolNames == nil })
        #expect(openedAddresses == [kyoto])
        #expect(permissions.writes == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func rejectsInvalidAddressesBeforeRequestingPermission() async throws {
        let tool = OpenTabBrowserTool { _, _ in
            Issue.record("Invalid addresses must never open a tab")
            return nil
        }
        let permissions = ClientToolTestPermissions()
        let coordinator = ClientToolPermissionCoordinator(permissions: permissions)
        let catalog = BrowserToolCatalog(tools: [tool], configuration: ClientToolTestConfiguration())
        let invoker = BrowserToolInvoker(catalog: catalog, clientToolPermissions: coordinator)
        let source = ClientToolTestSource()
        source.onPush = { _ in false }
        let prefix = "https://kyoto.example/"
        let longestAddress = prefix + String(repeating: "a", count: 1280 - prefix.count)
        #expect(tool.permissionTarget(arguments: ["url": .string(longestAddress)], context: context) == longestAddress)
        let inputs: [JSONValue] = [
            [:], ["url": 1], ["url": "https:///wiki/Kyoto"],
            ["url": "https://duckduckgo.com/?ia=chat"], ["url": .string(longestAddress + "a")]
        ]

        for input in inputs {
            let request = try makeRequest(callID: "invalid", input: input)
            let result = await invoker.invokeClientTool(request, context: context, permissionPrompter: source)
            #expect(result == .failure(callId: "invalid", error: .invalidArguments), "Input: \(input)")
        }

        #expect(source.prompts.isEmpty)
        #expect(permissions.writes == 0)
    }

    private func makeRequest(callID: String, input: JSONValue) throws -> ExecuteClientToolRequest {
        let payload: JSONValue = [
            "callId": .string(callID), "chatId": "chat", "capability": ["name": "openTab", "version": 1], "input": input
        ]
        return try JSONDecoder().decode(ExecuteClientToolRequest.self, from: JSONEncoder().encode(payload))
    }
}
