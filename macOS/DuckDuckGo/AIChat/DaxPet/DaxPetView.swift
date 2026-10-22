//
//  DaxPetView.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI

/// Speech bubble on top, Dax in the middle, controls at his feet. Every area has a fixed size, so the
/// window never resizes and Dax never moves; only the controls capsule grows into the prompt field.
struct DaxPetView: View {

    enum Metrics {
        static let padding: CGFloat = 8
        static let spacing: CGFloat = 6
        /// Room for three findings with two-line titles, the tallest thing Dax shows.
        static let bubbleAreaHeight: CGFloat = 220
        static let controlsHeight: CGFloat = 36
        static let toolbarSize = CGSize(width: 106, height: 32)
        static let composingWidth: CGFloat = 320
        static let promptLeadingInset: CGFloat = 14
        static let attachmentChipSize: CGFloat = 22
        static let maxVisibleAttachments = 3

        /// Room the attachment chips take before the prompt text.
        static func attachmentsWidth(count: Int) -> CGFloat {
            guard count > 0 else { return 0 }
            return CGFloat(min(count, maxVisibleAttachments) + 1) * (attachmentChipSize + 2)
        }

        /// Room the chips of the tabs to compare take before the prompt text.
        static func tabChipsWidth(count: Int) -> CGFloat {
            CGFloat(count) * (attachmentChipSize + 2)
        }

        static let windowSize = CGSize(width: composingWidth + padding * 2,
                                       height: padding * 2 + bubbleAreaHeight + spacing * 2
                                       + DaxCharacterView.preferredSize.height + controlsHeight)

        /// The parts of the window that take clicks, in window coordinates (origin bottom-left).
        static func characterFrame() -> CGRect {
            let size = DaxCharacterView.preferredSize
            return CGRect(x: (windowSize.width - size.width) / 2,
                          y: padding + controlsHeight + spacing,
                          width: size.width, height: size.height)
        }

        static func controlsFrame(isComposing: Bool) -> CGRect {
            let size = isComposing ? CGSize(width: composingWidth, height: controlsHeight) : toolbarSize
            return CGRect(x: (windowSize.width - size.width) / 2,
                          y: padding + (controlsHeight - size.height) / 2,
                          width: size.width, height: size.height)
        }

        /// Bubbles sit on the bottom of their area, so only the part they fill takes clicks.
        static func bubbleFrame(contentHeight: CGFloat? = nil) -> CGRect {
            let height = min(contentHeight ?? bubbleAreaHeight, bubbleAreaHeight)
            return CGRect(x: padding, y: characterFrame().maxY + spacing, width: composingWidth, height: height)
        }
    }

    @ObservedObject var model: DaxPetViewModel

    var body: some View {
        VStack(spacing: Metrics.spacing) {
            ZStack(alignment: .bottom) {
                Group {
                if let offer = model.dropOffer {
                    DropOfferBubble(speech: model.speech, offer: offer, suggestions: model.suggestions,
                                    onGoToTab: model.goToDroppedTab,
                                    onRecap: { Task { await model.recapDrop() } },
                                    onSuggestion: model.useSuggestion)
                        .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
                } else if !model.suggestions.isEmpty {
                    SuggestionChips(suggestions: model.suggestions, onSelect: model.useSuggestion)
                        .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
                } else if let findings = model.findings, case .items(let items) = findings.content {
                    FindingsCard(headline: findings.headline, total: findings.total, items: items, now: model.now(),
                                 onOpen: model.openFinding, onAskDuckAI: model.askDuckAIInstead)
                        .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
                } else if let findings = model.findings {
                    FindingsBubble(findings: findings,
                                   onAllowHistory: model.allowHistorySearch,
                                   onAskDuckAI: model.askDuckAIInstead)
                        .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
                } else if let glance = model.glance {
                    GlanceBubble(glance: glance,
                                 onAsk: { followUp in Task { await model.askAboutGlance(followUp) } },
                                 onShowWhere: { Task { await model.showWhereOnPage() } })
                        .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
                } else if let speech = model.speech {
                    SpeechBubble(text: speech)
                        .id(speech)
                        .transition(.scale(scale: 0.7, anchor: .bottom).combined(with: .opacity))
                }
                }
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: BubbleHeightKey.self, value: proxy.size.height)
                })
            }
            .frame(width: Metrics.composingWidth, height: Metrics.bubbleAreaHeight, alignment: .bottom)
            .onPreferenceChange(BubbleHeightKey.self) { model.bubbleContentHeight = $0 }
            // Over the tip of a hat.
            .zIndex(1)

            DaxCharacterRepresentable(character: model.character)
                .frame(width: DaxCharacterView.preferredSize.width, height: DaxCharacterView.preferredSize.height)
                .overlay(alignment: .top) {
                    if let burst = model.heartBurst {
                        HeartBurst().id(burst)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if model.isAsleep {
                        SleepingZs()
                            .offset(x: 26, y: -18)
                            .transition(.opacity)
                    }
                }

            Controls(model: model)
                .frame(width: Metrics.composingWidth, height: Metrics.controlsHeight)
        }
        .padding(Metrics.padding)
        .frame(width: Metrics.windowSize.width, height: Metrics.windowSize.height)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.speech)
        .animation(.easeInOut(duration: 0.6), value: model.isAsleep)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.suggestions)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.glance)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.findings)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.dropOffer)
    }
}

