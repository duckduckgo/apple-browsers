//
//  JsonToRemoteConfigModelMapperSurfaceTests.swift
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

@Suite("RMF - Mapping - Surfaces")
struct JsonToRemoteConfigModelMapperSurfaceTests {

    @Test(
        "Check Messages Without Surfaces Are Mapped Correctly to Supported Surface Default Value",
        arguments: [0, 1, 2, 3, 4]
    )
    func checkSurfaceIsSetToDefaultSupportedWhenNil(index: Int) throws {
        // GIVEN
        let config = try RemoteMessagingConfigDecoder.decodeAndMapJson(fileName: "remote-messaging-config-surfaces-default-values.json", bundle: .module, supportedSurfacesForMessage: { _ in .newTabPage })
        #expect(config.messages.count == 5)

        // WHEN
        let message = config.messages[index]

        // THEN
        #expect(message.id == String(index+1))
        #expect(message.surfaces == .newTabPage)
    }

    @Test("Default surface prefers newTabPage when tabBar is also supported")
    func checkDefaultSurfacePrefersNewTabPageWhenTabBarSupported() throws {
        let config = try RemoteMessagingConfigDecoder.decodeAndMapJson(
            fileName: "remote-messaging-config-surfaces-default-values.json",
            bundle: .module,
            supportedSurfacesForMessage: { _ in [.newTabPage, .tabBar] }
        )

        config.messages.forEach { message in
            #expect(message.surfaces == .newTabPage)
        }
    }

    @Test(
        "Check Surface Is Mapped Correctly When Message Type Supports It",
    )
    func checkSurfaceIsMappedCorrectlyWhenSupported() throws {
        // GIVEN
        let expectedSurfaces: [String: RemoteMessageSurfaceType] = [
            "1": .newTabPage,
            "2": .newTabPage,
            "3": .newTabPage,
            "4": .newTabPage,
            "5": .newTabPage,
            "6": .tabBar
        ]

        let config = try RemoteMessagingConfigDecoder.decodeAndMapJson(
            fileName: "remote-messaging-config-surfaces-supported-values.json",
            bundle: .module,
            supportedSurfacesForMessage: { _ in [.newTabPage, .tabBar] }
        )
        #expect(config.messages.count == expectedSurfaces.count)

        // WHEN/THEN
        for message in config.messages {
            let expectedSurface = try #require(expectedSurfaces[message.id])
            #expect(message.surfaces == expectedSurface)
        }
    }

    @Test("Check Messages With Unsupported Surfaces are Dropped")
    func smallMessagesWithUnsupportedSurfacesAreDropped() async throws {
        // GIVEN
        // All messages in remote-messaging-config-surfaces-supported-values.json have either .modal, .dedicatedTab or both
        let config = try RemoteMessagingConfigDecoder.decodeAndMapJson(fileName: "remote-messaging-config-surfaces-unsupported-values.json", bundle: .module, supportedSurfacesForMessage: { _ in .newTabPage })

        // WHEN
        let result = config.messages.count

        // THEN
        #expect(result == 0)
    }

    @Test(
        "Messages with mixed surfaces are filtered to supported ones",
        arguments: zip(["1", "2", "3", "4", "5"], [RemoteMessageSurfaceType.newTabPage, .newTabPage, nil, nil, .newTabPage])
    )
    func messagesWithMixedSurfacesAreFiltered(messageId: String, expectedSurface: RemoteMessageSurfaceType?) async throws {
        // GIVEN
        let config = try RemoteMessagingConfigDecoder.decodeAndMapJson(fileName: "remote-messaging-config-surfaces-mixed-supported-and-unsupported-values.json", bundle: .module, supportedSurfacesForMessage: { _ in .newTabPage })
        #expect(config.messages.count == 3)

        // WHEN
        let result = config.messages.first(where: { $0.id == messageId })

        // THEN
        if expectedSurface == nil {
            #expect(result == nil) // Message has been filtered out as no surfaces where valid
        } else {
            let surface = try #require(expectedSurface)
            #expect(result?.surfaces == surface)
        }
    }

}
