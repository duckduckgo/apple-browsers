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

import AIChat
import DesignResourcesKitIcons
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class UTIFooterCardViewTests: XCTestCase {

    private let phoneWidth: CGFloat = 390
    /// The input card's two widths on a phone: expanded to the omnibar margins, and flanked by the
    /// AI tab's fire and menu buttons — the footer card follows both.
    private let expandedCardWidth: CGFloat = 361
    private let flankedCardWidth: CGFloat = 249
    /// Longer than the room a titled card leaves beside its CTA and close button at phone width.
    private let wrappingTitle = "Advanced AI models limit reached for this billing period"

    func testWhenPromotionContainsSeparatorThenOnlyLocalizedPrefixIsEmphasized() throws {
        for prefix in ["Nowość", "Nytt", "新機能"] {
            let sut = UTIFooterCardView()
            let title = "  \(prefix)  · Add {attachment} · More"
            let message = UTIFooterMessageMapper().multiTabPromotionMessage(title: title)

            sut.configure(with: message, animateIcon: false)

            let label = try XCTUnwrap(titleLabel(in: sut))
            let renderedTitle = try XCTUnwrap(label.attributedText)
            let prefixRange = (renderedTitle.string as NSString).range(of: prefix)
            XCTAssertNotEqual(prefixRange.location, NSNotFound)
            for index in 0..<renderedTitle.length {
                guard renderedTitle.attribute(.attachment, at: index, effectiveRange: nil) == nil else { continue }
                let expectedFont: UIFont = NSLocationInRange(index, prefixRange) ? .daxFootnoteSemibold() : .daxFootnoteRegular()
                XCTAssertEqual(renderedTitle.attribute(.font, at: index, effectiveRange: nil) as? UIFont, expectedFont, prefix)
            }
            XCTAssertTrue(renderedTitle.string.contains("\u{fffc}"))
            XCTAssertFalse(renderedTitle.string.contains("{attachment}"))
            XCTAssertEqual(label.accessibilityLabel,
                           title.replacingOccurrences(of: "{attachment}", with: UserText.aiChatMultiTabPromotionAttachment))
        }
    }

    func testWhenPromotionHasNoPrefixOrSeparatorThenTitleIsNotEmphasized() throws {
        for title in ["Nowość Add {attachment}", "  · Add {attachment}"] {
            let sut = UTIFooterCardView()
            let message = UTIFooterMessageMapper().multiTabPromotionMessage(title: title)

            sut.configure(with: message, animateIcon: false)

            let label = try XCTUnwrap(titleLabel(in: sut))
            let renderedTitle = try XCTUnwrap(label.attributedText)
            renderedTitle.enumerateAttributes(in: NSRange(location: 0, length: renderedTitle.length)) { attributes, _, _ in
                guard attributes[.attachment] == nil else { return }
                XCTAssertEqual(attributes[.font] as? UIFont, .daxFootnoteRegular())
            }
            XCTAssertTrue(renderedTitle.string.contains("\u{fffc}"))
            XCTAssertEqual(label.accessibilityLabel,
                           title.replacingOccurrences(of: "{attachment}", with: UserText.aiChatMultiTabPromotionAttachment))
        }
    }

    func testSwitchingFromPromotionToPlainTitleRestoresOriginalPresentation() throws {
        for message in [makeMessage(), makeNotice()] {
            let sut = UTIFooterCardView()
            sut.configure(with: UTIFooterMessageMapper().multiTabPromotionMessage(), animateIcon: false)

            sut.configure(with: message, animateIcon: false)

            let reference = UTIFooterCardView()
            reference.configure(with: message, animateIcon: false)
            let label = try XCTUnwrap(titleLabel(in: sut))
            let referenceLabel = try XCTUnwrap(titleLabel(in: reference))
            XCTAssertEqual(label.text, message.title)
            XCTAssertEqual(label.font, referenceLabel.font)
            XCTAssertEqual(label.accessibilityLabel, referenceLabel.accessibilityLabel)
            if let title = label.attributedText {
                title.enumerateAttribute(.attachment, in: NSRange(location: 0, length: title.length)) { value, _, _ in
                    XCTAssertNil(value)
                }
            }
        }
    }

    func testStackedTermsAndPrivacyHaveTheSameTextGapAsBottomPadding() throws {
        let terms = UTIFooterCardView()
        let privacy = UTIFooterCardView()
        let mapper = UTIFooterMessageMapper()
        terms.configure(with: mapper.termsOfServiceMessage(), animateIcon: false)
        privacy.configure(with: mapper.attachmentPrivacyMessage(), animateIcon: false)
        privacy.isBelowAnotherCard = true
        let stack = UIStackView(arrangedSubviews: [terms, privacy])
        stack.axis = .vertical
        stack.spacing = -UTIFooterCardView.overlap
        let width: CGFloat = 1024
        stack.frame = CGRect(x: 0, y: 0, width: width, height: 200)
        stack.layoutIfNeeded()
        let size = stack.systemLayoutSizeFitting(CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
                                                withHorizontalFittingPriority: .required,
                                                verticalFittingPriority: .fittingSizeLevel)
        stack.frame = CGRect(origin: .zero, size: size)
        stack.setNeedsLayout()
        stack.layoutIfNeeded()

        let termsText = try XCTUnwrap(linkTextView(in: terms))
        let privacyText = try XCTUnwrap(linkTextView(in: privacy))
        let termsFrame = stack.convert(termsText.bounds, from: termsText)
        let privacyFrame = stack.convert(privacyText.bounds, from: privacyText)
        let bottomGap = stack.bounds.maxY - privacyFrame.maxY
        XCTAssertLessThan(termsFrame.height, 34)
        XCTAssertEqual(privacyFrame.minY - termsFrame.maxY, bottomGap, accuracy: 0.5)
        XCTAssertEqual(bottomGap, 12, accuracy: 0.5)
    }

    func testReusingDisclosureCardRestoresVisibleControlHeights() throws {
        let sut = UTIFooterCardView()
        sut.configure(with: UTIFooterMessageMapper().termsOfServiceMessage(), animateIcon: false)
        sut.configure(with: makeMessage(title: "Limit", subtitle: nil), animateIcon: false)
        sut.frame = CGRect(x: 0, y: 0, width: phoneWidth, height: height(of: sut))
        sut.setNeedsLayout()
        sut.layoutIfNeeded()

        let action = try XCTUnwrap(actionButton(in: sut))
        let dismiss = try XCTUnwrap(dismissButton(in: sut))
        XCTAssertFalse(action.isHidden)
        XCTAssertFalse(dismiss.isHidden)
        XCTAssertEqual(action.bounds.height, 34, accuracy: 0.5)
        XCTAssertEqual(dismiss.bounds.height, 32, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(sut.contentView.bounds.height, action.bounds.height)
        XCTAssertGreaterThanOrEqual(sut.contentView.bounds.height, dismiss.bounds.height)
    }

    func testPrivacyUsesNativeLinkAndHidesItOnReuse() throws {
        let sut = UTIFooterCardView()
        let message = UTIFooterMessageMapper().attachmentPrivacyMessage()
        sut.configure(with: message, animateIcon: false)
        let textView = try XCTUnwrap((textStack(in: sut)?.arrangedSubviews ?? []).compactMap { $0 as? UTIFooterLinkTextView }.first)
        let range = (message.title as NSString).range(of: "Learn more")
        XCTAssertEqual(textView.attributedText.attribute(.link, at: range.location, effectiveRange: nil) as? URL, message.link?.url)
        XCTAssertFalse(textView.isHidden)
        XCTAssertFalse(textView.canBecomeFirstResponder)

        sut.configure(with: makeMessage(), animateIcon: false)
        XCTAssertTrue(textView.isHidden)
        XCTAssertFalse(try XCTUnwrap(titleLabel(in: sut)).isHidden)
    }

    func testPrivacyLinkRejectsTrailingAndBelowTextWhitespace() throws {
        let sut = UTIFooterLinkTextView()
        let url = try XCTUnwrap(URL(string: "https://duckduckgo.com"))
        sut.configure(text: "Learn more", link: .init(text: "Learn more", url: url))
        sut.frame = CGRect(x: 0, y: 0, width: 300, height: 80)
        sut.layoutIfNeeded()
        XCTAssertFalse(sut.point(inside: CGPoint(x: 299, y: 10), with: nil))
        XCTAssertFalse(sut.point(inside: CGPoint(x: 3, y: 79), with: nil))
        XCTAssertTrue(sut.point(inside: CGPoint(x: 3, y: 8), with: nil))
    }

    func testLocalizedLinksUseRenderedWrappedAndRightToLeftRanges() throws {
        let cases: [(String, String, UISemanticContentAttribute)] = [
            ("Dateien werden automatisch geprüft. %@", "Weitere Informationen zu diesen Dateien", .forceLeftToRight),
            ("📎 %@：添付ファイルの取り扱いについて", "詳しく見る", .forceLeftToRight),
            ("تُفحص الملفات تلقائيًا. %@", "معرفة المزيد", .forceRightToLeft)
        ]
        for (format, linkText, direction) in cases {
            let sut = UTIFooterLinkTextView()
            sut.semanticContentAttribute = direction
            let message = UTIFooterMessageMapper().attachmentPrivacyMessage(format: format, learnMoreText: linkText)
            sut.configure(text: message.title, link: try XCTUnwrap(message.link))
            sut.frame = CGRect(x: 0, y: 0, width: 140, height: 180)
            sut.layoutIfNeeded()
            let range = (message.title as NSString).range(of: linkText)
            XCTAssertEqual(sut.attributedText.attribute(.link, at: range.location, effectiveRange: nil) as? URL, message.link?.url)
            let start = try XCTUnwrap(sut.position(from: sut.beginningOfDocument, offset: range.location))
            let end = try XCTUnwrap(sut.position(from: start, offset: range.length))
            let textRange = try XCTUnwrap(sut.textRange(from: start, to: end))
            let rects = sut.selectionRects(for: textRange).map(\.rect).filter { !$0.isEmpty }
            XCTAssertFalse(rects.isEmpty, linkText)
            for rect in rects {
                XCTAssertTrue(sut.point(inside: CGPoint(x: rect.midX, y: rect.midY), with: nil), linkText)
            }
        }
    }

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

    func test_cardHeight_dropsTheTopGapWhenStackedUnderAnotherCard() {
        let sut = UTIFooterCardView()
        sut.configure(with: makeMessage(), animateIcon: false)
        let standalone = height(of: sut)

        sut.isBelowAnotherCard = true
        let stacked = height(of: sut)

        XCTAssertEqual(standalone - stacked, 12, accuracy: 0.5)

        sut.isBelowAnotherCard = false
        XCTAssertEqual(height(of: sut), standalone, accuracy: 0.5)
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

    /// The reset line beside a CTA has to stay on one line; a card with the pill gone can spend two,
    /// while the longer model-switch notice can spend three.
    func test_subtitle_usesTheLineLimitForItsMessageLayout() {
        let sut = UTIFooterCardView()

        sut.configure(with: makeMessage(), animateIcon: false)
        XCTAssertEqual(subtitleLabel(in: sut)?.numberOfLines, 1)

        sut.configure(with: makeMessage(primaryAction: nil), animateIcon: false)
        XCTAssertEqual(subtitleLabel(in: sut)?.numberOfLines, 2)

        sut.configure(with: makeSwitchNotice(), animateIcon: false)
        XCTAssertEqual(subtitleLabel(in: sut)?.numberOfLines, 3)
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

    /// The footer's width follows the input card, so a message can be measured at the flanked
    /// AI-tab width. A title left at its own intrinsic width keeps that measurement, which is what
    /// draws it as a column of one or two characters a line.
    func test_title_ownsItsRoomAtEveryCardWidth() {
        let sut = UTIFooterCardView()
        sut.configure(with: makeLimitReachedMessage(), animateIcon: false)

        for width in [flankedCardWidth, expandedCardWidth] {
            layOut(sut, atWidth: width)

            guard let label = titleLabel(in: sut), let stack = textStack(in: sut) else {
                return XCTFail("Expected the title to be part of the card")
            }
            XCTAssertEqual(label.bounds.width, stack.bounds.width, accuracy: 0.5,
                           "The title has to own the room the CTA leaves it, at card width \(width)")
        }
    }

    func test_oneLineLinkCopy_isCenteredOnItsIcon() throws {
        let sut = UTIFooterCardView()
        sut.configure(with: UTIFooterMessageMapper().termsOfServiceMessage(), animateIcon: false)
        let wideCardWidth: CGFloat = 900
        sut.frame = CGRect(x: 0, y: 0, width: wideCardWidth, height: 0)
        sut.layoutIfNeeded()
        let height = sut.systemLayoutSizeFitting(CGSize(width: wideCardWidth, height: UIView.layoutFittingCompressedSize.height),
                                                 withHorizontalFittingPriority: .required,
                                                 verticalFittingPriority: .fittingSizeLevel).height
        sut.frame = CGRect(x: 0, y: 0, width: wideCardWidth, height: height)
        sut.setNeedsLayout()
        sut.layoutIfNeeded()

        let linkText = try XCTUnwrap(linkTextView(in: sut))
        let shield = try XCTUnwrap(sut.contentView.subviews.first { $0.accessibilityIdentifier == "AIChat.Footer.Icon.Shield" })
        let oneLine = linkText.sizeThatFits(CGSize(width: linkText.bounds.width, height: CGFloat.greatestFiniteMagnitude)).height
        XCTAssertLessThan(oneLine, UIFont.daxFootnoteRegular().lineHeight * 2, "The copy has to fit one line for this to mean anything")
        XCTAssertEqual(linkText.bounds.height, oneLine, accuracy: 0.5)
        let linkTextCenter = sut.contentView.convert(CGPoint(x: linkText.bounds.midX, y: linkText.bounds.midY), from: linkText)
        XCTAssertEqual(shield.center.y, linkTextCenter.y, accuracy: 0.5)
    }

    func testPurchaseAvailabilityRemovesAndRestoresRenderedButtonWhileKeepingNotice() throws {
        let card = UTIFooterCardView()
        let mapper = UTIFooterMessageMapper()
        for trialEligible in [true, false] {
            let warning = DuckAiUsageWarning(window: .daily, message: .freeReached, severity: .reached,
                                            percent: 100, resetsIn: .days(1), isDismissible: false,
                                            action: .tryForFree(isTrialEligible: trialEligible))
            for available in [true, false, true] {
                let message = mapper.message(for: warning, allowsSubscriptionUpsell: available)
                card.configure(with: message, animateIcon: false)
                card.frame = CGRect(x: 0, y: 0, width: phoneWidth, height: height(of: card))
                card.setNeedsLayout()
                card.layoutIfNeeded()

                let button = try XCTUnwrap(actionButton(in: card))
                XCTAssertEqual(button.isHidden, !available)
                XCTAssertEqual(titleLabel(in: card)?.text, message.title)
                XCTAssertEqual(subtitleLabel(in: card)?.text, message.subtitle)
                XCTAssertGreaterThan(height(of: card), 0)
            }
        }
    }

    func test_infoIcon_matchesTheShieldTint() {
        let sut = UTIFooterCardView()
        sut.configure(with: UTIFooterMessageMapper().attachmentPrivacyMessage(), animateIcon: false)
        let info = try? XCTUnwrap(infoIcon(in: sut))
        let shield = sut.subviews.flatMap(\.subviews).compactMap { $0 as? UIImageView }
            .first { $0.accessibilityIdentifier == "AIChat.Footer.Icon.Shield" }
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let expected = UIColor(designSystemColor: .iconsSecondary).resolvedColor(with: traits)
            XCTAssertEqual(info?.tintColor.resolvedColor(with: traits), expected)
            XCTAssertEqual(shield?.tintColor.resolvedColor(with: traits), expected)
        }
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

    private func linkTextView(in card: UTIFooterCardView) -> UTIFooterLinkTextView? {
        card.subviews.flatMap(\.subviews).compactMap { $0 as? UIStackView }.first?
            .arrangedSubviews.compactMap { $0 as? UTIFooterLinkTextView }.first
    }

    private func layOut(_ card: UTIFooterCardView, atWidth width: CGFloat) {
        card.frame = CGRect(x: 0, y: 0, width: width, height: 200)
        card.setNeedsLayout()
        card.layoutIfNeeded()
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
                         isDismissible: isDismissible,
                         link: nil)
    }

    /// The Create Image switch card: a headline over body copy, with no CTA to compete for width.
    private func makeSwitchNotice(
        subtitle: String = "Mistral can't create images. Zero Provider Visibility won't apply until you switch back."
    ) -> UTIFooterMessage {
        UTIFooterMessage(icon: .modelSwitch,
                         title: "Now using 5.6 Luna",
                         subtitle: subtitle,
                         primaryAction: nil,
                         isDismissible: true,
                         link: nil)
    }

    private func makeNotice(title: String = "Opus 4.8 uses limits up to 2-5x faster than basic models.") -> UTIFooterMessage {
        UTIFooterMessage(icon: .info,
                         title: title,
                         subtitle: nil,
                         primaryAction: nil,
                         isDismissible: true,
                         link: nil)
    }

    /// The blocked card as shipped: a short title beside a CTA wide enough to compress it, and no
    /// close button, so the pill reaches the trailing edge.
    private func makeLimitReachedMessage() -> UTIFooterMessage {
        UTIFooterMessage(icon: .alert,
                         title: "Daily limit reached",
                         subtitle: "Resets in 5 hours",
                         primaryAction: .init(title: "Start Using Weekly Limit"),
                         isDismissible: false,
                         link: nil)
    }

    private func makeIconlessMessage() -> UTIFooterMessage {
        UTIFooterMessage(icon: .none,
                         title: "90% of weekly limit",
                         subtitle: "Resets in 2 days",
                         primaryAction: .init(title: "Switch Model"),
                         isDismissible: true,
                         link: nil)
    }
}