private struct BubbleHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Requests to send about what was dropped, suggested on the device; one click sends one.
private struct SuggestionChips: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ChipList(suggestions: suggestions, maximumRows: 2, onSelect: onSelect)
            .frame(width: DaxPetView.Metrics.composingWidth, height: DaxPetView.Metrics.bubbleAreaHeight, alignment: .bottom)
    }
}

/// Requests as chips at their full width, in as many rows as allowed; one click sends one.
private struct ChipList: View {
    let suggestions: [String]
    let maximumRows: Int
    let onSelect: (String) -> Void

    var body: some View {
        Group {
            if #available(macOS 13, *) {
                ChipRows(spacing: 6, maximumRows: maximumRows) { chips(suggestions) }
            } else {
                VStack(spacing: 6) { chips(Array(suggestions.prefix(maximumRows))) }
            }
        }
        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
    }

    private func chips(_ suggestions: [String]) -> some View {
        ForEach(suggestions, id: \.self) { suggestion in
            Button {
                onSelect(suggestion)
            } label: {
                ChipLabel(text: suggestion)
            }
            .buttonStyle(.plain)
            .help(suggestion)
        }
    }
}

/// One chip's capsule; the accented one stands out as the way on to Duck.ai.
private struct ChipLabel: View {
    let text: String
    var isAccented = false

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: isAccented ? .semibold : .medium))
            .foregroundColor(Color(designSystemColor: isAccented ? .accentPrimary : .textPrimary))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(designSystemColor: .surfacePrimary)))
            .overlay(Capsule().stroke(Color(designSystemColor: .surfaceDecorationPrimary), lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// For a dropped link the browser knows: Dax's line, then going to its tab and a recap, then any suggestions.
private struct DropOfferBubble: View {
    let speech: String?
    let offer: DaxPetDropOffer
    let suggestions: [String]
    let onGoToTab: () -> Void
    let onRecap: () -> Void
    let onSuggestion: (String) -> Void

    var body: some View {
        VStack(spacing: 6) {
            if let speech {
                SpeechBubble(text: speech)
            }
            Group {
                if #available(macOS 13, *) {
                    ChipRows(spacing: 6, maximumRows: 2) { chips }
                } else {
                    HStack(spacing: 6) { chips }
                }
            }
            .frame(width: DaxPetView.Metrics.composingWidth)
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
        }
    }

    @ViewBuilder
    private var chips: some View {
        if case .openTab = offer {
            Button(action: onGoToTab) { ChipLabel(text: UserText.daxPetDropGoToTab, isAccented: true) }
                .buttonStyle(.plain)
        }
        Button(action: onRecap) { ChipLabel(text: UserText.daxPetDropRecap, isAccented: true) }
            .buttonStyle(.plain)
        ForEach(suggestions, id: \.self) { suggestion in
            Button { onSuggestion(suggestion) } label: { ChipLabel(text: suggestion) }
                .buttonStyle(.plain)
                .help(suggestion)
        }
    }
}

/// What Dax found on the Mac, a row each with its icon, full title and where it is, and Duck.ai as the way on.
private struct FindingsCard: View {
    let headline: String
    let total: Int?
    let items: [DaxPetFindings.Item]
    let now: Date
    let onOpen: (DaxPetFindings.Item) -> Void
    let onAskDuckAI: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(headline)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .lineLimit(1)
                if let total {
                    Text(verbatim: "\(total)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color(designSystemColor: .controlsFillPrimary)))
                }
                Spacer(minLength: 0)
                Button(action: onAskDuckAI) {
                    HStack(spacing: 4) {
                        Image(nsImage: DesignSystemImages.Glyphs.Size12.aiChat)
                            .renderingMode(.template)
                        Text(UserText.daxPetFindingsAskDuckAI)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(Color(designSystemColor: .accentPrimary))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color(designSystemColor: .controlsFillPrimary)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 6)
            .padding(.bottom, 2)

            if items.count > Self.rowsWithoutScrolling {
                ScrollView(.vertical) {
                    VStack(spacing: 2) { rows }
                        // Room for the last row to clear the fade.
                        .padding(.bottom, 14)
                }
                .frame(height: Self.scrollingHeight)
                // Fades the rows out at the bottom, so it's clear there are more to scroll to.
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [Color(designSystemColor: .surfacePrimary).opacity(0), Color(designSystemColor: .surfacePrimary)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 22)
                        .allowsHitTesting(false)
                }
            } else {
                rows
            }
        }
        .padding(8)
        .frame(width: DaxPetView.Metrics.composingWidth)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(designSystemColor: .surfacePrimary))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(designSystemColor: .surfaceDecorationPrimary), lineWidth: 1))
        .onAppear { hasAppeared = true }
    }

    /// Three rows of two-line titles fill the bubble; more scroll, with the fourth peeking out.
    static let rowsWithoutScrolling = 3
    static let scrollingHeight: CGFloat = 160

    private var rows: some View {
        let amongPagesSeenBefore = items.contains { if case .visit = $0 { true } else { false } }
        return ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            FindingRow(item: item, detail: item.detail(relativeTo: now, amongPagesSeenBefore: amongPagesSeenBefore)) { onOpen(item) }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared || reduceMotion ? 0 : 6)
                .animation(.spring(response: 0.35, dampingFraction: 0.8).delay(Double(min(index, 5)) * 0.06), value: hasAppeared)
        }
    }
}

