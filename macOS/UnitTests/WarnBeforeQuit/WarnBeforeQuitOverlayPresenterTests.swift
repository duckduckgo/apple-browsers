//
//  WarnBeforeQuitOverlayPresenterTests.swift
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

import AppKit
import Combine
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class WarnBeforeQuitOverlayPresenterTests: XCTestCase, Sendable {

    func testWhenQuitIsCancelledThenDidHideReportsCancellationAfterRemovingOverlay() async throws {
        let context = try await makePresentedQuitWarning()
        defer { context.cleanUp() }

        let result = try await completeQuitWarning(context, shouldProceed: false)

        XCTAssertTrue(result.notification.object as? NSWindow === context.window)
        XCTAssertEqual(result.notification.userInfo?[WarnBeforeQuitOverlayPresenter.UserInfoKeys.shouldProceed] as? Bool, false)
        XCTAssertFalse(result.hadParent)
        XCTAssertFalse(result.wasVisible)
        XCTAssertFalse(result.hadOverlayWindow)
    }

    func testWhenQuitIsConfirmedThenDidHideReportsProceedingAfterRemovingOverlay() async throws {
        let context = try await makePresentedQuitWarning()
        defer { context.cleanUp() }

        let result = try await completeQuitWarning(context, shouldProceed: true)

        XCTAssertTrue(result.notification.object as? NSWindow === context.window)
        XCTAssertEqual(result.notification.userInfo?[WarnBeforeQuitOverlayPresenter.UserInfoKeys.shouldProceed] as? Bool, true)
        XCTAssertFalse(result.hadParent)
        XCTAssertFalse(result.wasVisible)
        XCTAssertFalse(result.hadOverlayWindow)
    }

    private struct QuitWarningContext {
        let notificationCenter: NotificationCenter
        let window: NSWindow
        let focusedWindow: NSWindow
        let presenter: WarnBeforeQuitOverlayPresenter
        let continuation: AsyncStream<WarnBeforeQuitManager.State>.Continuation

        @MainActor
        func cleanUp() {
            continuation.finish()
            if let overlay = presenter.overlayWindow {
                overlay.parent?.removeChildWindow(overlay)
                overlay.orderOut(nil)
            }
            window.removeChildWindow(focusedWindow)
            focusedWindow.close()
            window.close()
        }
    }

    private struct DidHideResult {
        let notification: Notification
        let hadParent: Bool
        let wasVisible: Bool
        let hadOverlayWindow: Bool
    }

    private func makePresentedQuitWarning() async throws -> QuitWarningContext {
        let notificationCenter = NotificationCenter()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        let focusedWindow = NSWindow(contentRect: window.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        focusedWindow.isReleasedWhenClosed = false
        window.addChildWindow(focusedWindow, ordered: .above)

        let presenter = WarnBeforeQuitOverlayPresenter(windowProvider: { focusedWindow }, notificationCenter: notificationCenter)
        let (stream, continuation) = AsyncStream<WarnBeforeQuitManager.State>.makeStream()
        let context = QuitWarningContext(notificationCenter: notificationCenter, window: window, focusedWindow: focusedWindow,
                                         presenter: presenter, continuation: continuation)

        let willShow = expectation(description: "Quit warning will show")
        willShow.assertForOverFulfill = true
        let willShowSubscription = notificationCenter.notificationPublisher(for: WarnBeforeQuitOverlayPresenter.willShowNotification)
            .sink { notification in
                XCTAssertTrue(notification.object as? NSWindow === window)
                XCTAssertNil(presenter.overlayWindow?.parent)
                willShow.fulfill()
            }
        defer { willShowSubscription.cancel() }

        presenter.subscribe(to: stream)
        continuation.yield(.keyDown)
        await fulfillment(of: [willShow], timeout: 2)

        let overlay: NSWindow
        do {
            overlay = try XCTUnwrap(presenter.overlayWindow)
        } catch {
            context.cleanUp()
            throw error
        }
        XCTAssertTrue(overlay.parent === focusedWindow)
        XCTAssertTrue(overlay.isVisible)
        return context
    }

    private func completeQuitWarning(_ context: QuitWarningContext, shouldProceed: Bool) async throws -> DidHideResult {
        let overlay = try XCTUnwrap(context.presenter.overlayWindow)
        var result: DidHideResult?
        let didHide = expectation(description: "Quit warning did hide")
        didHide.assertForOverFulfill = true
        let didHideSubscription = context.notificationCenter.notificationPublisher(for: WarnBeforeQuitOverlayPresenter.didHideNotification)
            .sink { notification in
                result = DidHideResult(notification: notification, hadParent: overlay.parent != nil, wasVisible: overlay.isVisible,
                                       hadOverlayWindow: context.presenter.overlayWindow != nil)
                didHide.fulfill()
            }
        defer { didHideSubscription.cancel() }

        context.continuation.yield(.completed(shouldProceed: shouldProceed))
        await fulfillment(of: [didHide], timeout: 2)
        return try XCTUnwrap(result)
    }
}
