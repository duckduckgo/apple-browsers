//
//  PromptBarContentHosting.swift
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

/// What `PromptBarPresenter` needs from the bar's content, so presentation and dismissal can be
/// tested without building the Duck.ai prompt stack.
@MainActor
protocol PromptBarContentHosting: AnyObject {

    var viewController: NSViewController { get }

    /// True while a tool menu, file picker or modal is on screen. The presenter suppresses
    /// dismiss-on-resign-key while it holds, otherwise opening the file picker would close the bar.
    var isPresentingAuxiliaryUI: Bool { get }

    /// Window content size the current text and attachments need. Named to avoid colliding with
    /// `NSViewController.preferredContentSize`, which conforming view controllers already inherit.
    var preferredWindowContentSize: NSSize { get }

    /// Fires when `preferredWindowContentSize` changes, e.g. as the prompt wraps onto another line.
    var onPreferredWindowContentSizeChanged: ((NSSize) -> Void)? { get set }

    /// Fires once the prompt has been handed off to Duck.ai; the presenter dismisses in response.
    var onSubmit: (() -> Void)? { get set }

    /// Called before the window is shown, to refresh state that may have changed since last time.
    func prepareForPresentation()

    /// Called once the window is key, when first responder assignment actually sticks.
    func focusPromptEditor()

    /// Called after dismissal, to clear the draft so the next presentation starts clean.
    func resetAfterDismissal()
}