/// One tab or page: its icon, its title in full on up to two lines, and where it is.
private struct FindingRow: View {
    let item: DaxPetFindings.Item
    let detail: String
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(nsImage: item.favicon ?? DesignSystemImages.Glyphs.Size16.globe)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color(designSystemColor: .controlsFillPrimary)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(nsImage: DesignSystemImages.Glyphs.Size12.arrowRight)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .iconsSecondary))
                    .opacity(isHovered ? 1 : 0)
                    .offset(x: isHovered ? 0 : -4)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(designSystemColor: .controlsFillPrimary)).opacity(isHovered ? 1 : 0))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help(item.url.absoluteString)
        .accessibilityLabel(item.title)
        .accessibilityHint(detail)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}

/// Dax's question before he first searches the history, with Duck.ai as the other way on.
private struct FindingsBubble: View {
    let findings: DaxPetFindings
    let onAllowHistory: () -> Void
    let onAskDuckAI: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text(findings.headline)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(designSystemColor: .surfacePrimary))
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                )
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(designSystemColor: .surfaceDecorationPrimary), lineWidth: 1))

            Group {
                if #available(macOS 13, *) {
                    ChipRows(spacing: 6, maximumRows: 2) { chips }
                } else {
                    HStack(spacing: 6) { chips }
                }
            }
            .frame(width: DaxPetView.Metrics.composingWidth)
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
        }
    }

    @ViewBuilder
    private var chips: some View {
        // Duck.ai first, so it's never the chip left out of a full row.
        Button(action: onAskDuckAI) {
            ChipLabel(text: UserText.daxPetFindingsAskDuckAI, isAccented: true)
        }
        .buttonStyle(.plain)
        if findings.content == .askingToSearchHistory {
            Button(action: onAllowHistory) {
                ChipLabel(text: UserText.daxPetHistoryAllow)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Lays chips out at their full width, wrapping onto centred rows from the bottom up; chips that don't fit
/// in `maximumRows` are left out rather than squeezed.
@available(macOS 13, *)
private struct ChipRows: Layout {
    let spacing: CGFloat
    let maximumRows: Int

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: height(of: rows))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, width: bounds.width)
        var y = bounds.maxY - height(of: rows)
        for row in rows {
            var x = bounds.midX - row.width / 2
            for index in row.indices {
                let size = chipSize(subviews[index], width: bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
        // Left out: a zero size still draws the chip's padding, so out of sight it goes.
        let placed = Set(rows.flatMap(\.indices))
        for index in subviews.indices where !placed.contains(index) {
            subviews[index].place(at: CGPoint(x: bounds.minX - 10_000, y: bounds.minY), proposal: .unspecified)
        }
    }

    /// A chip as wide as its text, but never wider than the room there is.
    private func chipSize(_ subview: LayoutSubview, width: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        return ideal.width <= width ? ideal : subview.sizeThatFits(ProposedViewSize(width: width, height: ideal.height))
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        for index in subviews.indices {
            let size = chipSize(subviews[index], width: width)
            if var row = rows.last, row.width + spacing + size.width <= width {
                row.indices.append(index)
                row.width += spacing + size.width
                row.height = max(row.height, size.height)
                rows[rows.count - 1] = row
            } else if rows.count < maximumRows {
                rows.append(Row(indices: [index], width: size.width, height: size.height))
            }
        }
        return rows
    }

    private func height(of rows: [Row]) -> CGFloat {
        rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    }
}

/// What was dropped on Dax, one icon each (named in its tooltip), and a button to drop them all.
private struct AttachmentChips: View {
    let attachments: [DaxPetAttachment]
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(attachments.prefix(DaxPetView.Metrics.maxVisibleAttachments)) { attachment in
                chip(for: attachment)
                    .frame(width: DaxPetView.Metrics.attachmentChipSize, height: DaxPetView.Metrics.attachmentChipSize)
                    .help(attachment.name)
                    .accessibilityLabel(attachment.name)
            }
            Button(action: onRemove) {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.close)
                    .renderingMode(.template)
                    .foregroundColor(Color(designSystemColor: .iconsSecondary))
                    .frame(width: DaxPetView.Metrics.attachmentChipSize, height: DaxPetView.Metrics.attachmentChipSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(UserText.daxPetRemoveAttachments)
            .accessibilityLabel(UserText.daxPetRemoveAttachments)
        }
    }

    /// Images show what they are, which matters most for a screenshot about to be sent.
    @ViewBuilder
    private func chip(for attachment: DaxPetAttachment) -> some View {
        if case .image(let image) = attachment {
            Image(nsImage: image.image)
                .resizable()
                .scaledToFill()
                .frame(width: DaxPetView.Metrics.attachmentChipSize, height: DaxPetView.Metrics.attachmentChipSize)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(designSystemColor: .surfaceDecorationPrimary), lineWidth: 1))
        } else {
            Image(nsImage: icon(for: attachment))
                .renderingMode(.template)
                .foregroundColor(Color(designSystemColor: .iconsPrimary))
                .frame(width: DaxPetView.Metrics.attachmentChipSize, height: DaxPetView.Metrics.attachmentChipSize)
                .background(Circle().fill(Color(designSystemColor: .controlsFillPrimary)))
        }
    }

    private func icon(for attachment: DaxPetAttachment) -> NSImage {
        switch attachment {
        case .text: return DesignSystemImages.Glyphs.Size16.note
        case .link: return DesignSystemImages.Glyphs.Size16.link
        case .image: return DesignSystemImages.Glyphs.Size16.image
        case .file: return DesignSystemImages.Glyphs.Size16.attach
        }
    }
}

