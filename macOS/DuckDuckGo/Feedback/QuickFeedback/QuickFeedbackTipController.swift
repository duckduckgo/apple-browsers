//
//  QuickFeedbackTipController.swift
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
import Foundation
import Persistence

struct QuickFeedbackTipSettings: StoringKeys {
    let lastShown = StorageKey<Double>(.feedbackTipLastShown)
    let buttonClicked = StorageKey<Bool>(.feedbackTipButtonClicked)
}

@MainActor
final class QuickFeedbackTipController {

    // Internal only — not localized
    private static let messages = [
        "Dax wants YOU to report problems!",
        "Only YOU can prevent regressions!",
        "Spotted a bug? Dax wants to hear about it!",
        "Help Dax squash bugs, share your feedback!",
        "Deliver delight the Dax way, report a problem today!",
    ]

    #if DEBUG
    private static let showDelay: TimeInterval = 3
    private static let preClickInterval: TimeInterval = 30
    private static let postClickInterval: TimeInterval = 60
    private static let autoDismissDelay: TimeInterval = 5
    #else
    private static let showDelay: TimeInterval = 3
    private static let preClickInterval: TimeInterval = 86400      // 24 hours
    private static let postClickInterval: TimeInterval = 604800     // 7 days
    private static let autoDismissDelay: TimeInterval = 5
    #endif

    private var popover: NSPopover?
    private var autoDismissTimer: Timer?
    private var scheduledShowWork: DispatchWorkItem?
    private weak var anchorView: NSView?
    private let storage: any KeyedStoring<QuickFeedbackTipSettings>

    init(storage: (any KeyedStoring<QuickFeedbackTipSettings>)? = nil) {
        self.storage = if let storage { storage } else { UserDefaults.standard.keyedStoring() }
    }

    func scheduleIfNeeded(anchoredTo view: NSView) {
        anchorView = view
        scheduledShowWork?.cancel()

        guard shouldShow() else { return }

        let work = DispatchWorkItem { [weak self] in
            self?.showTip()
        }
        scheduledShowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showDelay, execute: work)
    }

    func recordButtonClick() {
        storage.buttonClicked = true
        dismissTip()
    }

    func dismissTip() {
        scheduledShowWork?.cancel()
        scheduledShowWork = nil
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        popover?.close()
        popover = nil
    }

    private func shouldShow() -> Bool {
        let lastShown = storage.lastShown ?? 0
        guard lastShown > 0 else { return true }

        let hasClicked = storage.buttonClicked ?? false
        let interval = hasClicked ? Self.postClickInterval : Self.preClickInterval
        let elapsed = Date().timeIntervalSince1970 - lastShown
        return elapsed >= interval
    }

    private func showTip() {
        guard let anchor = anchorView, anchor.window != nil else { return }
        guard shouldShow() else { return }

        let message = Self.messages.randomElement() ?? Self.messages[0]
        let viewController = QuickFeedbackTipViewController(message: message) { [weak self] in
            self?.dismissTip()
        }

        let tip = NSPopover()
        tip.contentViewController = viewController
        tip.behavior = .semitransient
        tip.animates = true
        popover = tip

        tip.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)

        storage.lastShown = Date().timeIntervalSince1970

        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: Self.autoDismissDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissTip()
            }
        }
    }
}

// MARK: - Tip Content View Controller

private final class QuickFeedbackTipViewController: NSViewController {

    private let message: String
    private let onDismiss: () -> Void

    init(message: String, onDismiss: @escaping () -> Void) {
        self.message = message
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 60))

        let daxIcon = NSImageView()
        daxIcon.translatesAutoresizingMaskIntoConstraints = false
        daxIcon.image = NSImage(named: "OnboardingDax")
        daxIcon.imageScaling = .scaleProportionallyDown

        let label = NSTextField(wrappingLabelWithString: message)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13)
        label.textColor = .labelColor
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBordered = false

        let dismissButton = NSButton()
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        dismissButton.bezelStyle = .inline
        dismissButton.isBordered = false
        dismissButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")
        dismissButton.imageScaling = .scaleProportionallyDown
        dismissButton.target = self
        dismissButton.action = #selector(dismissClicked)

        container.addSubview(daxIcon)
        container.addSubview(label)
        container.addSubview(dismissButton)

        NSLayoutConstraint.activate([
            daxIcon.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            daxIcon.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            daxIcon.widthAnchor.constraint(equalToConstant: 28),
            daxIcon.heightAnchor.constraint(equalToConstant: 28),

            label.leadingAnchor.constraint(equalTo: daxIcon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            dismissButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            dismissButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 20),
            dismissButton.heightAnchor.constraint(equalToConstant: 20),
        ])

        view = container
    }

    @objc private func dismissClicked() {
        onDismiss()
    }
}
