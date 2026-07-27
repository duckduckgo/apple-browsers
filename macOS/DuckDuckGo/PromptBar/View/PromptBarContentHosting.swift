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

/// What `PromptBarPresenter` needs from the bar's content.
@MainActor
protocol PromptBarContentHosting: AnyObject {

    var viewController: NSViewController { get }

    /// True while a menu, file picker or modal is up: those take key away, and must not dismiss the bar.
    var isPresentingAuxiliaryUI: Bool { get }

    /// Not `preferredContentSize`, which would collide with the `NSViewController` property conformers inherit.
    var preferredWindowContentSize: NSSize { get }

    var onPreferredWindowContentSizeChanged: ((NSSize) -> Void)? { get set }
    var onSubmit: (() -> Void)? { get set }

    func prepareForPresentation()

    /// Called once the window is key, when first responder assignment sticks.
    func focusPromptEditor()

    func resetAfterDismissal()
}
