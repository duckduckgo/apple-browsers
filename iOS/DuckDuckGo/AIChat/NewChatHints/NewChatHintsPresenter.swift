//
//  NewChatHintsPresenter.swift
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

import Combine
import UIKit
import WebKit

/// Puts the coordinator's new chat hints above the full-tab Duck.ai input card, moving with it as the keyboard does.
/// Until the page and the row can share the empty chat's space, the row stays hidden wherever it would cover what
/// the page draws there (the Duck.ai logo, the privacy line, a greeting): it asks the page what sits in its band.
@MainActor
final class NewChatHintsPresenter {

    enum Metrics {
        static let cardSpacing: CGFloat = 10
        /// Clearance kept between the page's content and the row.
        static let contentClearance: CGFloat = 8
        /// The page settles its layout a moment after the keyboard moves; measure again then.
        static let settleDelay: TimeInterval = 0.35
    }

    private weak var coordinator: UnifiedToggleInputCoordinator?
    private weak var parentView: UIView?
    private let webView: () -> WKWebView?
    private let row = NewChatHintsView()
    private var hints: [NewChatHint] = []
    /// The band last measured, in `parentView`, and whether the page draws in it.
    private var measuredBand: CGRect?
    private var isBandClear = false
    private var measurement = 0
    private var cancellable: AnyCancellable?

    init(coordinator: UnifiedToggleInputCoordinator, parentView: UIView, below inputContainer: UIView,
         webView: @escaping () -> WKWebView?) {
        self.coordinator = coordinator
        self.parentView = parentView
        self.webView = webView
        row.translatesAutoresizingMaskIntoConstraints = false
        row.accessibilityIdentifier = "NewChatHints"
        if inputContainer.superview === parentView {
            parentView.insertSubview(row, belowSubview: inputContainer)
        } else {
            parentView.addSubview(row)
        }
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.trailingAnchor),
            row.bottomAnchor.constraint(equalTo: coordinator.viewController.inputCardTopAnchor, constant: -Metrics.cardSpacing),
        ])
        row.onHintSelected = { [weak coordinator] in coordinator?.performNewChatHint($0) }
        cancellable = coordinator.$newChatHints.sink { [weak self] hints in
            guard let self else { return }
            let isNewSet = hints.isEmpty != self.hints.isEmpty
            self.hints = hints
            if isNewSet {
                self.measuredBand = nil
                self.isBandClear = false
            }
            self.updateLayout()
        }
    }

    /// Call on every layout pass: the band above the card moves with the keyboard.
    func updateLayout() {
        guard let band = rowBand, !hints.isEmpty else {
            apply([])
            return
        }
        if band != measuredBand {
            measuredBand = band
            measure(band)
            DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.settleDelay) { [weak self] in
                guard let self, self.measuredBand == band else { return }
                self.measure(band)
            }
        }
        apply(isBandClear ? hints : [])
    }

    private func apply(_ shown: [NewChatHint]) {
        guard shown != row.hints || row.isHidden == !shown.isEmpty else { return }
        row.setHints(shown, animated: true)
        if !shown.isEmpty {
            coordinator?.newChatHintsDidAppear(shown)
        }
    }

    /// Where the row sits, with its clearance, in `parentView`. Nil while the card isn't laid out.
    private var rowBand: CGRect? {
        guard let coordinator, let parentView else { return nil }
        let card = coordinator.viewController.inputCardFrame(in: parentView)
        guard !card.isEmpty else { return nil }
        let height = NewChatHintsView.Metrics.height + Metrics.contentClearance
        return CGRect(x: card.minX, y: card.minY - Metrics.cardSpacing - height, width: card.width, height: height).integral
    }

    /// Asks the page whether anything it draws reaches into `band`. Anything unknown keeps the row hidden.
    private func measure(_ band: CGRect) {
        guard let parentView, let webView = webView(), webView.window != nil else {
            isBandClear = false
            return
        }
        measurement += 1
        let current = measurement
        let inWebView = webView.convert(band, from: parentView)
        let scroll = webView.scrollView
        let zoom = max(scroll.zoomScale, 0.01)
        let top = (inWebView.minY + scroll.contentOffset.y) / zoom
        let bottom = (inWebView.maxY + scroll.contentOffset.y) / zoom
        let script = Self.bandHasContentScript(top: top, bottom: bottom)
        webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self] result in
            guard let self, current == self.measurement else { return }
            let hasContent = (try? result.get()) as? Bool
            self.isBandClear = hasContent == false
            self.apply(self.isBandClear ? self.hints : [])
        }
    }

    /// True when visible text or an image of the page intersects the band. The band is given in page coordinates.
    static func bandHasContentScript(top: CGFloat, bottom: CGFloat) -> String {
        """
        (() => {
          const top = \(top) - window.scrollY, bottom = \(bottom) - window.scrollY;
          const hits = r => r.width > 0 && r.height > 0 && r.bottom > top && r.top < bottom;
          const visible = el => {
            for (let e = el; e && e.nodeType === 1; e = e.parentElement) {
              const s = getComputedStyle(e);
              if (s.display === 'none' || s.visibility === 'hidden' || parseFloat(s.opacity) === 0) return false;
            }
            return true;
          };
          for (const el of document.querySelectorAll('img, svg, canvas, video, picture')) {
            if (hits(el.getBoundingClientRect()) && visible(el)) return true;
          }
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
          const range = document.createRange();
          for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            if (!node.textContent.trim()) continue;
            range.selectNodeContents(node);
            for (const r of range.getClientRects()) {
              if (hits(r) && visible(node.parentElement)) return true;
            }
          }
          return false;
        })()
        """
    }
}
