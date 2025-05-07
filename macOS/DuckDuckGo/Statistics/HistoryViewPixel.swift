//
//  HistoryViewPixel.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Foundation
import HistoryView
import PixelKit

/**
 * This enum keeps pixels related to HTML History View.
 *
 * > Unless otherwise specified, all pixels are daily + standard.
 *
 * > Related links:
 * [Privacy Triage TBD](https://app.asana.com/0/69071770703008/1209581218702028)
 * [Detailed Pixels description](https://app.asana.com/0/1201899738287924/1209364382402737)
 *
 * Anomaly Investigation:
 * - Unless otherwise specified, anomaly in all the pixels will be related to an increase/drop in app use.
 */
enum HistoryViewPixel: PixelKitEventV2 {

    // MARK: - Permanent Pixels

    /**
     * Event Trigger: History View is displayed to user.
     *
     */
    case historyPageShown(HistoryPageSource)

    /**
     * Event Trigger: History View filter is set (range, search term or domain).
     */
    case filterSet(FilterKind)

    /**
     * Event Trigger: History View filter is cleared (or range is set to `all`).
     */
    case filterCleared

    /**
     * Event Trigger: History item is opened.
     */
    case itemOpened(OpenItemType)

    /**
     * Event Trigger: History item was deleted. This pixel indicates any type of deletion.
     *
     * > This is a daily-only pixel.
     */
    case delete

    /**
     * Event Trigger: A single history item was deleted by pressing delete key.
     */
    case singleItemDeleted

    /**
     * Event Trigger: History items were deleted via the delete dialog.
     */
    case multipleItemsDeleted(DeletedBatchKind, burn: Bool)

    // MARK: -

    enum HistoryPageSource: String {
        case topMenu = "top-menu", sideMenu = "side-menu", introDialog = "intro-dialog"
    }

    enum FilterKind: String {
        case range, searchTerm = "search-term", domain

        init(_ queryKind: DataModel.HistoryQueryKind) {
            switch queryKind {
            case .rangeFilter:
                self = .range
            case .domainFilter:
                self = .domain
            case .searchTerm:
                self = .searchTerm
            }
        }
    }

    enum DeletedBatchKind: String {
        case all, range, searchTerm = "search-term", domain, multiSelect = "multi-select"

        init(_ queryKind: DataModel.HistoryQueryKind) {
            switch queryKind {
            case .rangeFilter(.all):
                self = .all
            case .rangeFilter:
                self = .range
            case .domainFilter:
                self = .domain
            case .searchTerm:
                self = .searchTerm
            }
        }
    }

    enum OpenItemType: String {
        case single, multiple
    }

    // MARK: - Debug

    /**
     * Event Trigger: History View reports a JavaScript exception.
     *
     * Anomaly Investigation:
     * - Anomaly in this pixel may mean a critical breakage in the History View.
     */
    case historyPageExceptionReported

    var name: String {
        switch self {
        case .historyPageShown: return "history-page_shown"
        case .historyPageExceptionReported: return "history-page_exception-reported"
        case .filterSet: return "history-page_filter-set"
        case .filterCleared: return "history-page_filter-cleared"
        case .itemOpened: return "history-page_item-opened"
        case .delete: return "history-page_any-delete"
        case .singleItemDeleted: return "history-page_item-deleted"
        case .multipleItemsDeleted: return "history-page_items-deleted"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .historyPageShown(let source):
            return [Parameters.source: source.rawValue]
        case .historyPageExceptionReported:
            return nil
        case .filterSet(let filter):
            return [Parameters.filter: filter.rawValue]
        case .filterCleared:
            return nil
        case .itemOpened(let type):
            return [Parameters.type: type.rawValue]
        case .delete:
            return nil
        case .singleItemDeleted:
            return nil
        case .multipleItemsDeleted(let batchKind, let burn):
            return [Parameters.filter: batchKind.rawValue, Parameters.type: burn ? "burn" : "delete"]
        }
    }

    var error: (any Error)? {
        nil
    }

    enum Parameters {
        static let filter = "filter"
        static let type = "type"
        static let message = "message"
        static let source = "source"
    }
}
