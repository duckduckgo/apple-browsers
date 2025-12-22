//
//  JsonToRemoteMessageModelMapperPlaceholdersTests.swift
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

import Testing
import RemoteMessagingTestsUtils
@testable import RemoteMessaging

@Suite("RMF - Mapping - Placeholders")
struct JsonToRemoteMessageModelMapperPlaceholdersTests {
    private static let placeholderMappings: [(RemoteMessageResponse.JsonPlaceholder, RemotePlaceholder)] = [
        (.announce, .announce),
        (.ddgAnnounce, .ddgAnnounce),
        (.criticalUpdate, .criticalUpdate),
        (.appUpdate, .appUpdate),
        (.macComputer, .macComputer),
        (.newForMacAndWindows, .newForMacAndWindows),
        (.privacyShield, .subscription),
        (.aiChat, .aiChat),
        (.visualDesignUpdate, .visualDesignUpdate),
        (.imageAI, .imageAI),
        (.radar, .radar),
        (.radarCheckGreen, .radarCheckGreen),
        (.radarCheckPurple, .radarCheckPurple),
        (.keyImport, .keyImport),
        (.mobileCustomization, .mobileCustomization),
        (.pir, .pir),
        (.subscription, .subscription),
    ]

    @Test("Check Placeholder Mapping Coverage")
    func placeholderMappingIsExhaustive() {
        let mappedKeys = Set(Self.placeholderMappings.map { $0.0 })
        let allKeys = Set(RemoteMessageResponse.JsonPlaceholder.allCases)

        #expect(mappedKeys == allKeys)
    }

    @Test(
        "Check Placeholders Are Mapped Correctly",
        arguments: Self.placeholderMappings
    )
    func placeholderAPIModelIsMappedCorrectly(apiValue: RemoteMessageResponse.JsonPlaceholder, expectedDomainValue: RemotePlaceholder) {
        // WHEN
        let result = JsonToRemoteMessageModelMapper.mapToPlaceholder(apiValue.rawValue)

        // THEN
        #expect(result == expectedDomainValue)
    }

}

@Suite("RMF - Mapping - Placeholders - JSON Integration")
struct JsonToRemoteMessageModelMapperPlaceholdersIntegrationTests {
    let config: RemoteConfigModel

    init() throws {
        self.config = try RemoteMessagingConfigDecoder.decodeAndMapJson(
            fileName: "remote-messaging-config-placeholders.json",
            bundle: .module
        )
    }

    @Test(
        "Check Placeholder Json Value Gets Mapped Correctly In Message",
        arguments: [
            ("1", .announce), // No placeholder -> default to announce
            ("2", .announce),
            ("3", .ddgAnnounce),
            ("4", .criticalUpdate),
            ("5", .appUpdate),
            ("6", .macComputer),
            ("7", .newForMacAndWindows),
            ("8", .subscription),
            ("9", .aiChat),
            ("10", .visualDesignUpdate),
            ("11", .imageAI),
            ("12", .radarCheckGreen),
            ("13", .keyImport),
            ("14", .radar),
            ("15", .radarCheckPurple),
            ("16", .pir),
            ("17", .subscription),
        ] as [(String, RemotePlaceholder)]
    )
    func placeholderIsMappedCorrectlyForMessages(id: String, expectedDomainValue: RemotePlaceholder) throws {
        // GIVEN
        let message = try #require(config.messages.first(where: { $0.id == id }))

        // WHEN
        guard case let .medium(_, _, placeholder) = message.content else {
            Issue.record("Expected medium content type")
            return
        }

        // THEN
        #expect(message.id == id)
        #expect(placeholder == expectedDomainValue)
    }

    @Test(
        "Check Placeholder Json Value Gets Mapped Correctly In List Item",
        arguments: [
            ("1", .announce), // No placeholder -> default to announce
            ("2", .announce),
            ("3", .ddgAnnounce),
            ("4", .criticalUpdate),
            ("5", .appUpdate),
            ("6", .macComputer),
            ("7", .newForMacAndWindows),
            ("8", .subscription),
            ("9", .aiChat),
            ("10", .visualDesignUpdate),
            ("11", .imageAI),
            ("12", .radarCheckGreen),
            ("13", .keyImport),
            ("14", .radar),
            ("15", .radarCheckPurple),
            ("16", .pir),
            ("17", .subscription),
        ] as [(String, RemotePlaceholder)]
    )
    func placeholderIsMappedCorrectlyForItemsInList(itemId: String, expectedDomainValue: RemotePlaceholder) throws {
        // GIVEN
        let messageId = "18"
        let message = try #require(config.messages.first(where: { $0.id == messageId }))
        let listItems = try #require(message.content?.listItems)

        // WHEN
        let item =  try #require(listItems.first(where: { $0.id == itemId }))

        // THEN
        #expect(item.id == itemId)
        #expect(item.placeholderImage == expectedDomainValue)
    }
}