/// The tabs going along for a comparison, by their icons; clicking one leaves it out.
private struct TabChips: View {
    let tabs: [DaxPetTab]
    let onLeaveOut: (DaxPetTab) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Button { onLeaveOut(tab) } label: {
                    Image(nsImage: tab.favicon ?? DesignSystemImages.Glyphs.Size16.globe)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .frame(width: DaxPetView.Metrics.attachmentChipSize, height: DaxPetView.Metrics.attachmentChipSize)
                        .background(Circle().fill(Color(designSystemColor: .controlsFillPrimary)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(UserText.daxPetCompareLeaveOut(tab.title))
                .accessibilityLabel(UserText.daxPetCompareLeaveOut(tab.title))
            }
        }
    }
}

/// A handful of hearts floating up out of a happily petted Dax.
private struct HeartBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFloating = false

    private let hearts: [(x: CGFloat, rise: CGFloat, delay: Double, scale: CGFloat)] = [
        (-22, 34, 0, 0.9), (0, 46, 0.12, 1.1), (20, 30, 0.24, 0.8), (-8, 40, 0.36, 0.7)
    ]

    var body: some View {
        ZStack {
            ForEach(hearts.indices, id: \.self) { index in
                let heart = hearts[index]
                Image(nsImage: DesignSystemImages.Color.Size16.heart)
                    .scaleEffect(isFloating ? heart.scale : 0.3)
                    .offset(x: heart.x, y: isFloating && !reduceMotion ? -heart.rise : 0)
                    .opacity(isFloating ? 0 : 1)
                    .animation(.easeOut(duration: 1.3).delay(heart.delay), value: isFloating)
            }
        }
        .onAppear { isFloating = true }
        .accessibilityHidden(true)
    }
}

