//
//  SuggestionRowIcon+Glyph.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import DesignResourcesKitIcons
import UIKit

extension SuggestionRowIcon {
    /// The 24pt design-system glyph for this semantic icon.
    var glyph: UIImage {
        switch self {
        case .globe: return DesignSystemImages.Glyphs.Size24.globe
        case .bookmark: return DesignSystemImages.Glyphs.Size24.bookmark
        case .favorite: return DesignSystemImages.Glyphs.Size24.bookmarkFavorite
        case .history: return DesignSystemImages.Glyphs.Size24.history
        case .openTab: return DesignSystemImages.Glyphs.Size24.tabsMobile
        case .search: return DesignSystemImages.Glyphs.Size24.findSearchSmall
        case .aiChat: return DesignSystemImages.Glyphs.Size24.aiChat
        case .pin: return DesignSystemImages.Glyphs.Size24.pin
        }
    }
}
