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

struct PastedTextSheetSubtitle: Equatable {
    let count: Int
    let limit: Int

    var isOverLimit: Bool { count > limit }

    /// Built from the format's pieces around `%1$d` so the count keeps its colour wherever a translation puts it.
    func attributed(format: String = UserText.aiChatPastedTextCountFormat, locale: Locale = .current) -> AttributedString {
        let pieces = PromptLengthText.positional(format).components(separatedBy: "%1$d")
        guard pieces.count == 2 else {
            return Self.secondary(PromptLengthText.format(format, count, limit, locale: locale))
        }
        var countText = AttributedString(PromptLengthText.number(count, locale: locale))
        countText.foregroundColor = Color(designSystemColor: isOverLimit ? .destructivePrimary : .textPrimary)
        return Self.secondary(limitFilled(pieces[0], locale: locale)) + countText + Self.secondary(limitFilled(pieces[1], locale: locale))
    }

    func accessibilityLabel(locale: Locale = .current) -> String {
        PromptLengthText.format(UserText.aiChatPastedTextCountAccessibilityFormat, count, limit, locale: locale)
    }

    private func limitFilled(_ piece: String, locale: Locale) -> String {
        piece.replacingOccurrences(of: "%2$d", with: PromptLengthText.number(limit, locale: locale))
            .replacingOccurrences(of: "%%", with: "%")
    }

    private static func secondary(_ text: String) -> AttributedString {
        var line = AttributedString(text)
        line.foregroundColor = Color(designSystemColor: .textSecondary)
        return line
    }
}

struct PastedTextSheetRules: Equatable {
    let original: AIChatPastedText
    let mode: PastedTextSheetMode

    func count(of text: String) -> Int { text.utf16.count }

    /// Saving over the limit lets the user trim several pastes in turn; the input's too-long error keeps Send off until the prompt fits.
    func canSave(_ text: String) -> Bool {
        guard case .editable = mode else { return false }
        return !AIChatPromptLimits.isBlank(text)
    }

    var opensWithKeyboard: Bool { mode != .viewOnly }

    var title: String { mode == .viewOnly ? UserText.aiChatPastedTextSheetTitle : UserText.aiChatPastedTextEditSheetTitle }

    /// The view-only sheet has no limit to count against, so it carries no subtitle.
    func subtitle(for text: String) -> PastedTextSheetSubtitle? {
        guard case .editable(let limit) = mode else { return nil }
        return PastedTextSheetSubtitle(count: count(of: text), limit: limit)
    }

    func hasUnsavedEdits(_ text: String) -> Bool {
        mode != .viewOnly && text != original.content
    }

    func outcome(savingText text: String) -> PastedTextSheetOutcome {
        text == original.content ? .unchanged : .saved(AIChatPastedText(content: text))
    }
}

struct PastedTextSheetView: View {

    @State private var text: String
    @FocusState private var isTextFocused: Bool
    @Environment(\.sizeCategory) private var sizeCategory
    private let rules: PastedTextSheetRules
    private let onSave: (String) -> Void
    private let onCancel: () -> Void
    let onUnsavedEditsChanged: (Bool) -> Void

    init(pastedText: AIChatPastedText,
         mode: PastedTextSheetMode,
         onSave: @escaping (String) -> Void,
         onCancel: @escaping () -> Void,
         onUnsavedEditsChanged: @escaping (Bool) -> Void = { _ in }) {
        _text = State(initialValue: pastedText.content)
        rules = PastedTextSheetRules(original: pastedText, mode: mode)
        self.onSave = onSave
        self.onCancel = onCancel
        self.onUnsavedEditsChanged = onUnsavedEditsChanged
    }

    private var isViewOnly: Bool { rules.mode == .viewOnly }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if isViewOnly {
                    PastedTextReadOnlyView(text: text, sizeCategory: sizeCategory)
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
        .onChange(of: text) { onUnsavedEditsChanged(rules.hasUnsavedEdits($0)) }
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
                if let subtitle = rules.subtitle(for: text) {
                    Text(subtitle.attributed())
                        .daxCaption1()
                        .accessibilityLabel(subtitle.accessibilityLabel())
                        .accessibilityIdentifier("PastedTextSheet.Count")
                }
            }
            .lineLimit(1)
            .padding(.horizontal, PastedTextSheetMetrics.buttonSize + PastedTextSheetMetrics.titleButtonGap)
            .padding(.top, PastedTextSheetMetrics.titleTopPadding)
        }
        .padding(.horizontal, PastedTextSheetMetrics.headerHorizontalPadding)
        .padding(.top, PastedTextSheetMetrics.grabberHeight)
        .padding(.bottom, PastedTextSheetMetrics.headerBottomPadding)
    }
}

private enum PastedTextSheetMetrics {
    static let grabberHeight: CGFloat = 16
    static let headerHorizontalPadding: CGFloat = 16
    static let headerBottomPadding: CGFloat = 10
    static let titleTopPadding: CGFloat = 5
    static let buttonSize: CGFloat = 44
    static let titleButtonGap: CGFloat = 8
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
    /// The font is built for one text size, so a change of size rebuilds it.
    let sizeCategory: ContentSizeCategory

    final class Coordinator {
        var appliedSizeCategory: ContentSizeCategory?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard textView.text != text || context.coordinator.appliedSizeCategory != sizeCategory else { return }
        context.coordinator.appliedSizeCategory = sizeCategory
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
            },
            // A tap outside the form sheet or a swipe down would otherwise drop the edits without asking.
            onUnsavedEditsChanged: { weakController?.isModalInPresentation = $0 }
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
