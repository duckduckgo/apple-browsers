//
//  SuggestionTableRowView.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import Cocoa

final class SuggestionTableRowView: NSTableRowView {

    static let identifier = "SuggestionTableRowView"

    var theme: ThemeStyleProviding?

    override func awakeFromNib() {
        super.awakeFromNib()

        setupView()
    }

    override var isEmphasized: Bool {
        get { return true }
        set {}
    }

    override var isSelected: Bool {
        didSet {
            updateCellView()
            needsDisplay = true
        }
    }

    var isBurner: Bool = false
    var isAppRebranded: Bool = false

    private func setupView() {
        selectionHighlightStyle = .none
        wantsLayer = true
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isSelected, let theme else {
            return
        }

        let styleProvider = theme.addressBarStyleProvider
        let colorsProvider = theme.colorsProvider

        let fillColor: NSColor = {
            if isAppRebranded {
                return colorsProvider.suggestionsHighlightBackgroundColor
            }

            return isBurner ? .burnerAccent : theme.palette.accentPrimary
        }()

        let cornerRadius = styleProvider.suggestionHighlightCornerRadius
        let horizontalPadding = styleProvider.suggestionHighlightHorizontalPadding

        let selectionRect = bounds.insetBy(dx: horizontalPadding, dy: 0)
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: cornerRadius, yRadius: cornerRadius)

        fillColor.setFill()
        path.fill()
    }

    private func updateCellView() {
        for subview in subviews {
            if let cellView = subview as? SuggestionTableCellView {
                cellView.isSelected = isSelected
                isBurner = cellView.isBurner
            }
        }
    }

    override func layout() {
        super.layout()

        updateCellView()
        needsDisplay = true
    }

}
