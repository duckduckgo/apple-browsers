//
//  SuggestionRow.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import SwiftUI

/// One row in the unified UTI suggestions list. Pure data — carries no actions.
/// Selection and tap handling are dispatched by `id` to the active view model.
struct SuggestionRow: Identifiable, Equatable {

    enum Accessory: Equatable {
        case none
        case tapAhead
        case delete
    }

    let id: String
    let icon: Image
    let title: String
    /// When set, the matched prefix of `title` is rendered bold.
    let query: String?
    let subtitle: String?
    let accessory: Accessory
    let accessibilityID: String

    init(id: String,
         icon: Image,
         title: String,
         query: String? = nil,
         subtitle: String? = nil,
         accessory: Accessory = .none,
         accessibilityID: String) {
        self.id = id
        self.icon = icon
        self.title = title
        self.query = query
        self.subtitle = subtitle
        self.accessory = accessory
        self.accessibilityID = accessibilityID
    }
}

/// A titled group of rows. Sections with no rows are omitted by producers.
struct SuggestionSection: Identifiable, Equatable {
    let id: String
    let title: String?
    let rows: [SuggestionRow]

    init(id: String, title: String? = nil, rows: [SuggestionRow]) {
        self.id = id
        self.title = title
        self.rows = rows
    }
}
