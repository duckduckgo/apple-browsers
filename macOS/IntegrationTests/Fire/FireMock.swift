//
//  FireMock.swift
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

import Combine
import Common
import Foundation
import History

@testable import DuckDuckGo_Privacy_Browser

final class FireMock: FireProtocol {

    var burningData: DuckDuckGo_Privacy_Browser.Fire.BurningData?

    let fireproofDomains: FireproofDomains
    let visualizeFireAnimationDecider: VisualizeFireSettingsDecider

    private let burningSubject = PassthroughSubject<Fire.BurningData?, Never>()
    var burningDataPublisher: AnyPublisher<Fire.BurningData?, Never> { burningSubject.eraseToAnyPublisher() }

    init(fireproofDomains: FireproofDomains = FireproofDomains(store: FireproofDomainsStoreMock(), tld: TLD()),
         visualizeFireAnimationDecider: VisualizeFireSettingsDecider = MockVisualizeFireAnimationDecider()) {
        self.fireproofDomains = fireproofDomains
        self.visualizeFireAnimationDecider = visualizeFireAnimationDecider
    }

    // Captured calls
    struct BurnAllCall { let isBurnOnExit: Bool; let includeCookiesAndSiteData: Bool; let includeChatHistory: Bool; let url: URL }
    struct BurnEntityCall { let entity: Fire.BurningEntity; let includingHistory: Bool; let includeCookiesAndSiteData: Bool; let includeChatHistory: Bool; }
    struct BurnVisitsCall { let visits: [Visit]; let isToday: Bool; let closeWindows: Bool; let clearSiteData: Bool; let clearChatHistory: Bool; let url: URL? }
    struct BurnChatHistoryCall { }

    private(set) var burnAllCalls: [BurnAllCall] = []
    private(set) var burnEntityCalls: [BurnEntityCall] = []
    private(set) var burnVisitsCalls: [BurnVisitsCall] = []
    private(set) var burnChatHistoryCalls: [BurnChatHistoryCall] = []

    // MARK: - Fire animation hooks
    func fireAnimationDidStart() {
        // simulate start by emitting non-nil value
        burningSubject.send(.all)
    }

    func fireAnimationDidFinish() {
        // simulate finish by emitting nil
        burningSubject.send(nil)
    }

    @MainActor
    func burnAll(isBurnOnExit: Bool, opening url: URL, includeCookiesAndSiteData: Bool, includeChatHistory: Bool, completion: (@MainActor () -> Void)?) {
        burnAllCalls.append(.init(isBurnOnExit: isBurnOnExit, includeCookiesAndSiteData: includeCookiesAndSiteData, includeChatHistory: includeChatHistory, url: url))
        completion?()
    }

    @MainActor
    func burnEntity(_ entity: DuckDuckGo_Privacy_Browser.Fire.BurningEntity, includingHistory: Bool, includeCookiesAndSiteData: Bool, includeChatHistory: Bool, completion: (@MainActor () -> Void)?) {
        burnEntityCalls.append(.init(entity: entity, includingHistory: includingHistory, includeCookiesAndSiteData: includeCookiesAndSiteData, includeChatHistory: includeChatHistory))
        completion?()
    }

    @MainActor
    func burnVisits(_ visits: [Visit],
                    except fireproofDomains: DomainFireproofStatusProviding,
                    isToday: Bool,
                    closeWindows: Bool = true,
                    clearSiteData: Bool = true,
                    clearChatHistory: Bool = false,
                    urlToOpenIfWindowsAreClosed url: URL? = .newtab,
                    completion: (@MainActor () -> Void)? = nil) {
        burnVisitsCalls.append(.init(visits: visits, isToday: isToday, closeWindows: closeWindows, clearSiteData: clearSiteData, clearChatHistory: clearChatHistory, url: url))
        completion?()
    }

    @MainActor
    func burnChatHistory() {
        burnChatHistoryCalls.append(.init())
    }
}
