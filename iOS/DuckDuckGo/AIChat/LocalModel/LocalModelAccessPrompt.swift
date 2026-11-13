//
//  LocalModelAccessPrompt.swift
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

import AIChat
import DesignResourcesKit
import DuckUI
import SwiftUI
import UIKit

/// Asks whether Duck.ai may use the local model, in a card over everything on screen, including the Duck.ai sheet.
@MainActor
final class LocalModelAccessPrompt: LocalModelAccessAsking {

    private let isPad: () -> Bool
    private weak var controller: UIViewController?
    private var answer: AIChatLocalModelAccessReply.Result?
    private var waiting: [CheckedContinuation<AIChatLocalModelAccessReply.Result, Never>] = []

    init(isPad: @escaping () -> Bool = { UIDevice.current.userInterfaceIdiom == .pad }) {
        self.isPad = isPad
    }

    func ask(in window: UIWindow?, modelName: String) async -> AIChatLocalModelAccessReply.Result {
        await withCheckedContinuation { continuation in
            waiting.append(continuation)
            // A second request while the card is up, from a double tap or another tab, gets the same answer.
            guard waiting.count == 1 else { return }
            if !show(in: window, modelName: modelName) {
                finish(.declined)
            }
        }
    }

    private func show(in window: UIWindow?, modelName: String) -> Bool {
        guard let root = window?.rootViewController else { return false }
        var presenter = root
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }

        let card = LocalModelAccessPromptView(modelName: modelName,
                                              message: isPad() ? UserText.localModelAccessPromptMessageIPad : UserText.localModelAccessPromptMessageIPhone,
                                              onAnswer: { [weak self] answer in self?.close(with: answer) })
        let controller = LocalModelAccessPromptHostingController(rootView: card) { [weak self] in
            guard let self else { return }
            self.finish(self.answer ?? .declined)
        }
        self.controller = controller
        presenter.present(controller, animated: true)
        // UIKit refuses to present over a screen that is already presenting, and the page would wait forever.
        return presenter.presentedViewController === controller
    }

    private func close(with answer: AIChatLocalModelAccessReply.Result) {
        guard self.answer == nil else { return }
        self.answer = answer
        controller?.dismiss(animated: true)
    }

    private func finish(_ result: AIChatLocalModelAccessReply.Result) {
        let waiting = self.waiting
        self.waiting = []
        answer = nil
        for continuation in waiting {
            continuation.resume(returning: result)
        }
    }
}

/// Every way the card goes away ends in `viewDidDisappear`: the buttons, a tap outside, or the sheet
/// or tab under it closing. So that's where the page gets its answer.
final class LocalModelAccessPromptHostingController: UIHostingController<LocalModelAccessPromptView> {

    private let onDisappear: () -> Void

    init(rootView: LocalModelAccessPromptView, onDisappear: @escaping () -> Void) {
        self.onDisappear = onDisappear
        super.init(rootView: rootView)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.accessibilityViewIsModal = true
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDisappear()
    }
}

struct LocalModelAccessPromptView: View {

    let modelName: String
    let message: String
    let onAnswer: (AIChatLocalModelAccessReply.Result) -> Void

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture { onAnswer(.declined) }

            // Scrolls when large text makes the card taller than the screen.
            GeometryReader { proxy in
                ScrollView {
                    VStack {
                        Spacer(minLength: 20)
                        card
                            .frame(maxWidth: 420)
                            .padding(.horizontal, 24)
                        Spacer(minLength: 20)
                    }
                    .frame(minHeight: proxy.size.height)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { onAnswer(.declined) }
                }
            }
        }
        .accessibilityAction(.escape) { onAnswer(.declined) }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            title

            Text(message)
                .daxBodyRegular()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(designSystemColor: .controlsFillPrimary)))

            HStack(spacing: 12) {
                Button(UserText.localModelAccessNoThanks) { onAnswer(.declined) }
                    .buttonStyle(SecondaryFillButtonStyle())
                    .accessibilityIdentifier("LocalModelAccessPrompt.noThanks")
                Button(UserText.localModelAccessTurnOn) { onAnswer(.allowed) }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("LocalModelAccessPrompt.turnOn")
            }
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous)
            .fill(Color(designSystemColor: .backgroundSheets)))
        // Taps inside the card must not count as a tap outside.
        .onTapGesture { }
    }

    /// One sentence for translators, laid out as in the design: the model's chip sits inside the sentence.
    private var title: some View {
        let parts = UserText.localModelAccessPromptTitle.components(separatedBy: "%@")
        let beforeModel = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
        let afterModel = parts.dropFirst().joined().trimmingCharacters(in: .whitespaces)
        return VStack(alignment: .leading, spacing: 6) {
            if !beforeModel.isEmpty {
                Text(beforeModel)
            }
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    AppleIntelligenceGlyph(size: 20)
                    Text(modelName)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .overlay(Capsule(style: .continuous).stroke(Color(designSystemColor: .lines), lineWidth: 1))
                if !afterModel.isEmpty {
                    Text(afterModel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .daxHeadline()
        .foregroundColor(Color(designSystemColor: .textPrimary))
        .accessibilityElement(children: .combine)
    }
}
