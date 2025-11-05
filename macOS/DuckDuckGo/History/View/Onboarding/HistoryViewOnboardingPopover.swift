//
//  HistoryViewOnboardingPopover.swift
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

final class HistoryViewOnboardingPopover: NSPopover {
    let ctaCallback: (Bool) -> Void

    init(ctaCallback: @escaping (Bool) -> Void) {
        self.ctaCallback = ctaCallback
        super.init()
        self.behavior = .semitransient
        /// popover frame used for positioning is 26px wider than `contentSize.width`
        /// and makes the popover appear partially outside of the window.
        /// Subtract 12px to ensure that the popover is fully contained within the window.
        ///
        /// Height is an arbitrary value and it doesn't influence positioning. It will be
        /// updated with the actual height of the popover's SwiftUI view.
        contentSize = .init(width: HistoryViewOnboardingView.Const.width - 12, height: 200)
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
        contentViewController = HistoryViewOnboardingViewController(ctaCallback: ctaCallback)
    }
}

final class HistoryViewOnboardingViewController: NSHostingController<HistoryViewOnboardingView> {

    init(ctaCallback: @escaping (Bool) -> Void) {
        self.viewModel = HistoryViewOnboardingViewModel(ctaCallback: ctaCallback)
        let view = HistoryViewOnboardingView(model: viewModel)
        super.init(rootView: view)
    }

    @MainActor @preconcurrency required dynamic init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        viewModel.markAsShown()
    }

    private let viewModel: HistoryViewOnboardingViewModel
}
