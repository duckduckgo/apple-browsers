//
//  LocalModelAccessPrompt.swift
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

import AIChat
import AppKit
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI
import SwiftUIExtensions
import WebKit

@MainActor
protocol LocalModelAccessAsking: AnyObject {
    /// `.allowed` means Turn On for a model on the device, or Install for one that needs a download.
    func ask(from webView: WKWebView?, request: AIChatLocalModelAccessRequest) async -> AIChatLocalModelAccessReply.Result
}

/// Asks whether Duck.ai may use the local model, in a pop-up at the window's Duck.ai button.
@MainActor
final class LocalModelAccessPrompt: NSObject, LocalModelAccessAsking {

    private let themeManager: ThemeManager
    private let instrumentation: AIChatLocalModelInstrumentation
    private weak var translateOffers: BrowserToolPermissionPromptPresenter?
    private var popover: NSPopover?
    private var answer: AIChatLocalModelAccessReply.Result?
    private var isInstallPrompt = false
    private var waiting: [CheckedContinuation<AIChatLocalModelAccessReply.Result, Never>] = []

    init(themeManager: ThemeManager,
         instrumentation: AIChatLocalModelInstrumentation = LocalModelPixelInstrumentation(),
         translateOffers: BrowserToolPermissionPromptPresenter? = nil) {
        self.themeManager = themeManager
        self.instrumentation = instrumentation
        self.translateOffers = translateOffers
    }

    func ask(from webView: WKWebView?, request: AIChatLocalModelAccessRequest) async -> AIChatLocalModelAccessReply.Result {
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
            // A second request while the pop-up is up, from a double click or another window, gets the same answer.
            guard popover == nil else { return }
            if show(from: webView, request: request) {
                // The pixels only know Apple Intelligence so far, so an Install pop-up would count as its offer.
                if case .install = request {
                    isInstallPrompt = true
                } else {
                    instrumentation.fire(.promoShown)
                }
            } else {
                finish(.declined)
            }
        }
    }

    private func show(from webView: WKWebView?, request: AIChatLocalModelAccessRequest) -> Bool {
        // AppKit skips the pop-up for a hidden window.
        guard let webView, let window = webView.window, window.isVisible else { return false }
        // Before the anchor is picked: the offer it closes may have been all that revealed the Duck.ai button.
        translateOffers?.localModelPromptWillShow(in: window)

        let content = LocalModelAccessPromptView(themeManager: themeManager,
                                                 request: request,
                                                 onNoThanks: { [weak self] in self?.close(with: .declined) },
                                                 onAccept: { [weak self] in self?.close(with: .allowed) })
        let controller = NSHostingController(rootView: content)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = controller
        popover.contentSize = controller.view.fittingSize
        self.popover = popover

        if let button = duckAIButton(in: webView.window) {
            popover.show(positionedBelow: button)
        } else {
            // The button can be hidden in Settings, and a floating Duck.ai window has none.
            let top = webView.isFlipped ? webView.bounds.minY : webView.bounds.maxY - 1
            popover.show(positionedBelow: NSRect(x: webView.bounds.midX, y: top, width: 1, height: 1), in: webView)
        }
        // AppKit skips the pop-up for a hidden window, and a pop-up that never shows never closes to answer the page.
        return popover.isShown
    }

    private func duckAIButton(in window: NSWindow?) -> NSView? {
        guard let mainWindowController = window?.windowController as? MainWindowController,
              let button = mainWindowController.mainViewController.tabBarViewController.duckAISplitButtonContainer,
              !button.isHiddenOrHasHiddenAncestor,
              button.window != nil else { return nil }
        return button
    }

    private func close(with answer: AIChatLocalModelAccessReply.Result) {
        self.answer = answer
        popover?.close()
    }

    private func finish(_ result: AIChatLocalModelAccessReply.Result) {
        let waiting = self.waiting
        self.waiting = []
        translateOffers?.localModelPromptDidClose()
        popover = nil
        answer = nil
        isInstallPrompt = false
        for continuation in waiting {
            continuation.resume(returning: result)
        }
    }
}

extension LocalModelAccessPrompt: NSPopoverDelegate {

    /// Every way the pop-up closes ends here, so Escape or a click outside answers `declined`.
    func popoverDidClose(_ notification: Notification) {
        let result = answer ?? .declined
        if result == .declined, !isInstallPrompt {
            instrumentation.fire(.promoClosed)
        }
        finish(result)
    }
}

struct LocalModelAccessPromptView: View {

    @ObservedObject var themeManager: ThemeManager
    let request: AIChatLocalModelAccessRequest
    let onNoThanks: () -> Void
    let onAccept: () -> Void

    private var isInstall: Bool {
        if case .install = request { return true }
        return false
    }

    private var titleFormat: String {
        UserText.localModelPromptTitle
    }

    private var message: String {
        switch request {
        case .connect(let model):
            return String(format: UserText.localModelPromptMessage, model.name)
        case .install(let model, _):
            return String(format: UserText.localModelPromptMessage, model.name) + "\n\n" + UserText.localModelInstallPromptFutureUse
        }
    }

    private var acceptTitle: String {
        switch request {
        case .connect:
            return UserText.localModelConnect
        case .install(_, let bytes):
            return String(format: UserText.localModelInstallButton, ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            title

            Text(message)
                .font(.system(size: 13))
                .foregroundColor(color(.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color(.controlsFillPrimary)))

            HStack(spacing: 8) {
                Spacer()
                Button(action: onNoThanks) {
                    buttonLabel(UserText.localModelAccessNoThanks)
                }
                .buttonStyle(DismissActionButtonStyle(topPadding: 0, bottomPadding: 0, pillShape: true, stateColors: .themedDismissButton))
                .accessibilityIdentifier("LocalModelAccessPrompt.noThanks")

                Button(action: onAccept) {
                    buttonLabel(acceptTitle)
                }
                .buttonStyle(DefaultActionButtonStyle(enabled: true, topPadding: 0, bottomPadding: 0, stateColors: .themedActionButton, pillShape: true))
                .accessibilityIdentifier(isInstall ? "LocalModelAccessPrompt.install" : "LocalModelAccessPrompt.turnOn")
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    /// One sentence for translators, laid out as in the design: the model's chip ends the first line.
    private var title: some View {
        let parts = titleFormat.components(separatedBy: "%@")
        let beforeModel = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let afterModel = parts.dropFirst().joined().trimmingCharacters(in: .whitespaces)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if !beforeModel.isEmpty {
                    Text(beforeModel)
                }
                HStack(spacing: 6) {
                    switch request {
                    case .connect:
                        AppleIntelligenceGlyph(size: 16)
                    case .install:
                        Image(nsImage: DesignSystemImages.Glyphs.Size12.chip)
                            .foregroundColor(color(.iconsPrimary))
                            .accessibilityHidden(true)
                    }
                    Text(UserText.localModelPromptChip)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(Capsule(style: .continuous).stroke(color(.containerBorderPrimary), lineWidth: 1))
            }
            if !afterModel.isEmpty {
                Text(afterModel)
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(color(.textPrimary))
        .accessibilityElement(children: .combine)
    }

    private func buttonLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 8)
            .frame(height: 28)
    }

    private func color(_ color: DesignSystemColor) -> Color {
        Color(designSystemColor: color, palette: themeManager.designColorPalette)
    }
}
