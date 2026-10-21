//
//  PastedTextSheet.swift
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
import DesignResourcesKitIcons
import SwiftUI
import UIKit

enum PastedTextSheetMode: Equatable {
    case editable(limit: Int)
    /// A paste from a sent prompt: the web app matches returned pastes by content, so it can be read, not changed.
    case viewOnly
}

enum PastedTextSheetOutcome: Equatable {
    case saved(AIChatPastedText)
    case unchanged
}

enum PastedTextSheetSubtitle: Equatable {
    case size(String)
    case overLimit(count: Int, limit: Int)
}

struct PastedTextSheetRules: Equatable {
    let original: AIChatPastedText
    let mode: PastedTextSheetMode

    func count(of text: String) -> Int { text.utf16.count }

    func isOverLimit(_ text: String) -> Bool {
        guard case .editable(let limit) = mode else { return false }
        return count(of: text) > limit
    }

    func canSave(_ text: String) -> Bool {
        guard case .editable = mode else { return false }
        return !AIChatPromptLimits.isBlank(text) && !isOverLimit(text)
    }

    var opensWithKeyboard: Bool { mode != .viewOnly }

    var title: String { mode == .viewOnly ? UserText.aiChatPastedTextSheetTitle : UserText.aiChatPastedTextEditSheetTitle }

    func subtitle(for text: String, locale: Locale = .current) -> PastedTextSheetSubtitle {
        let count = count(of: text)
        guard case .editable(let limit) = mode else {
            return .size(UserText.aiChatPastedTextCharacterCount(count, formattedCount: Self.compact(count, locale: locale)))
        }
        guard count <= limit else { return .overLimit(count: count, limit: limit) }
        return .size(UserText.aiChatPastedTextCharacterCount(formattedCount: Self.compact(count, locale: locale),
                                                            limit: limit,
                                                            formattedLimit: Self.compact(limit, locale: locale)))
    }

    /// The design writes thousands with a lowercase k, e.g. 1.2k, where the formatter writes 1.2K.
    private static func compact(_ value: Int, locale: Locale) -> String {
        value.formatted(.number.notation(.compactName).locale(locale)).lowercased(with: locale)
    }

    func outcome(savingText text: String) -> PastedTextSheetOutcome {
        text == original.content ? .unchanged : .saved(AIChatPastedText(content: text))
    }
}

struct PastedTextSheetView: View {

    @State private var text: String
    @FocusState private var isTextFocused: Bool
    private let rules: PastedTextSheetRules
    private let onSave: (String) -> Void
    private let onCancel: () -> Void

    init(pastedText: AIChatPastedText, mode: PastedTextSheetMode, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: pastedText.content)
        rules = PastedTextSheetRules(original: pastedText, mode: mode)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var isViewOnly: Bool { rules.mode == .viewOnly }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if isViewOnly {
                    PastedTextReadOnlyView(text: text)
                } else {
                    TextEditor(text: $text)
                        .font(Font(PastedTextSheetMetrics.bodyFont()))
                        .lineSpacing(PastedTextSheetMetrics.bodyLineSpacing())
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .modifier(HiddenScrollContentBackground())
                        .focused($isTextFocused)
                }
            }
            .accessibilityIdentifier("PastedTextSheet.TextView")
            .padding(.horizontal, PastedTextSheetMetrics.bodyHorizontalPadding)
            .padding(.top, PastedTextSheetMetrics.bodyTopPadding)
        }
        .background(Color(designSystemColor: .backgroundTertiary).ignoresSafeArea())
        .onAppear { isTextFocused = rules.opensWithKeyboard }
    }

    /// A solid header of its own rather than a navigation bar, so the text never scrolls under a blurred bar.
    private var header: some View {
        ZStack(alignment: .top) {
            HStack {
                PastedTextSheetCircleButton(glyph: DesignSystemImages.Glyphs.Size24.close, style: .plain, action: onCancel)
                    .accessibilityLabel(isViewOnly ? UserText.navigationTitleDone : UserText.actionCancel)
                    .accessibilityIdentifier("PastedTextSheet.Cancel")
                Spacer()
                if !isViewOnly {
                    PastedTextSheetCircleButton(glyph: DesignSystemImages.Glyphs.Size24.check, style: .prominent) { onSave(text) }
                        .disabled(!rules.canSave(text))
                        .accessibilityLabel(UserText.actionSave)
                        .accessibilityIdentifier("PastedTextSheet.Save")
                }
            }
            VStack(spacing: 0) {
                Text(rules.title)
                    .daxButton()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .daxCaption1()
                    .accessibilityIdentifier("PastedTextSheet.Count")
            }
            .lineLimit(1)
            .padding(.top, PastedTextSheetMetrics.titleTopPadding)
        }
        .padding(.horizontal, PastedTextSheetMetrics.headerHorizontalPadding)
        .padding(.top, PastedTextSheetMetrics.grabberHeight)
        .padding(.bottom, PastedTextSheetMetrics.headerBottomPadding)
    }

    private var subtitle: AttributedString {
        let secondary = Color(designSystemColor: .textSecondary)
        switch rules.subtitle(for: text) {
        case .size(let size):
            var line = AttributedString(size)
            line.foregroundColor = secondary
            return line
        case .overLimit(let count, let limit):
            var line = AttributedString(String(format: UserText.aiChatPromptTooLongCountFormat, count, limit))
            line.foregroundColor = secondary
            if let range = line.range(of: String(count)) {
                line[range].foregroundColor = Color(designSystemColor: .destructivePrimary)
            }
            return line
        }
    }
}

