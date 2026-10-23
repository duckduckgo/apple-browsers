//
//  FireProgressWindowTests.swift
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

import Combine
import Common
import FoundationExtensions
import History
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class FireProgressWindowTests: XCTestCase {
    @MainActor
    func testFastCleanupCancelsDelayedPresentation() async throws {
        let fire = ProgressFireStub()
        let model = FireViewModel(fire: fire)
        let source = makeSource()
        defer { source.close() }
        fire.burningData = .all
        let progress = FireProgressWindowController.present(fireViewModel: model, message: "All data", sourceWindow: source, delay: 0.15)
        fire.burningData = nil
        try await Task.sleep(nanoseconds: 350_000_000)
        XCTAssertNil(progress.window, "A completed cleanup must not flash a delayed panel")
    }

    @MainActor
    func testSlowCleanupUsesIndependentPanelAndStandardPopupAnimation() async throws {
        let fire = ProgressFireStub()
        let model = FireViewModel(fire: fire)
        let source = makeSource()
        defer { source.close() }
        fire.burningData = .all
        let progress = FireProgressWindowController.present(fireViewModel: model, message: "Scope-specific progress", sourceWindow: source, delay: 0)
        await waitForVisibility(progress, visible: true)
        let window = try XCTUnwrap(progress.window)
        XCTAssertTrue(window is NSPanel)
        XCTAssertNil(window.parent)
        XCTAssertNil(window.sheetParent)
        XCTAssertEqual(window.animationBehavior, .alertPanel)
        let stack = try XCTUnwrap(window.contentView?.subviews.first as? NSStackView)
        XCTAssertEqual((stack.arrangedSubviews.first as? NSTextField)?.stringValue, "Scope-specific progress")
        XCTAssertEqual((stack.arrangedSubviews.last as? NSProgressIndicator)?.style, .bar)
        source.close()
        XCTAssertTrue(window.isVisible, "Closing the browser must not close its independent progress window")
        fire.burningData = nil
        await waitForVisibility(progress, visible: false)
        XCTAssertNil(progress.window)
    }

    @MainActor
    func testProgressWaitsForAnimationThenAppearsWhileCleanupIsStillPending() async throws {
        let fire = ProgressFireStub()
        let model = FireViewModel(fire: fire)
        let source = makeSource()
        defer { source.close() }
        fire.burningData = .all
        model.setSnapshotAnimationPlaying(true, isFireWindow: false)
        let progress = FireProgressWindowController.present(fireViewModel: model, message: "All data", sourceWindow: source, delay: 0)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertNil(progress.window)
        model.setSnapshotAnimationPlaying(false, isFireWindow: false)
        progress.animationDidFinish()
        await waitForVisibility(progress, visible: true)
        fire.burningData = nil
        await waitForVisibility(progress, visible: false)
    }

    @MainActor
    func testCleanupFinishingBeforeAnimationNeverShowsProgressAfterAnimation() async throws {
        let fire = ProgressFireStub()
        let model = FireViewModel(fire: fire)
        let source = makeSource()
        defer { source.close() }
        fire.burningData = .all
        model.setSnapshotAnimationPlaying(true, isFireWindow: false)
        let progress = FireProgressWindowController.present(fireViewModel: model, message: "All data", sourceWindow: source, delay: 0.1)
        fire.burningData = nil
        try await Task.sleep(nanoseconds: 150_000_000)
        model.setSnapshotAnimationPlaying(false, isFireWindow: false)
        progress.animationDidFinish()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNil(progress.window)
    }

    @MainActor
    func testVisibleProgressRespectsMinimumDurationThenDisappears() async {
        let fire = ProgressFireStub()
        let model = FireViewModel(fire: fire)
        let source = makeSource()
        defer { source.close() }
        fire.burningData = .all
        let progress = FireProgressWindowController.present(fireViewModel: model, message: "All data", sourceWindow: source, delay: 0)
        await waitForVisibility(progress, visible: true)
        let observedAt = Date()
        fire.burningData = nil
        await waitForVisibility(progress, visible: false)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(observedAt), 0.8)
    }

    @MainActor
    func testNextBurnReplacesPreviousPanelAndCancelsItsPendingDismissal() async throws {
        let fire = ProgressFireStub()
        let model = FireViewModel(fire: fire)
        let source = makeSource()
        defer { source.close() }
        fire.burningData = .all
        let previous = FireProgressWindowController.present(fireViewModel: model, message: "First burn", sourceWindow: source, delay: 0)
        await waitForVisibility(previous, visible: true)
        fire.burningData = nil
        try await Task.sleep(nanoseconds: 50_000_000)
        fire.burningData = .all
        let next = FireProgressWindowController.present(fireViewModel: model, message: "Second burn", sourceWindow: source, delay: 0)
        await waitForVisibility(next, visible: true)
        XCTAssertNil(previous.window)
        try await Task.sleep(nanoseconds: 1_100_000_000)
        XCTAssertTrue(next.window?.isVisible == true, "The previous burn's timer must not dismiss this burn")
        XCTAssertEqual(NSApp.windows.filter { $0.isVisible && $0.windowController is FireProgressWindowController }.count, 1)
        fire.burningData = nil
        await waitForVisibility(next, visible: false)
    }

    @MainActor
    private func waitForVisibility(_ progress: FireProgressWindowController, visible: Bool) async {
        let changed = expectation(for: NSPredicate { _, _ in (progress.window?.isVisible ?? false) == visible }, evaluatedWith: nil)
        await fulfillment(of: [changed], timeout: 3)
    }

    @MainActor
    private func makeSource() -> NSWindow {
        let window = NSWindow(contentRect: .init(x: 100, y: 100, width: 700, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        return window
    }
}

private final class ProgressFireStub: FireProtocol {
    @Published var burningData: Fire.BurningData?
    let fireproofDomains: FireproofDomains = MockFireproofDomains()
    let visualizeFireAnimationDecider: VisualizeFireSettingsDecider = MockVisualizeFireAnimationDecider()
    var burningDataPublisher: AnyPublisher<Fire.BurningData?, Never> { $burningData.eraseToAnyPublisher() }

    func fireAnimationDidStart() {}
    func fireAnimationDidFinish() {}

    @MainActor
    func burnAll(isBurnOnExit: Bool, opening url: URL, includeCookiesAndSiteData: Bool, includeChatHistory: Bool,
                 isAutoClear: Bool, dataClearingWideEventService: DataClearingWideEventService?, completion: (@MainActor () -> Void)?) {
        XCTFail("Unexpected data clearing")
    }

    @MainActor
    func burnEntity(_ entity: Fire.BurningEntity, includingHistory: Bool, includeCookiesAndSiteData: Bool, includeChatHistory: Bool,
                    dataClearingWideEventService: DataClearingWideEventService?, completion: (@MainActor () -> Void)?) {
        XCTFail("Unexpected data clearing")
    }

    @MainActor
    func burnVisits(_ visits: [Visit], except fireproofDomains: DomainFireproofStatusProviding, isToday: Bool, closeWindows: Bool,
                    clearSiteData: Bool, clearChatHistory: Bool, urlToOpenIfWindowsAreClosed url: URL?,
                    dataClearingWideEventService: DataClearingWideEventService?, completion: (@MainActor () -> Void)?) {
        XCTFail("Unexpected data clearing")
    }

    @MainActor
    func burnChatHistory() async -> Result<Void, Error> {
        XCTFail("Unexpected data clearing")
        return .success(())
    }
}
