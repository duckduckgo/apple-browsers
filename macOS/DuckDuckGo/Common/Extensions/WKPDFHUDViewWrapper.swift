//
//  WKPDFHUDViewWrapper.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Common
import FoundationExtensions
import Foundation
import WebKit

/// A wrapper for the PDF HUD window with Zoom controls, Download and Open in Preview buttons
/// Used to trigger Save PDF
///
/// Before macOS 27 the HUD is an Obj-C `WKPDFHUDView` drawing its controls with CALayers and toggling visibility with `_setVisible:`.
/// Since macOS 27 (WebKit 309541@main) the HUD is a Swift `WKDefaultPDFHUDView` (or `WKAlternatePDFHUDView`) using NSButtons;
/// `WKPDFHUDView` became a protocol and `_setVisible:` was replaced with `show`.
struct WKPDFHUDViewWrapper {

    static let hudViewClasses: [AnyClass] = ["WKPDFHUDView", "WKDefaultPDFHUDView", "WKAlternatePDFHUDView"].compactMap(NSClassFromString)

    static let performActionForControlSelector = NSSelectorFromString("_performActionForControl:")
    // macOS 27+
    static let showSelector = NSSelectorFromString("show")
    // Legacy (pre-macOS 27) `WKPDFHUDView`
    static let visibleKey = "_visible"
    static let setVisibleSelector = NSSelectorFromString("_setVisible:")

    private enum ControlId: String {
        case savePDF = "arrow.down.circle"
        case zoomIn = "plus.magnifyingglass"
        case zoomOut = "minus.magnifyingglass"
    }

    private let hudView: NSView

    private var isLegacyHUDView: Bool {
        hudView.responds(to: Self.setVisibleSelector)
    }

    static func isHUDView(_ view: NSView) -> Bool {
        hudViewClasses.contains { type(of: view) == $0 }
    }

    /// Create a wrapper over the PDF HUD view validating its class is one of the known PDF HUD view classes
    /// - parameter view: the PDF HUD view to wrap or its subview (macOS 27+ HUD hit-tests to its NSButtons)
    /// - returns nil if the view is not a PDF HUD view or its subview
    init?(view: NSView) {
        var view: NSView = view
        while !Self.isHUDView(view) {
            guard !(view is WKWebView), let superview = view.superview else { return nil }
            view = superview
        }

        guard view.responds(to: Self.performActionForControlSelector) else {
            assertionFailure("\(type(of: view)) doesn‘t respond to _performActionForControl:")
            return nil
        }
        self.hudView = view
    }

    /// Find WebView‘s PDF HUD view at a clicked point
    /// 
    /// Used to get PDF controls view of a clicked WebView frame for `Print…` and `Save As…` PDF context menu commands
    static func getPdfHudView(in webView: WKWebView, at location: NSPoint? = nil) -> Self? {
        guard let hudView = webView.subviews.last(where: { isHUDView($0) && $0.frame.contains(location ?? $0.frame.origin) }) else {
#if DEBUG
            if AppVersion.runType == .normal {
                Task {
                    if await webView.mimeType == "application/pdf" {
                        assertionFailure("WebView doesn‘t have PDF HUD View")
                    }
                }
            }
#endif
            return nil
        }
        return self.init(view: hudView)
    }

    func savePDF() {
        performAction(for: .savePDF)
    }

    func zoomIn() {
        performAction(for: .zoomIn)
    }

    func zoomOut() {
        performAction(for: .zoomOut)
    }

    private func performAction(for controlId: ControlId) {
        guard isLegacyHUDView else {
            // macOS 27+: `WKDefaultPDFHUDView` ignores control actions while its bar is auto-hidden
            // and there‘s no ivar to toggle, so show the HUD (it auto-hides again after a delay)
            if hudView.responds(to: Self.showSelector) {
                hudView.perform(Self.showSelector)
            } else {
                assertionFailure("\(type(of: hudView)) doesn‘t respond to show")
            }
            hudView.perform(Self.performActionForControlSelector, with: controlId.rawValue)
            return
        }

        let wasVisible = isLegacyHUDVisible
        self.setIsVisibleIVar(true)
        defer {
            if !wasVisible {
                self.setIsVisibleIVar(false)
            }
        }
        hudView.perform(Self.performActionForControlSelector, with: controlId.rawValue)
    }

    private var isLegacyHUDVisible: Bool {
        hudView.layer?.sublayers?.first?.opacity ?? 0 > 0
    }

    // try to set _visible ivar value directly to avoid actually showing the HUD
    private func setIsVisibleIVar(_ value: Bool) {
        do {
            try NSException.catch {
                hudView.setValue(value, forKey: Self.visibleKey)
            }
        } catch {
            assertionFailure("\(error)")
            hudView.perform(Self.setVisibleSelector, with: value)
        }
    }

}
