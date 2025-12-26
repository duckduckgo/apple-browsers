//
//  SearchField.swift
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
import AppKit

final class SearchField: NSSearchField {

    override class var cellClass: AnyClass? {
        get {
            SearchFieldCell.self
        }
        set {
            // NO-OP
        }
    }

    var searchFieldCell: SearchFieldCell? {
        cell as? SearchFieldCell
    }

    var metrics: SearchFieldMetrics = .default {
        didSet {
            needsDisplay = true
        }
    }

    var borderColor: NSColor = .gray {
        didSet {
            needsDisplay = true
        }
    }

    var borderHighlightColor: NSColor = .blue {
        didSet {
            needsDisplay = true
        }
    }

    var innerBackgroundColor: NSColor = .clear {
        didSet {
            needsDisplay = true
        }
    }
}

final class SearchFieldCell: NSSearchFieldCell {

    private var searchField: SearchField {
        // swiftlint:disable:next force_cast
        controlView as! SearchField
    }

    private var metrics: SearchFieldMetrics {
        searchField.metrics
    }

    private var backgroundStrokeColor: NSColor {
        showsFirstResponder ? searchField.borderHighlightColor : searchField.borderColor
    }

    private var borderLineWidth: CGFloat {
        showsFirstResponder ? metrics.borderHiglightedLineWidth : metrics.borderLineWidth
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        // Draw: Background
        let backgroundFrame = cellFrame.insetBy(dx: 1, dy: 1)
        let backgroundPath = NSBezierPath(roundedRect: backgroundFrame, xRadius: metrics.cornerRadius, yRadius: metrics.cornerRadius)

        searchField.innerBackgroundColor.setFill()
        backgroundPath.fill()

        // Draw: Border
        backgroundStrokeColor.setStroke()
        backgroundPath.lineWidth = borderLineWidth
        backgroundPath.stroke()

        // Draw: Interior Elements (Text)
        drawInterior(withFrame: backgroundFrame, in: controlView)
    }

    override func drawFocusRingMask(withFrame cellFrame: NSRect, in controlView: NSView) {
        // NO-OP: We'll render our custom Focus Ringt
    }
}

struct SearchFieldMetrics {
    let borderLineWidth: CGFloat
    let borderHiglightedLineWidth: CGFloat
    let cornerRadius: CGFloat
}

extension SearchFieldMetrics {
    static var `default`: SearchFieldMetrics {
        SearchFieldMetrics(borderLineWidth: 1, borderHiglightedLineWidth: 2, cornerRadius: 6)
    }
}
