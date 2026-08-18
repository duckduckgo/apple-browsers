//
//  UTIFooterController.swift
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

import Foundation
import os.log
import UIKit

@MainActor
protocol UTIFooterPresenting: AnyObject {
    func applyFooterMessage(_ message: UTIFooterMessage?)
}

@MainActor
final class UTIFooterController {

    typealias Animator = (_ changes: @escaping () -> Void) -> Void

    private enum Constants {
        static let duration: TimeInterval = 0.4
        static let damping: CGFloat = 0.85
    }

    weak var presenter: UTIFooterPresenting?

    var onAction: ((UTIFooterAction) -> Void)?

    private let provider: UTIFooterWarningProviding
    private let mapper: UTIFooterMessageMapper
    private let dateProvider: () -> Date
    private let animator: Animator

    private var lastWarning: UTIFooterWarning?
    private var dismissedWarnings: Set<UTIFooterWarning> = []
    private var isSuppressed = false

    private(set) var currentMessage: UTIFooterMessage?

    init(provider: UTIFooterWarningProviding,
         mapper: UTIFooterMessageMapper = UTIFooterMessageMapper(),
         dateProvider: @escaping () -> Date = Date.init,
         animator: Animator? = nil) {
        self.provider = provider
        self.mapper = mapper
        self.dateProvider = dateProvider
        self.animator = animator ?? Self.springAnimator
    }

    func refresh() {
        lastWarning = provider.currentWarning()
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] controller refresh → warning=\(String(describing: self.lastWarning), privacy: .public) suppressed=\(self.isSuppressed, privacy: .public)")
        applyCurrentState()
    }

    func resetForPoseChange() {
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] controller reset for pose change")
        lastWarning = nil
        currentMessage = nil
    }

    func setSuppressed(_ suppressed: Bool) {
        guard isSuppressed != suppressed else { return }
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] controller suppressed=\(suppressed, privacy: .public)")
        isSuppressed = suppressed
        applyCurrentState()
    }

    func dismissCurrent() {
        guard let lastWarning else { return }
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] controller dismissed \(String(describing: lastWarning), privacy: .public)")
        dismissedWarnings.insert(lastWarning)
        applyCurrentState()
    }

    func performPrimaryAction() {
        guard let action = currentMessage?.primaryAction?.action else { return }
        onAction?(action)
    }

    private func applyCurrentState() {
        let message = resolveMessage()
        guard message != currentMessage else {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] controller no-op: message unchanged (\(message == nil ? "nil" : "visible", privacy: .public))")
            return
        }
        Logger.duckAIUsageWarnings.debug("[UsageWarnings] controller applying: \(message?.title ?? "nil", privacy: .public)")
        currentMessage = message
        animator { [weak self] in
            self?.presenter?.applyFooterMessage(message)
        }
    }

    private func resolveMessage() -> UTIFooterMessage? {
        guard !isSuppressed else {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] nothing to show: suppressed (editing or Search mode)")
            return nil
        }
        guard let lastWarning else { return nil }
        guard !dismissedWarnings.contains(lastWarning) else {
            Logger.duckAIUsageWarnings.debug("[UsageWarnings] nothing to show: warning was dismissed this session")
            return nil
        }
        return mapper.message(for: lastWarning, now: dateProvider())
    }

    static let springAnimator: Animator = { changes in
        guard !UIAccessibility.isReduceMotionEnabled else {
            changes()
            return
        }
        UIView.animate(withDuration: Constants.duration,
                       delay: 0,
                       usingSpringWithDamping: Constants.damping,
                       initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction],
                       animations: changes)
    }
}