/// Three z's drifting up and away from a sleeping Dax.
private struct SleepingZs: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let period: TimeInterval = 3

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .bottomLeading) {
                ForEach(0..<3) { index in
                    let progress = reduceMotion ? 0.3 + Double(index) * 0.25
                        : (time / period + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                    Text(verbatim: "z")
                        .font(.system(size: 10 + progress * 8, weight: .bold, design: .rounded))
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .offset(x: progress * 14 + sin(progress * .pi * 2) * 3, y: -progress * 30)
                        .opacity(reduceMotion ? 1 : sin(progress * .pi))
                }
            }
            .frame(width: 40, height: 44, alignment: .bottomLeading)
        }
        .accessibilityHidden(true)
    }
}

/// One capsule that morphs between the toolbar and the prompt field, cross-fading their contents.
private struct Controls: View {
    @ObservedObject var model: DaxPetViewModel

    var body: some View {
        let size = model.isComposing
            ? CGSize(width: DaxPetView.Metrics.composingWidth, height: DaxPetView.Metrics.controlsHeight)
            : DaxPetView.Metrics.toolbarSize

        ZStack {
            Capsule().fill(.regularMaterial)

            Toolbar(model: model)
                .opacity(model.isComposing ? 0 : 1)
                .scaleEffect(model.isComposing ? 0.9 : 1)
                .allowsHitTesting(!model.isComposing)

            PromptField(model: model)
                .frame(width: DaxPetView.Metrics.composingWidth)
                .opacity(model.isComposing ? 1 : 0)
                .allowsHitTesting(model.isComposing)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color(designSystemColor: .surfaceDecorationPrimary), lineWidth: 1))
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: model.isComposing)
    }
}

private struct DaxCharacterRepresentable: NSViewRepresentable {
    let character: DaxCharacterView

    func makeNSView(context: Context) -> DaxCharacterView { character }
    func updateNSView(_ nsView: DaxCharacterView, context: Context) {}
}

/// The gist of the open page, and follow-ups to send Duck.ai about it; `onAsk(nil)` asks for a full summary
/// when the model had no follow-ups.
private struct GlanceBubble: View {
    let glance: DaxPetPageGlance
    let onAsk: (String?) -> Void
    let onShowWhere: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 4) {
                Text(glance.summary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if glance.followUps.isEmpty {
                    Button { onAsk(nil) } label: {
                        Text(UserText.daxPetGlanceAsk)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(designSystemColor: .accentPrimary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 280)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(designSystemColor: .surfacePrimary))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(designSystemColor: .surfaceDecorationPrimary), lineWidth: 1)
            )

            if !glance.followUps.isEmpty || glance.quote != nil {
                Group {
                    if #available(macOS 13, *) {
                        ChipRows(spacing: 6, maximumRows: 2) { chips }
                    } else {
                        VStack(spacing: 6) { chips }
                    }
                }
                .frame(width: DaxPetView.Metrics.composingWidth)
                .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
            }
        }
    }
}

