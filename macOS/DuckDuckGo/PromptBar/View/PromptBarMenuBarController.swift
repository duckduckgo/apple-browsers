//
//  PromptBarMenuBarController.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI

/// The part of `NSStatusItem` this controller drives, so tests can substitute a
/// detached item instead of installing one in the system menu bar.
@MainActor
protocol PromptBarStatusItem: AnyObject {
    var button: NSStatusBarButton? { get }
    var isVisible: Bool { get set }
}

extension NSStatusItem: PromptBarStatusItem {}

/// Manages the Prompt Bar's duck.ai icon in the macOS menu bar.
@MainActor
final class PromptBarMenuBarController: NSObject {

    private let makeStatusItem: @MainActor () -> PromptBarStatusItem
    private var statusItem: PromptBarStatusItem?

    var onClick: (() -> Void)?

    private var tipPopover: NSPopover?
    private var onTipLinkClicked: (() -> Void)?

    /// - Parameter makeStatusItem: Injectable for testing; defaults to a real menu bar item.
    init(makeStatusItem: @escaping @MainActor () -> PromptBarStatusItem = { NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength) }) {
        self.makeStatusItem = makeStatusItem
        super.init()
    }

    private func configureStatusItem(_ statusItem: PromptBarStatusItem) {
        guard let button = statusItem.button else { return }

        button.image = DesignSystemImages.Glyphs.Size16.duckAi
        button.image?.isTemplate = true
        button.setAccessibilityIdentifier("PromptBar.menuBarIcon")
        button.target = self
        button.action = #selector(statusBarButtonTapped)
    }

    @objc
    private func statusBarButtonTapped() {
        onClick?()
    }

    /// The item is created on first show: `NSStatusBar` puts it on screen as soon
    /// as it exists, so it must not be created while the icon should be hidden.
    func show() {
        if statusItem == nil {
            let statusItem = makeStatusItem()
            self.statusItem = statusItem
            configureStatusItem(statusItem)
        }
        statusItem?.isVisible = true
    }

    func hide() {
        statusItem?.isVisible = false
    }

    // ponytail: skipped on macOS 12 and when the item has no screen (e.g. hidden behind the notch); no retry.
    func showTip(shortcut: PromptBarShortcut, onLinkClicked: @escaping () -> Void) {
        guard #available(macOS 13, *),
              let button = statusItem?.button, button.window?.screen != nil else { return }

        let colorScheme: ColorScheme = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        let keyCaps = ImageRenderer(content: HStack(spacing: 3) {
            ForEach(Array((shortcut.modifierSymbols + [shortcut.keyDisplayString]).enumerated()), id: \.offset) { _, label in
                PromptBarShortcutRecorderView.KeyCapChip(label: label, compact: true)
            }
        }
        .padding(1)
        .environment(\.colorScheme, colorScheme))
        keyCaps.scale = button.window?.backingScaleFactor ?? 2
        guard let keyCapsImage = keyCaps.nsImage else { return }
        keyCapsImage.accessibilityDescription = shortcut.displayString

        // AppKit text rather than SwiftUI: SwiftUI links don't show the pointing hand on macOS.
        let font = NSFont.systemFont(ofSize: 13)
        let keyCapsAttachment = NSTextAttachment()
        keyCapsAttachment.image = keyCapsImage
        // Centred on the cap height instead of sitting on the baseline.
        keyCapsAttachment.bounds = CGRect(x: 0,
                                          y: (font.capHeight - keyCapsImage.size.height) / 2,
                                          width: keyCapsImage.size.width,
                                          height: keyCapsImage.size.height)

        let tip = UserText.duckAiLauncherMenuBarTip
        let bodyAttributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
        let text = NSMutableAttributedString(string: tip.beforeShortcut, attributes: bodyAttributes)
        text.append(NSAttributedString(attachment: keyCapsAttachment))
        let afterShortcut = NSMutableAttributedString(attributedString: NSAttributedString(tip.afterShortcut))
        afterShortcut.addAttributes(bodyAttributes, range: NSRange(location: 0, length: afterShortcut.length))
        text.append(afterShortcut)

        let width: CGFloat = 260
        let padding: CGFloat = 12
        let textView = NSTextView(frame: NSRect(x: padding, y: padding, width: width, height: 0))
        textView.delegate = self
        textView.isEditable = false
        textView.isSelectable = true // Required for link clicks to reach the delegate.
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.linkTextAttributes = [
            .foregroundColor: NSColor(designSystemColor: .textLink),
            .cursor: NSCursor.pointingHand
        ]
        textView.textStorage?.setAttributedString(text)
        textView.setAccessibilityLabel(text.string.replacingOccurrences(of: "\u{FFFC}", with: shortcut.displayString))
        if let layoutManager = textView.layoutManager, let textContainer = textView.textContainer {
            layoutManager.ensureLayout(for: textContainer)
            textView.frame.size.height = ceil(layoutManager.usedRect(for: textContainer).height)
        }

        let viewController = NSViewController()
        viewController.view = NSView(frame: NSRect(x: 0, y: 0, width: width + padding * 2, height: textView.frame.height + padding * 2))
        viewController.view.addSubview(textView)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = viewController
        popover.contentSize = viewController.view.frame.size
        tipPopover = popover
        onTipLinkClicked = onLinkClicked
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

extension PromptBarMenuBarController: NSTextViewDelegate {

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        tipPopover?.close()
        onTipLinkClicked?()
        return true
    }
}
