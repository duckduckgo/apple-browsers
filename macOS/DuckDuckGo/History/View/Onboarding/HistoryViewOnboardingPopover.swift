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
        contentSize = .init(width: HistoryViewOnboardingView.Const.width, height: 200)
        setupContentController()
    }

    required init?(coder: NSCoder) {
        fatalError("\(Self.self): Bad initializer")
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
