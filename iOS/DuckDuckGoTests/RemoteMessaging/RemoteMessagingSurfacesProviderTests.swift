//
//  RemoteMessagingSurfacesProviderTests.swift
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

import Testing
import RemoteMessaging
import RemoteMessagingTestsUtils
@testable import DuckDuckGo

@Suite("RMF - Surfaces Provider")
struct RemoteMessagingSurfacesProviderTest {

    @Test(
        "Check Expected Surface Is Returned For Message Type",
        arguments: [
            (.small(titleText: "", descriptionText: ""), .newTabPage),
            (.medium(titleText: "", descriptionText: "", placeholder: .announce, imageUrl: nil), .newTabPage),
            (.bigSingleAction(titleText: "", descriptionText: "", placeholder: .announce, imageUrl: nil, primaryActionText: "", primaryAction: .dismiss), .newTabPage),
            (.bigTwoAction(titleText: "", descriptionText: "", placeholder: .announce, imageUrl: nil, primaryActionText: "", primaryAction: .dismiss, secondaryActionText: "", secondaryAction: .dismiss), .newTabPage),
            (.promoSingleAction(titleText: "", descriptionText: "", placeholder: .announce, imageUrl: nil, actionText: "", action: .dismiss), .newTabPage),
            (.cardsList(titleText: "", placeholder: nil, imageUrl: nil, items: [], primaryActionText: "", primaryAction: .dismiss), .modal)
        ] as [(RemoteMessageModelType, RemoteMessageSurfaceType)]
    )
    func returnExpectedSurfaceForMessageType(messageType: RemoteMessageModelType, expectedSurface: RemoteMessageSurfaceType) throws {
        // GIVEN
        let sut = DefaultRemoteMessagingSurfacesProvider()

        // WHEN
        let result = sut.supportedSurfaces(for: messageType)

        // THEN
        #expect(result.contains(expectedSurface))
    }

}
