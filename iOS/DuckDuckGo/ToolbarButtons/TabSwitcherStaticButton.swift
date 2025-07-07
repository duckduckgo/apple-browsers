//
//  TabSwitcherStaticButton.swift
//  DuckDuckGo
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

import UIKit

final class TabSwitcherStaticButton: BrowserChromeButton, TabSwitcherButton {

    private let tabSwitcherView = TabSwitcherStaticView()
    weak var delegate: TabSwitcherButtonDelegate?

    var text: String? {
        tabSwitcherView.label.text
    }

    // Just to satisfy protocol requirement
    let pointer: UIView? = nil

    init() {
        super.init()
        self.frame = CGRect(x: 0, y: 0, width: 34, height: 44)

        addAction(UIAction(handler: { [weak self] _ in
            guard let self else { return }

            self.delegate?.showTabSwitcher(self)

        }), for: .touchUpInside)

        let longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(onNewTabLongPressRecognizer))
        longPressRecognizer.minimumPressDuration = 0.4
        addGestureRecognizer(longPressRecognizer)

        setUpSubviews()
        self.isPointerInteractionEnabled = true
    }

    @available(*, unavailable)
    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setUpSubviews() {
        addSubview(tabSwitcherView)

        tabSwitcherView.frame = bounds
        tabSwitcherView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tabSwitcherView.isUserInteractionEnabled = false

        // This is needed so the BrowserChromeButton is resized appropriately.
        setImage(.fake(size: CGSize(width: 24, height: 24)))
    }

    var tabCount: Int = 0 {
        didSet {
            refresh()
        }
    }

    private func refresh() {
        if tabCount == 0 {
            tabSwitcherView.updateCount(nil, isSymbol: false)
            return
        }

        let useSymbol = tabCount >= Constants.maxTextTabs
        let text = useSymbol ? "∞" : "\(tabCount)"
        tabSwitcherView.updateCount(text, isSymbol: useSymbol)
    }

    var hasUnread: Bool {
        get {
            tabSwitcherView.hasUnread
        }

        set {
            tabSwitcherView.hasUnread = newValue
        }
    }

    func animateUpdate(update: @escaping () -> Void) {
        let animator1 = UIViewPropertyAnimator(duration: 0.25, curve: .easeIn) {
            self.tabSwitcherView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        }

        let animator2 = UIViewPropertyAnimator(duration: 0.8, dampingRatio: 0.3) {
            self.tabSwitcherView.transform = .identity
        }

        animator1.addCompletion { _ in
            update()
            animator2.startAnimation()
        }

        animator1.startAnimation()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()

        tabSwitcherView.tintColor = tintColor
    }

    @objc private func onNewTabLongPressRecognizer(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began else { return }

        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        delegate?.launchNewTab(self)
    }

    private struct Constants {
        static let maxTextTabs = 100
    }
}

private extension UIImage {
    static func fake(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            // No drawing operations needed for transparency
        }
        return image
    }
}
