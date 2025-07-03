//
//  XCUIElementTypeExtension.swift
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

import XCTest

extension XCUIElement.ElementType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .any: return "any"
        case .other: return "other"
        case .application: return "application"
        case .group: return "group"
        case .window: return "window"
        case .sheet: return "sheet"
        case .drawer: return "drawer"
        case .alert: return "alert"
        case .dialog: return "dialog"
        case .button: return "button"
        case .radioButton: return "radioButton"
        case .radioGroup: return "radioGroup"
        case .checkBox: return "checkBox"
        case .disclosureTriangle: return "disclosureTriangle"
        case .popUpButton: return "popUpButton"
        case .comboBox: return "comboBox"
        case .menuButton: return "menuButton"
        case .toolbarButton: return "toolbarButton"
        case .popover: return "popover"
        case .keyboard: return "keyboard"
        case .key: return "key"
        case .navigationBar: return "navigationBar"
        case .tabBar: return "tabBar"
        case .tabGroup: return "tabGroup"
        case .toolbar: return "toolbar"
        case .statusBar: return "statusBar"
        case .table: return "table"
        case .tableRow: return "tableRow"
        case .tableColumn: return "tableColumn"
        case .outline: return "outline"
        case .outlineRow: return "outlineRow"
        case .browser: return "browser"
        case .collectionView: return "collectionView"
        case .slider: return "slider"
        case .pageIndicator: return "pageIndicator"
        case .progressIndicator: return "progressIndicator"
        case .activityIndicator: return "activityIndicator"
        case .segmentedControl: return "segmentedControl"
        case .picker: return "picker"
        case .pickerWheel: return "pickerWheel"
        case .switch: return "switch"
        case .toggle: return "toggle"
        case .link: return "link"
        case .image: return "image"
        case .icon: return "icon"
        case .searchField: return "searchField"
        case .scrollView: return "scrollView"
        case .scrollBar: return "scrollBar"
        case .staticText: return "staticText"
        case .textField: return "textField"
        case .secureTextField: return "secureTextField"
        case .datePicker: return "datePicker"
        case .textView: return "textView"
        case .menu: return "menu"
        case .menuItem: return "menuItem"
        case .menuBar: return "menuBar"
        case .menuBarItem: return "menuBarItem"
        case .map: return "map"
        case .webView: return "webView"
        case .incrementArrow: return "incrementArrow"
        case .decrementArrow: return "decrementArrow"
        case .timeline: return "timeline"
        case .ratingIndicator: return "ratingIndicator"
        case .valueIndicator: return "valueIndicator"
        case .splitGroup: return "splitGroup"
        case .splitter: return "splitter"
        case .relevanceIndicator: return "relevanceIndicator"
        case .colorWell: return "colorWell"
        case .helpTag: return "helpTag"
        case .matte: return "matte"
        case .dockItem: return "dockItem"
        case .ruler: return "ruler"
        case .rulerMarker: return "rulerMarker"
        case .grid: return "grid"
        case .levelIndicator: return "levelIndicator"
        case .cell: return "cell"
        case .layoutArea: return "layoutArea"
        case .layoutItem: return "layoutItem"
        case .handle: return "handle"
        case .stepper: return "stepper"
        case .tab: return "tab"
        case .touchBar: return "touchBar"
        case .statusItem: return "statusItem"
        @unknown default:
            return "unknown(\(self.rawValue))"
        }
    }
}
