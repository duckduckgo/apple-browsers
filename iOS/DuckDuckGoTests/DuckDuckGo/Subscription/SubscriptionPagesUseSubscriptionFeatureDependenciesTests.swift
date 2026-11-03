//
//  SubscriptionPagesUseSubscriptionFeatureDependenciesTests.swift
//  DuckDuckGo
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

import Testing
@_spi(Testing) import WideEvent
@testable import DuckDuckGo
@testable import Subscription
import SubscriptionTestingUtilities

@MainActor
@Suite("Subscription pages use subscription feature dependencies")
struct SubscriptionPagesUseSubscriptionFeatureDependenciesTests {

    private let subscriptionManager = SubscriptionManagerMock()
    private let wideEvent = WideEventMock()

    private func makeDependencies() -> SubscriptionPagesUseSubscriptionFeatureDependencies {
        SubscriptionPagesUseSubscriptionFeatureDependencies.make(subscriptionManager: subscriptionManager, wideEvent: wideEvent)
    }

    @available(iOS 16, macOS 13, *)
    @Test("make builds the default App Store flow chain", .timeLimit(.minutes(1)))
    func makeBuildsDefaultChain() {
        let dependencies = makeDependencies()

        #expect(dependencies.pendingTransactionHandler is DefaultPendingTransactionHandler)
        #expect(dependencies.appStoreRestoreFlow is DefaultAppStoreRestoreFlow)
        #expect(dependencies.appStorePurchaseFlow is DefaultAppStorePurchaseFlow)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each call to make builds fresh instances", .timeLimit(.minutes(1)))
    func makeBuildsFreshInstances() {
        let first = makeDependencies()
        let second = makeDependencies()

        #expect(first.pendingTransactionHandler as AnyObject !== second.pendingTransactionHandler as AnyObject)
        #expect(first.appStoreRestoreFlow as AnyObject !== second.appStoreRestoreFlow as AnyObject)
        #expect(first.appStorePurchaseFlow as AnyObject !== second.appStorePurchaseFlow as AnyObject)
        #expect(first.subscriptionFlowsExecuter !== second.subscriptionFlowsExecuter)
    }

    @available(iOS 16, macOS 13, *)
    @Test("DefaultSubscriptionFlowsExecuter.make builds a fresh executer per call", .timeLimit(.minutes(1)))
    func executerMakeBuildsFreshInstances() {
        let first = DefaultSubscriptionFlowsExecuter.make(subscriptionManager: subscriptionManager, wideEvent: wideEvent)
        let second = DefaultSubscriptionFlowsExecuter.make(subscriptionManager: subscriptionManager, wideEvent: wideEvent)

        #expect(first !== second)
    }
}
