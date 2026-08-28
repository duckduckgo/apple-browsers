//
//  ApplicationShortcutItemsServiceTests.swift
//  DuckDuckGoTests
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
import UIKit
@testable import DuckDuckGo

@MainActor
@Suite("Application Shortcut Items Service")
struct ApplicationShortcutItemsServiceTests {

    @Test("Resume updates shortcut items while the application is active")
    func resumeUpdatesShortcutItemsWhileActive() async {
        let shortcutItem = UIApplicationShortcutItem(type: "test", localizedTitle: "Test")
        let recorder = ShortcutItemsRecorder()
        var updates = recorder.updates.makeAsyncIterator()
        let service = ApplicationShortcutItemsService(
            shortcutItemProviders: [{ shortcutItem }],
            notificationCenter: NotificationCenter(),
            applicationStateProvider: { .active },
            shortcutItemsUpdater: recorder.record)

        service.resume()

        let updatedItems = await updates.next()
        #expect(updatedItems?.map(\.type) == [shortcutItem.type])
    }

    @Test("Resume does not update shortcut items while the application is in the background")
    func resumeDoesNotUpdateShortcutItemsWhileBackgrounded() async {
        let shortcutItem = UIApplicationShortcutItem(type: "test", localizedTitle: "Test")
        let providerCalled = AsyncSignal<Void>()
        var providerCalls = providerCalled.values.makeAsyncIterator()
        let recorder = ShortcutItemsRecorder()
        let service = ApplicationShortcutItemsService(
            shortcutItemProviders: [{
                providerCalled.send(())
                return shortcutItem
            }],
            notificationCenter: NotificationCenter(),
            applicationStateProvider: { .background },
            shortcutItemsUpdater: recorder.record)

        service.resume()
        _ = await providerCalls.next()
        await Task.yield()

        #expect(recorder.recordedItems.isEmpty)
    }

    @Test("Suspend prevents an in-flight refresh from updating shortcut items")
    func suspendPreventsInFlightRefreshFromUpdatingShortcutItems() async {
        let shortcutItem = UIApplicationShortcutItem(type: "test", localizedTitle: "Test")
        let provider = SuspendedShortcutItemProvider()
        var providerCalls = provider.didStart.values.makeAsyncIterator()
        let recorder = ShortcutItemsRecorder()
        let service = ApplicationShortcutItemsService(
            shortcutItemProviders: [provider.shortcutItem],
            notificationCenter: NotificationCenter(),
            applicationStateProvider: { .active },
            shortcutItemsUpdater: recorder.record)

        service.resume()
        _ = await providerCalls.next()
        service.suspend()
        provider.finish(with: shortcutItem)
        await Task.yield()

        #expect(recorder.recordedItems.isEmpty)
    }

    @Test("Suspend removes shortcut items that are no longer eligible")
    func suspendRemovesIneligibleShortcutItems() {
        let retainedShortcutItem = UIApplicationShortcutItem(type: "retained", localizedTitle: "Retained")
        let removedShortcutItem = UIApplicationShortcutItem(type: "removed", localizedTitle: "Removed")
        let recorder = ShortcutItemsRecorder()
        let service = ApplicationShortcutItemsService(
            shortcutItemProviders: [],
            notificationCenter: NotificationCenter(),
            applicationStateProvider: { .inactive },
            currentShortcutItemsProvider: { [retainedShortcutItem, removedShortcutItem] },
            shortcutItemsFilter: { $0.filter { $0.type != removedShortcutItem.type } },
            shortcutItemsUpdater: recorder.record)

        service.suspend()

        #expect(recorder.recordedItems.map { $0.map(\.type) } == [[retainedShortcutItem.type]])
    }

    @Test("Suspend does not update shortcut items after entering the background")
    func suspendDoesNotUpdateShortcutItemsAfterEnteringBackground() {
        let shortcutItem = UIApplicationShortcutItem(type: "removed", localizedTitle: "Removed")
        let recorder = ShortcutItemsRecorder()
        let service = ApplicationShortcutItemsService(
            shortcutItemProviders: [],
            notificationCenter: NotificationCenter(),
            applicationStateProvider: { .background },
            currentShortcutItemsProvider: { [shortcutItem] },
            shortcutItemsFilter: { _ in [] },
            shortcutItemsUpdater: recorder.record)

        service.suspend()

        #expect(recorder.recordedItems.isEmpty)
    }

    @Test("Settings changes refresh shortcut items while active")
    func settingsChangesRefreshShortcutItemsWhileActive() async {
        let notificationCenter = NotificationCenter()
        let shortcutItem = UIApplicationShortcutItem(type: "test", localizedTitle: "Test")
        let recorder = ShortcutItemsRecorder()
        var updates = recorder.updates.makeAsyncIterator()
        let service = ApplicationShortcutItemsService(
            shortcutItemProviders: [{ shortcutItem }],
            notificationCenter: notificationCenter,
            applicationStateProvider: { .active },
            shortcutItemsUpdater: recorder.record)

        service.resume()
        _ = await updates.next()
        notificationCenter.post(name: .aiChatSettingsChanged, object: nil)

        _ = await updates.next()
        #expect(recorder.recordedItems.count == 2)
    }

}

@MainActor
private final class ShortcutItemsRecorder {

    private let signal = AsyncSignal<[UIApplicationShortcutItem]>()
    private(set) var recordedItems: [[UIApplicationShortcutItem]] = []
    var updates: AsyncStream<[UIApplicationShortcutItem]> { signal.values }

    func record(_ shortcutItems: [UIApplicationShortcutItem]) {
        recordedItems.append(shortcutItems)
        signal.send(shortcutItems)
    }

}

@MainActor
private final class SuspendedShortcutItemProvider {

    let didStart = AsyncSignal<Void>()
    private var continuation: CheckedContinuation<UIApplicationShortcutItem?, Never>?

    func shortcutItem() async -> UIApplicationShortcutItem? {
        didStart.send(())
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish(with shortcutItem: UIApplicationShortcutItem?) {
        continuation?.resume(returning: shortcutItem)
        continuation = nil
    }

}

private final class AsyncSignal<Value> {

    let values: AsyncStream<Value>
    private let continuation: AsyncStream<Value>.Continuation

    init() {
        let stream = AsyncStream<Value>.makeStream()
        values = stream.stream
        continuation = stream.continuation
    }

    func send(_ value: Value) {
        continuation.yield(value)
    }

}
