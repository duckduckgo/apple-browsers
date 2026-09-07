//
//  UTIFooterCardViewTests.swift
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

import DesignResourcesKitIcons
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class UTIFooterCardViewTests: XCTestCase {

    private let phoneWidth: CGFloat = 390
    /// Longer than the room a titled card leaves beside its CTA and close button at phone width.
    private let wrappingTitle = "Advanced AI models limit reached for this billing period"

    /// The card grows to fit the message instead of cutting it off.
    func test_cardHeight_growsWithAWrappedTitle() {
        let sut = UTIFooterCardView()

        sut.configure(with: makeMessage(title: "90% of weekly limit"), animateIcon: false)
        let compact = height(of: sut)

        sut.configure(with: makeMessage(title: wrappingTitle), animateIcon: false)
        let wrapped = height(of: sut)

        XCTAssertGreaterThan(wrapped, compact)
    }

    func test_cardHeight_isUnchangedByALongSubtitle() {
        let sut = UTIFooterCardView()

        sut.configure(with: makeMessage(subtitle: "Resets in 2 days"), animateIcon: false)
        let compact = height(of: sut)

        sut.configure(with: makeMessage(subtitle: "Resets in 2 days, 4 hours and 13 minutes from now"), animateIcon: false)
        let long = height(of: sut)

        XCTAssertEqual(compact, long, accuracy: 0.5)
    }

    func test_cardHeight_leavesRoomForTheControls() {
        let sut = UTIFooterCardView()
        sut.configure(with: makeMessage(), animateIcon: false)

        XCTAssertGreaterThan(height(of: sut), UTIFooterCardView.overlap + 34)
    }

    /// The whole message has to be readable, reset line beside it or not.
    func test_title_wrapsWithOrWithoutASubtitle() {
        let sut = UTIFooterCardView()

        sut.configure(with: makeMessage(), animateIcon: false)
        XCTAssertEqual(titleLabel(in: sut)?.numberOfLines, 0)

        sut.configure(with: makeNotice(), animateIcon: false)
        XCTAssertEqual(titleLabel(in: sut)?.numberOfLines, 0)
    }

    /// The reset line is short copy that belongs on one line, and wrapping it would grow the card
    /// for nothing.
    func test_subtitle_staysOnOneLine() {
        let sut = UTIFooterCardView()

        sut.configure(with: makeMessage(), animateIcon: false)

        XCTAssertEqual(subtitleLabel(in: sut)?.numberOfLines, 1)
    }

    /// The point of the wrap: at the height the card asks for, the whole title is on screen.
    func test_wrappedTitle_fitsTheHeightTheCardAsksFor() {
        let sut = UTIFooterCardView()
        sut.configure(with: makeMessage(title: wrappingTitle), animateIcon: false)
        sut.frame = CGRect(x: 0, y: 0, width: phoneWidth, height: height(of: sut))
        sut.setNeedsLayout()
        sut.layoutIfNeeded()

        guard let label = titleLabel(in: sut) else {
            return XCTFail("Expected the title to be part of the card")
        }
        let needed = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(needed, label.font.lineHeight * 1.5,
                             "The title has to wrap for this assertion to mean anything")
        XCTAssertEqual(label.bounds.height, needed, accuracy: 0.5)
    }

    /// A standalone paragraph reads as body copy, not as a heading.
    func test_title_usesBodyWeightWhenThereIsNoSubtitle() {
        let sut = UTIFooterCardView()

        sut.configure(with: makeMessage(), animateIcon: false)
        XCTAssertEqual(titleLabel(in: sut)?.font, UIFont.daxFootnoteSemibold())

        sut.configure(with: makeNotice(), animateIcon: false)
        XCTAssertEqual(titleLabel(in: sut)?.font, UIFont.daxFootnoteRegular())
    }

    /// The notice copy has to actually need the second line at phone width, or allowing it is moot.
    func test_title_wrapsTheNoticeCopyAtPhoneWidth() {
        let sut = UTIFooterCardView()
        sut.frame = CGRect(x: 0, y: 0, width: phoneWidth, height: 200)
        sut.configure(with: makeNotice(), animateIcon: false)
        sut.setNeedsLayout()
        sut.layoutIfNeeded()

        guard let label = titleLabel(in: sut) else {
            return XCTFail("Expected the title to be part of the card")
        }
        let needed = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(needed, label.font.lineHeight * 1.5)
    }

    /// The reset line beside a CTA has to stay on one line; a card with the pill gone can spend two.
    func test_subtitle_allowsTwoLinesOnlyWithoutACTA() {
        let sut = UTIFooterCardView()

        sut.configure(with: makeMessage(), animateIcon: false)
        XCTAssertEqual(subtitleLabel(in: sut)?.numberOfLines, 1)

        sut.configure(with: makeSwitchNotice(), animateIcon: false)
        XCTAssertEqual(subtitleLabel(in: sut)?.numberOfLines, 2)
    }

    /// The switch notice's copy has to actually need the second line at phone width, or allowing it
    /// is moot.
    func test_subtitle_wrapsTheSwitchNoticeCopyAtPhoneWidth() {
        let sut = UTIFooterCardView()
        sut.frame = CGRect(x: 0, y: 0, width: phoneWidth, height: 200)
        sut.configure(with: makeSwitchNotice(), animateIcon: false)
        sut.setNeedsLayout()
        sut.layoutIfNeeded()

        guard let label = subtitleLabel(in: sut) else {
            return XCTFail("Expected the subtitle to be part of the card")
        }
        let needed = label.sizeThatFits(CGSize(width: label.bounds.width, height: .greatestFiniteMagnitude)).height
        XCTAssertGreaterThan(needed, label.font.lineHeight * 1.5)
    }

    /// The card is measured bottom-up by the host, so the wrapped line has to reach its height.
    func test_cardHeight_growsForTheWrappedSwitchNoticeCopy() {
        let sut = UTIFooterCardView()

        sut.configure(with: makeSwitchNotice(subtitle: "Mistral can't create images."), animateIcon: false)
        let compact = height(of: sut)

        sut.configure(with: makeSwitchNotice(), animateIcon: false)
        let wrapped = height(of: sut)

        XCTAssertGreaterThan(wrapped, compact)
    }

    /// A message with no icon must not reserve the ring's room: the copy takes the leading edge.
    func test_cardWidth_collapsesTheIconWhenThereIsNone() {
        let sut = UTIFooterCardView()

        let withIcon = titleLeadingEdge(in: sut, message: makeMessage())
        let withoutIcon = titleLeadingEdge(in: sut, message: makeIconlessMessage())

        XCTAssertLessThan(withoutIcon, withIcon)
    }

    /// The notice carries a glyph of its own, so its copy starts where a warning's copy starts.
    func test_cardWidth_reservesTheIconSlotForTheNotice() {
        let sut = UTIFooterCardView()

        let withRing = titleLeadingEdge(in: sut, message: makeMessage())
        let withInfo = titleLeadingEdge(in: sut, message: makeNotice())

        XCTAssertEqual(withInfo, withRing, accuracy: 0.5)
    }

    func test_icon_showsTheInfoGlyphOnlyForTheNotice() {
        let sut = UTIFooterCardView()

        sut.configure(with: makeMessage(), animateIcon: false)
        XCTAssertEqual(infoIcon(in: sut)?.isHidden, true)

        sut.configure(with: makeNotice(), animateIcon: false)
        XCTAssertEqual(infoIcon(in: sut)?.isHidden, false)
        XCTAssertEqual(infoIcon(in: sut)?.image, DesignSystemImages.Glyphs.Size16.info)
    }

    /// A message with no CTA must leave no gap where the pill would have been.
    func test_cardWidth_collapsesTheActionButtonWithoutAnAction() {
        let sut = UTIFooterCardView()
        sut.frame = CGRect(x: 0, y: 0, width: phoneWidth, height: 200)

        sut.configure(with: makeMessage(primaryAction: nil), animateIcon: false)
        sut.setNeedsLayout()
        sut.layoutIfNeeded()

        let actionButtons = sut.subviews.flatMap(\.subviews).compactMap { $0 as? UTIFooterActionButton }
        XCTAssertEqual(actionButtons.count, 1)
        XCTAssertEqual(actionButtons.first?.bounds.width, 0)
    }

    /// A card with nothing to dismiss must not reserve the close button's room: the CTA takes over
    /// the trailing edge the close button would have owned.
    func test_cardWidth_alignsTheActionButtonToTheTrailingEdgeWhenNotDismissible() {
        let sut = UTIFooterCardView()

        let dismissEdge = trailingEdge(in: sut) { dismissButton(in: sut) }
        let actionEdge = trailingEdge(in: sut, isDismissible: false) { actionButton(in: sut) }

        XCTAssertEqual(actionEdge, dismissEdge, accuracy: 0.5)
    }

    func test_cardWidth_keepsTheActionButtonClearOfTheDismissButton() {
        let sut = UTIFooterCardView()
        sut.frame = CGRect(x: 0, y: 0, width: phoneWidth, height: 200)

        sut.configure(with: makeMessage(isDismissible: true), animateIcon: false)
        sut.setNeedsLayout()
        sut.layoutIfNeeded()

        guard let action = actionButton(in: sut), let dismiss = dismissButton(in: sut) else {
            return XCTFail("Expected both controls to be part of the card")
        }
        XCTAssertLessThanOrEqual(sut.convert(action.bounds, from: action).maxX,
                                 sut.convert(dismiss.bounds, from: dismiss).minX)
    }

    // MARK: - Helpers

    /// Lays the card out at phone width for `isDismissible` and reports the trailing edge of the
    /// resolved subview, in the card's own coordinates.
    private func trailingEdge(in card: UTIFooterCardView,
                              isDismissible: Bool = true,
                              of subview: () -> UIView?) -> CGFloat {
        card.frame = CGRect(x: 0, y: 0, width: phoneWidth, height: 200)
        card.configure(with: makeMessage(isDismissible: isDismissible), animateIcon: false)
        card.setNeedsLayout()
        card.layoutIfNeeded()

        guard let subview = subview() else {
            XCTFail("Expected the subview to be part of the card")
            return 0
        }
        return card.convert(subview.bounds, from: subview).maxX
    }

    private func infoIcon(in card: UTIFooterCardView) -> UIImageView? {
        card.subviews.flatMap(\.subviews)
            .compactMap { $0 as? UIImageView }
            .first { $0.accessibilityIdentifier == "AIChat.Footer.Icon.Info" }
    }

    private func actionButton(in card: UTIFooterCardView) -> UTIFooterActionButton? {
        card.subviews.flatMap(\.subviews).compactMap { $0 as? UTIFooterActionButton }.first
    }

    /// The card's only direct `UIButton` child: the action button's own buttons sit one level deeper.
    private func dismissButton(in card: UTIFooterCardView) -> UIButton? {
        card.subviews.flatMap(\.subviews).compactMap { $0 as? UIButton }.first
    }

    private func height(of view: UTIFooterCardView) -> CGFloat {
        view.frame = CGRect(x: 0, y: 0, width: phoneWidth, height: 0)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        return view.systemLayoutSizeFitting(CGSize(width: phoneWidth, height: UIView.layoutFittingCompressedSize.height),
                                            withHorizontalFittingPriority: .required,
                                            verticalFittingPriority: .fittingSizeLevel).height
    }

    /// The title's leading edge in the card's own coordinates, laid out at phone width.
    private func titleLeadingEdge(in card: UTIFooterCardView, message: UTIFooterMessage) -> CGFloat {
        card.frame = CGRect(x: 0, y: 0, width: phoneWidth, height: 200)
        card.configure(with: message, animateIcon: false)
        card.setNeedsLayout()
        card.layoutIfNeeded()

        guard let label = titleLabel(in: card) else {
            XCTFail("Expected the title to be part of the card")
            return 0
        }
        return card.convert(label.bounds, from: label).minX
    }

    /// The first arranged subview of the card's text stack.
    private func titleLabel(in card: UTIFooterCardView) -> UILabel? {
        textStack(in: card)?.arrangedSubviews.first as? UILabel
    }

    /// The second arranged subview of the card's text stack.
    private func subtitleLabel(in card: UTIFooterCardView) -> UILabel? {
        textStack(in: card)?.arrangedSubviews.last as? UILabel
    }

    private func textStack(in card: UTIFooterCardView) -> UIStackView? {
        card.subviews.flatMap(\.subviews).compactMap { $0 as? UIStackView }.first
    }

    private func makeMessage(title: String = "90% of weekly limit",
                             subtitle: String? = "Resets in 2 days",
                             isDismissible: Bool = true) -> UTIFooterMessage {
        makeMessage(title: title,
                    subtitle: subtitle,
                    primaryAction: .init(title: "Switch Model"),
                    isDismissible: isDismissible)
    }

    private func makeMessage(title: String = "90% of weekly limit",
                             subtitle: String? = "Resets in 2 days",
                             primaryAction: UTIFooterMessage.PrimaryAction?,
                             isDismissible: Bool = true) -> UTIFooterMessage {
        UTIFooterMessage(icon: .usageRing(progress: 0.9, severity: .critical),
                         title: title,
                         subtitle: subtitle,
                         primaryAction: primaryAction,
                         isDismissible: isDismissible)
    }

    /// The Create Image switch card: a headline over body copy, with no CTA to compete for width.
    private func makeSwitchNotice(
        subtitle: String = "Mistral can't create images. Its extra privacy protections won't apply until you switch back."
    ) -> UTIFooterMessage {
        UTIFooterMessage(icon: .modelSwitch,
                         title: "Now using 5.6 Luna",
                         subtitle: subtitle,
                         primaryAction: nil,
                         isDismissible: true)
    }

    private func makeNotice(title: String = "Opus 4.8 uses limits up to 2-5x faster than basic models.") -> UTIFooterMessage {
        UTIFooterMessage(icon: .info,
                         title: title,
                         subtitle: nil,
                         primaryAction: nil,
                         isDismissible: true)
    }

    private func makeIconlessMessage() -> UTIFooterMessage {
        UTIFooterMessage(icon: .none,
                         title: "90% of weekly limit",
                         subtitle: "Resets in 2 days",
                         primaryAction: .init(title: "Switch Model"),
                         isDismissible: true)
    }
}