private enum PastedTextSheetMetrics {
    static let grabberHeight: CGFloat = 16
    static let headerHorizontalPadding: CGFloat = 16
    static let headerBottomPadding: CGFloat = 10
    static let titleTopPadding: CGFloat = 5
    static let buttonSize: CGFloat = 44
    /// UITextView pads 8pt above the first line and 5pt before each line, so these land the text 16pt below the header and 32pt from the edges.
    static let bodyHorizontalPadding: CGFloat = 27
    static let bodyTopPadding: CGFloat = 8
    static let bodyFontSize: CGFloat = 16
    static let bodyLineHeight: CGFloat = 24

    static func bodyFont() -> UIFont {
        let font = UIFont(name: "DuckSansProduct-Regular", size: bodyFontSize) ?? .systemFont(ofSize: bodyFontSize)
        return UIFontMetrics(forTextStyle: .body).scaledFont(for: font)
    }

    static func bodyLineSpacing() -> CGFloat {
        max(0, UIFontMetrics(forTextStyle: .body).scaledValue(for: bodyLineHeight) - bodyFont().lineHeight)
    }
}

private struct HiddenScrollContentBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

private struct PastedTextSheetCircleButton: View {
    enum Style {
        case plain
        case prominent
    }

    let glyph: UIImage
    let style: Style
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    private var isProminent: Bool { style == .prominent && isEnabled }

    var body: some View {
        Button(action: action) {
            Image(uiImage: glyph)
                .renderingMode(.template)
                .foregroundColor(Color(designSystemColor: isProminent ? .accentContentPrimary : (isEnabled ? .icons : .iconsTertiary)))
                .frame(width: PastedTextSheetMetrics.buttonSize, height: PastedTextSheetMetrics.buttonSize)
                .modifier(PastedTextSheetCircleBackground(isProminent: isProminent))
        }
        .buttonStyle(.plain)
    }
}

private struct PastedTextSheetCircleBackground: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(isProminent ? .regular.tint(Color(designSystemColor: .accentPrimary)).interactive() : .regular.interactive(),
                                in: Circle())
        } else {
            content.background(Circle().fill(Color(designSystemColor: isProminent ? .accentPrimary : .controlsFillPrimary)))
        }
    }
}

/// A disabled `TextEditor` cannot scroll, so the view-only sheet shows its text in a `UITextView` that scrolls and selects but never edits.
private struct PastedTextReadOnlyView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard textView.text != text else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = PastedTextSheetMetrics.bodyLineSpacing()
        textView.attributedText = NSAttributedString(string: text, attributes: [
            .font: PastedTextSheetMetrics.bodyFont(),
            .foregroundColor: UIColor(designSystemColor: .textPrimary),
            .paragraphStyle: paragraph
        ])
    }
}

@MainActor
enum PastedTextSheetPresenter {

    static func present(_ pastedText: AIChatPastedText,
                        mode: PastedTextSheetMode,
                        from host: UIViewController,
                        completion: @escaping (PastedTextSheetOutcome) -> Void) {
        let rules = PastedTextSheetRules(original: pastedText, mode: mode)
        weak var weakController: PastedTextSheetHostingController?
        let view = PastedTextSheetView(
            pastedText: pastedText,
            mode: mode,
            onSave: { text in
                weakController?.finish(rules.outcome(savingText: text))
                weakController?.dismiss(animated: true)
            },
            onCancel: {
                weakController?.dismiss(animated: true)
            }
        )
        let controller = PastedTextSheetHostingController(rootView: view, completion: completion)
        controller.modalPresentationStyle = .formSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        weakController = controller
        topmost(from: host).present(controller, animated: true)
    }

    static func topmost(from host: UIViewController) -> UIViewController {
        var top = host
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

final class PastedTextSheetHostingController: UIHostingController<PastedTextSheetView> {

    private var completion: ((PastedTextSheetOutcome) -> Void)?

    init(rootView: PastedTextSheetView, completion: @escaping (PastedTextSheetOutcome) -> Void) {
        self.completion = completion
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func finish(_ outcome: PastedTextSheetOutcome) {
        guard let completion else { return }
        self.completion = nil
        completion(outcome)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }
        finish(.unchanged)
    }
}
