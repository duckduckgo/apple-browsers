//
//  AutofillPromptKeyboardHandlerTests.swift
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

import UIKit
import Testing
@testable import DuckDuckGo

@MainActor
final class AutofillPromptKeyboardHandlerTests {

    private let notificationCenter = NotificationCenter()
    private let window = TestWindow()
    private let webView = EditingView()
    private var prompt: PromptViewController! = PromptViewController()
    private var firstResponder: UIResponder?
    private var firstResponderQueryCount = 0
    private var handler: AutofillPromptKeyboardHandler!
    private weak var releasedPrompt: PromptViewController?
    private weak var releasedHandler: AutofillPromptKeyboardHandler?

    init() {
        window.addSubview(webView)
        let field = UIView()
        webView.addSubview(field)
        firstResponder = field
        prompt.presenter = UIViewController()
        handler = AutofillPromptKeyboardHandler(notificationCenter: notificationCenter) { [weak self] in
            self?.firstResponderQueryCount += 1
            return self?.firstResponder
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func doesNotObserveUntilPromptIsPrepared() {
        postKeyboardWillShow()

        #expect(webView.endEditingCalls.isEmpty)
        #expect(firstResponderQueryCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func suppressesWebViewKeyboardWhilePromptIsPresented() {
        handler.startObserving(for: prompt, webView: webView)

        postKeyboardWillShow()

        #expect(webView.endEditingCalls == [true])
        #expect(webView.resignFirstResponderCallCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func doesNotSuppressKeyboardForResponderOutsideWebView() {
        firstResponder = prompt.view
        handler.startObserving(for: prompt, webView: webView)

        postKeyboardWillShow()

        #expect(webView.endEditingCalls.isEmpty)
        #expect(webView.resignFirstResponderCallCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func doesNotSuppressKeyboardWithoutFirstResponder() {
        firstResponder = nil
        handler.startObserving(for: prompt, webView: webView)

        postKeyboardWillShow()

        #expect(webView.endEditingCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func doesNotSuppressKeyboardInNonKeyWindow() {
        window.reportsKeyWindow = false
        handler.startObserving(for: prompt, webView: webView)

        postKeyboardWillShow()

        #expect(webView.endEditingCalls.isEmpty)
        #expect(firstResponderQueryCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func doesNotSuppressKeyboardForDetachedWebView() {
        webView.removeFromSuperview()
        handler.startObserving(for: prompt, webView: webView)

        postKeyboardWillShow()

        #expect(webView.endEditingCalls.isEmpty)
        #expect(firstResponderQueryCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func dismissedPromptAllowsKeyboardAndStopsObserving() {
        handler.startObserving(for: prompt, webView: webView)
        prompt.presenter = nil

        postKeyboardWillShow()
        prompt.presenter = UIViewController()
        postKeyboardWillShow()

        #expect(webView.endEditingCalls.isEmpty)
        #expect(webView.resignFirstResponderCallCount == 0)
        #expect(firstResponderQueryCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func handlerDoesNotRetainPrompt() {
        handler.startObserving(for: prompt, webView: webView)
        releasedPrompt = prompt
        prompt = nil

        postKeyboardWillShow()

        #expect(releasedPrompt == nil)
        #expect(webView.endEditingCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func preparingPromptAgainDoesNotDuplicateObservation() {
        handler.startObserving(for: prompt, webView: webView)
        handler.startObserving(for: prompt, webView: webView)

        postKeyboardWillShow()

        #expect(webView.endEditingCalls == [true])
        #expect(firstResponderQueryCount == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func newPromptUsesCurrentWebView() {
        handler.startObserving(for: prompt, webView: webView)
        let newPrompt = PromptViewController()
        newPrompt.presenter = UIViewController()
        let newWebView = EditingView()
        window.addSubview(newWebView)
        firstResponder = newWebView
        handler.startObserving(for: newPrompt, webView: newWebView)
        prompt.presenter = nil

        postKeyboardWillShow()

        #expect(webView.endEditingCalls.isEmpty)
        #expect(newWebView.endEditingCalls == [true])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func stopObservingAllowsKeyboardWhilePromptStillExists() {
        handler.startObserving(for: prompt, webView: webView)
        handler.stopObserving()

        postKeyboardWillShow()

        #expect(webView.endEditingCalls.isEmpty)
        #expect(firstResponderQueryCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func releasingHandlerStopsObservation() {
        handler.startObserving(for: prompt, webView: webView)
        releasedHandler = handler
        handler = nil

        postKeyboardWillShow()

        #expect(releasedHandler == nil)
        #expect(firstResponderQueryCount == 0)
    }

    private func postKeyboardWillShow() {
        notificationCenter.post(name: UIResponder.keyboardWillShowNotification, object: nil)
    }
}

private final class TestWindow: UIWindow {
    var reportsKeyWindow = true

    override var isKeyWindow: Bool { reportsKeyWindow }
}

private final class PromptViewController: UIViewController {
    var presenter: UIViewController?

    override var presentingViewController: UIViewController? { presenter }
}

private final class EditingView: UIView {
    var endEditingCalls: [Bool] = []
    var resignFirstResponderCallCount = 0

    override func endEditing(_ force: Bool) -> Bool {
        endEditingCalls.append(force)
        return true
    }

    override func resignFirstResponder() -> Bool {
        resignFirstResponderCallCount += 1
        return true
    }
}
