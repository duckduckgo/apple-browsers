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

import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class UTIFooterCardViewTests: XCTestCase {

    private let phoneWidth: CGFloat = 390

    func test_cardHeight_isUnchangedByALongTitle() {
        let sut = UTIFooterCardView()

        sut.configure(with: makeMessage(title: "90% of weekly limit"), animateIcon: false)
        let compact = height(of: sut)

        sut.configure(with: makeMessage(title: "90% of weekly limit for advanced models on this plan"), animateIcon: false)
        let long = height(of: sut)

        XCTAssertEqual(compact, long, accuracy: 0.5)
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

    func test_cardHeight_isUnchangedByTheModelPickerChevron() {
        let sut = UTIFooterCardView()
        sut.modelPickerMenu = UIMenu(children: [UIAction(title: "5.4 mini") { _ in }])

        sut.configure(with: makeMessage(showsModelPicker: false), animateIcon: false)
        let plain = height(of: sut)

        sut.configure(with: makeMessage(showsModelPicker: true), animateIcon: false)
        let withChevron = height(of: sut)

        XCTAssertEqual(plain, withChevron, accuracy: 0.5)
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

    // MARK: - Helpers

    private func height(of view: UTIFooterCardView) -> CGFloat {
        view.frame = CGRect(x: 0, y: 0, width: phoneWidth, height: 0)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        return view.systemLayoutSizeFitting(CGSize(width: phoneWidth, height: UIView.layoutFittingCompressedSize.height),
                                            withHorizontalFittingPriority: .required,
                                            verticalFittingPriority: .fittingSizeLevel).height
    }

    private func makeMessage(title: String = "90% of weekly limit",
                             subtitle: String? = "Resets in 2 days",
                             showsModelPicker: Bool = false) -> UTIFooterMessage {
        makeMessage(title: title,
                    subtitle: subtitle,
                    primaryAction: .init(title: "Switch to 5.4 mini", showsModelPicker: showsModelPicker))
    }

    private func makeMessage(title: String = "90% of weekly limit",
                             subtitle: String? = "Resets in 2 days",
                             primaryAction: UTIFooterMessage.PrimaryAction?) -> UTIFooterMessage {
        UTIFooterMessage(icon: .usageRing(progress: 0.9),
                         title: title,
                         subtitle: subtitle,
                         primaryAction: primaryAction,
                         isDismissible: true)
    }
}
