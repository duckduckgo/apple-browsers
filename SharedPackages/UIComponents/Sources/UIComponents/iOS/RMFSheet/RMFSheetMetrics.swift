//
//  RMFSheetMetrics.swift
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

#if os(iOS)

import SwiftUI
import UIKit

/// The four compositions of the RMF sheet template.
///
/// Phone layouts come from the `RMF Sheet` Figma component (Fullscreen = false / true). iPad layouts come
/// from `RMF Sheet / iPad` (Presentation = Regular / Compact) and are chosen by the horizontal size class.
public enum RMFSheetLayout: Equatable, CaseIterable {
    /// Content-height phone sheet.
    case phone
    /// Tall phone sheet: content sits in a card with the actions pinned at the bottom.
    case phoneFullscreen
    /// Centred, content-height iPad form sheet.
    case padRegular
    /// Full-width iPad sheet in a narrow window, with the actions pinned at the bottom.
    case padCompact

    /// Resolves the layout from the device idiom and the horizontal size class.
    /// `fullscreen` only applies to phones; iPad picks Regular or Compact from the size class.
    public static func resolve(idiom: UIUserInterfaceIdiom,
                               horizontalSizeClass: UserInterfaceSizeClass?,
                               fullscreen: Bool) -> RMFSheetLayout {
        guard idiom == .pad else {
            return fullscreen ? .phoneFullscreen : .phone
        }
        return horizontalSizeClass == .compact ? .padCompact : .padRegular
    }

    public var metrics: RMFSheetMetrics {
        RMFSheetMetrics(layout: self)
    }
}

/// Spacing and sizing for the RMF sheet, from the `RMF Sheet` spec block in Figma.
///
/// Values are logical points. Paddings are measured to the visible edge of each element; the close
/// button's extra hit area is subtracted where it is laid out.
public struct RMFSheetMetrics: Equatable {

    public let layout: RMFSheetLayout

    public init(layout: RMFSheetLayout) {
        self.layout = layout
    }

    // MARK: Sheet

    /// Whether this is one of the iPad layouts.
    public var isPad: Bool {
        layout == .padRegular || layout == .padCompact
    }

    /// Reference width of the sheet in Figma. The view itself fills the width it is offered.
    public var referenceWidth: CGFloat {
        switch layout {
        case .phone, .phoneFullscreen: 390
        case .padRegular: 540
        case .padCompact: 507
        }
    }

    /// Corner radius the presenting container is expected to use. Used by previews.
    public var sheetCornerRadius: CGFloat {
        isPad ? 38 : 44
    }

    /// Whether the composition is tall, with the actions pinned to the bottom.
    public var pinsActionsToBottom: Bool {
        layout == .phoneFullscreen || layout == .padCompact
    }

    /// Whether the content sits in a card wrapper (`Sheet/Inline Padding` margin, `Card/Top Padding` inset).
    public var usesCard: Bool {
        layout == .phoneFullscreen
    }

    // MARK: Top bar

    /// Space from the top of the sheet to the close button's visible edge.
    public var closeTopPadding: CGFloat { isPad ? 16 : 20 }
    /// Space from the trailing edge of the sheet to the close button's visible edge.
    public let closeTrailingPadding: CGFloat = 20
    /// Space below the close button (iPad `Leading dismissal` bottom padding).
    public var closeBottomPadding: CGFloat { isPad ? 4 : 0 }
    /// Diameter of the close button's visible circle.
    public let closeButtonDiameter: CGFloat = 44
    /// Gap between the top bar and the card (`Card/Outer Margin`).
    public let cardOuterGap: CGFloat = 16

    // MARK: Card (phone fullscreen)

    /// Horizontal margin around the card (`Sheet/Inline Padding`).
    public let cardHorizontalMargin: CGFloat = 24
    /// Inset from the top of the card to the media (`Card/Top Padding`).
    public let cardTopPadding: CGFloat = 24
    public let cardCornerRadius: CGFloat = 32

    // MARK: Media

    /// Top padding above the media when there is no close button above it.
    public let mediaTopPaddingWithoutClose: CGFloat = 24
    /// Horizontal padding of the media slot.
    public var mediaHorizontalPadding: CGFloat { isPad ? 24 : 0 }
    /// Space below the media slot (`Sheet/Media Trailing`).
    public let mediaTrailing: CGFloat = 8
    /// Size of a standard pictogram (`Media/Pictogram Size`). Custom media keeps its own size.
    public let pictogramSize: CGFloat = 96

    // MARK: Message

    /// Space above the eyebrow / title block (`Sheet/Content Leading`, iPad `Card/Outer Margin`).
    public let messageTopPadding: CGFloat = 16
    /// Horizontal padding of the eyebrow, title and body.
    public var messageHorizontalPadding: CGFloat {
        switch layout {
        case .phone, .padCompact: 24
        case .phoneFullscreen: 0
        case .padRegular: 32
        }
    }
    /// Gap between the eyebrow, title and body (`Sheet/Text Gap`).
    public let textGap: CGFloat = 8

    // MARK: Content block

    /// Space above the content block (`Sheet/Content Block Gap`).
    public let contentTopPadding: CGFloat = 20
    /// Horizontal padding of the content block. Zero inside the phone card, which already has a margin.
    public var contentHorizontalPadding: CGFloat {
        layout == .phoneFullscreen ? 0 : 24
    }

    // MARK: Actions

    /// Space above the actions (`Sheet/Content To Actions` on phone, 24 on iPad).
    public var actionsTopPadding: CGFloat { isPad ? 24 : 20 }
    /// Space below the actions, or below the footnote when there is one (`Sheet/Bottom Padding`).
    public let actionsBottomPadding: CGFloat = 24
    /// Horizontal padding of the actions. Zero inside the phone card.
    public var actionsHorizontalPadding: CGFloat {
        layout == .phoneFullscreen ? 0 : 24
    }
    /// Gap between stacked actions and before the footnote (`Sheet/Action Gap`).
    public let actionGap: CGFloat = 8

}

#endif
