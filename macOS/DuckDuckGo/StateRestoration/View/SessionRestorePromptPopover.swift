//
//  SessionRestorePromptPopover.swift
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

import Foundation
import Persistence
import SwiftUIExtensions

final class SessionRestorePromptPopover: NSPopover {
    let ctaCallback: (Bool) -> Void

    init(ctaCallback: @escaping (Bool) -> Void) {
        self.ctaCallback = ctaCallback
        super.init()
        self.behavior = .applicationDefined
        setupContentController()
    }

    required init?(coder: NSCoder) {
        fatalError("\(Self.self): Bad initializer")
    }

    deinit {
#if DEBUG
        // Check that our content view controller deallocates
        contentViewController?.ensureObjectDeallocated(after: 1.0, do: .interrupt)
#endif
    }

    private func setupContentController() {
        /// Popover frame used for positioning is 26px wider than `contentSize.width`.
        /// Adjust the width to get the expected positioning.
        contentSize = NSSize(width: SessionRestorePromptView.Const.width - 26, height: 256)
        contentViewController = SessionRestorePromptViewController(ctaCallback: ctaCallback)
    }
}

final class SessionRestorePromptViewController: NSHostingController<SessionRestorePromptView> {
    private let viewModel: SessionRestorePromptViewModel

    init(ctaCallback: @escaping (Bool) -> Void) {
        self.viewModel = SessionRestorePromptViewModel(ctaCallback: ctaCallback)
        let view = SessionRestorePromptView(model: viewModel)
        super.init(rootView: view)
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
