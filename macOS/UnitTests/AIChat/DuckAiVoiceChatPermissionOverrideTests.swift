//
//  DuckAiVoiceChatPermissionOverrideTests.swift
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

@testable import DuckDuckGo_Privacy_Browser

final class DuckAiVoiceChatPermissionOverrideTests: XCTestCase {

    private func makeOverride(aiChatHost: String? = URL.duckAi.host) -> DuckAiVoiceChatPermissionOverride {
        let url: URL = aiChatHost.flatMap { URL(string: "https://\($0)") } ?? URL(string: "data:,empty")!
        return DuckAiVoiceChatPermissionOverride(aiChatURL: url)
    }

    // MARK: - Positive case

    func testWhenDuckAiHostAndMicrophoneThenReturnsAllow() {
        let sut = makeOverride()

        XCTAssertEqual(sut.decision(forDomain: URL.duckAi.host!, permissionType: .microphone), .allow)
    }

    // MARK: - Domain scoping

    func testWhenDomainIsNotDuckAiThenReturnsNil() {
        let sut = makeOverride()

        XCTAssertNil(sut.decision(forDomain: "example.com", permissionType: .microphone))
        XCTAssertNil(sut.decision(forDomain: "duckduckgo.com", permissionType: .microphone))
    }

    // MARK: - Permission type scoping

    func testWhenPermissionTypeIsNotMicrophoneThenReturnsNil() {
        let sut = makeOverride()

        XCTAssertNil(sut.decision(forDomain: URL.duckAi.host!, permissionType: .camera))
        XCTAssertNil(sut.decision(forDomain: URL.duckAi.host!, permissionType: .geolocation))
        XCTAssertNil(sut.decision(forDomain: URL.duckAi.host!, permissionType: .notification))
        XCTAssertNil(sut.decision(forDomain: URL.duckAi.host!, permissionType: .popups))
    }

    // MARK: - Degenerate URL

    func testWhenAIChatURLHasNoHostThenReturnsNil() {
        let sut = DuckAiVoiceChatPermissionOverride(aiChatURL: URL(string: "data:,empty")!)

        XCTAssertNil(sut.decision(forDomain: "", permissionType: .microphone),
                     "An override with no resolvable host has nothing to compare against and must opt out")
    }
}
