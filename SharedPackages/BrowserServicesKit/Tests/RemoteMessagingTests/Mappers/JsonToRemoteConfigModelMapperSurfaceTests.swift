//
//  JsonToRemoteConfigModelMapperTests.swift
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
    let config: RemoteConfigModel

    init() throws {
        config = try RemoteMessagingConfigDecoder.decodeAndMapJson(fileName: "remote-messaging-config-surfaces-items.json", bundle: .module)
    }

    @Test(
        "Check Surfaces Are Mapped Correctly",
        arguments: zip(
            [0, 1, 2, 3],
            [RemoteMessageSurfaceType.newTabPage, .modal, .dedicatedTab, .allCases]
        )
    )
    func checkSurfaceIsMappedCorrectly(index: Int, expectedSurface: RemoteMessageSurfaceType) async throws {
        // GIVEN
        #expect(config.messages.count == 5)

        // WHEN
        let message = config.messages[index]

        // THEN
        #expect(message.id == String(index+1))
        #expect(message.surfaces == expectedSurface)
    }

    @Test("Check No Surfaces Value Is Mapped To New Tab Page")
    func checkNoSurfacesValueIsMappedToNewTabPage() async throws {
        // GIVEN
        #expect(config.messages.count == 5)

        // WHEN
        let message = config.messages[4]

        // THEN
        #expect(message.id == "5")
        #expect(message.surfaces == .newTabPage)
    }

}