private extension GlanceBubble {

    /// "Show me where" first, so it's never the chip left out of a full row; on macOS 12 one follow-up fits beside it.
    @ViewBuilder
    var chips: some View {
        if glance.quote != nil {
            Button(action: onShowWhere) {
                ChipLabel(text: UserText.daxPetShowWhere, isAccented: true)
            }
            .buttonStyle(.plain)
        }
        ForEach(followUpsThatFit, id: \.self) { followUp in
            Button { onAsk(followUp) } label: {
                ChipLabel(text: followUp)
            }
            .buttonStyle(.plain)
            .help(followUp)
        }
    }

    private var followUpsThatFit: [String] {
        if #available(macOS 13, *) { return glance.followUps }
        return Array(glance.followUps.prefix(glance.quote == nil ? 2 : 1))
    }
}

private struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Color(designSystemColor: .textPrimary))
            .multilineTextAlignment(.center)
            .frame(maxWidth: 220)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(designSystemColor: .surfacePrimary))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(designSystemColor: .surfaceDecorationPrimary), lineWidth: 1)
            )
    }
}

private struct Toolbar: View {
    @ObservedObject var model: DaxPetViewModel

    var body: some View {
        HStack(spacing: 2) {
            ToolbarButton(image: DesignSystemImages.Glyphs.Size16.compose, help: UserText.daxPetAsk) {
                model.startComposing()
            }
            Divider().frame(height: 16)
            ToolbarButton(image: DesignSystemImages.Glyphs.Size16.aiChat, help: UserText.daxPetOpenDuckAI) {
                model.openDuckAI()
            }
            Divider().frame(height: 16)
            ToolbarButton(image: DesignSystemImages.Glyphs.Size16.close, help: UserText.daxPetHide) {
                model.hide()
            }
        }
        .frame(width: DaxPetView.Metrics.toolbarSize.width, height: DaxPetView.Metrics.toolbarSize.height)
    }
}

private struct ToolbarButton: View {
    let image: NSImage
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(nsImage: image)
                .renderingMode(.template)
                .foregroundColor(Color(designSystemColor: .iconsPrimary))
                .frame(width: 28, height: 26)
                .background(Circle().fill(Color(designSystemColor: .controlsFillPrimary)).opacity(isHovered ? 1 : 0))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovered = $0 }
    }
}

private struct PromptField: View {
    @ObservedObject var model: DaxPetViewModel
    @FocusState private var isFocused: Bool

    private var canSubmit: Bool {
        model.canSubmit
    }

    var body: some View {
        HStack(spacing: 6) {
            if !model.attachments.isEmpty {
                AttachmentChips(attachments: model.attachments, onRemove: model.removeAttachments)
                    .padding(.leading, 8)
            }
            if !model.comparedTabs.isEmpty {
                TabChips(tabs: model.comparedTabs, onLeaveOut: model.leaveOut)
                    .padding(.leading, 8)
            }
            TextField(model.promptPlaceholder, text: $model.prompt)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFocused)
                .onSubmit { model.submit() }
                .onExitCommand { model.endComposing() }
                .padding(.leading, model.attachments.isEmpty && model.comparedTabs.isEmpty ? DaxPetView.Metrics.promptLeadingInset : 0)

            Button(action: model.submit) {
                Image(nsImage: DesignSystemImages.Glyphs.Size16.arrowUp)
                    .renderingMode(.template)
                    .foregroundColor(.white)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color(designSystemColor: .accentPrimary)))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.4)
            .help(UserText.daxPetSend)
            .accessibilityLabel(UserText.daxPetSend)
            .padding(.trailing, 5)
        }
        .frame(height: DaxPetView.Metrics.controlsHeight)
        .disabled(!model.isComposing)
        .onChange(of: model.isComposing) { isComposing in
            // The window turns key just after composing starts.
            DispatchQueue.main.async { isFocused = isComposing }
        }
    }
}
