//
//  FindInPageView.swift
//  DuckDuckGo
//
//  Copyright © 2019 DuckDuckGo. All rights reserved.
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
import DesignResourcesKit
import DesignResourcesKitIcons

protocol FindInPageViewDelegate: NSObjectProtocol {
    
    func done(findInPageView: FindInPageView)
    
}

class FindInPageView: UIView {

    @IBOutlet weak var container: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var previousButton: UIButton!
    @IBOutlet weak var searchLoupe: UIImageView!
    @IBOutlet weak var counterLabel: UILabel!
    @IBOutlet weak var searchBackground: UIView!
    @IBOutlet weak var doneButton: UIButton!
    @IBOutlet weak var inputText: UITextField!
    @IBOutlet weak var activityView: UIActivityIndicatorView!

    weak var delegate: FindInPageViewDelegate?
    weak var findInPage: FindInPage?

    override func awakeFromNib() {
        super.awakeFromNib()
        
        layer.shadowRadius = 1
        layer.shadowOffset = CGSize(width: 0, height: -1.0 / UIScreen.main.scale)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.masksToBounds = false

        searchLoupe.image = DesignSystemImages.Glyphs.Size20.findSearch
        nextButton.setImage(DesignSystemImages.Glyphs.Size24.arrowDown, for: .normal)
        previousButton.setImage(DesignSystemImages.Glyphs.Size24.arrowUp, for: .normal)

        nextButton.isPointerInteractionEnabled = true
        nextButton.accessibilityLabel = UserText.keyCommandFindNext
        previousButton.isPointerInteractionEnabled = true
        previousButton.accessibilityLabel = UserText.keyCommandFindPrevious
        doneButton.isPointerInteractionEnabled = true

        inputText.accessibilityLabel = UserText.findInPage

        decorate()
    }

    @available(iOS 26.0, *)
    func applyFloatingUI() {
        backgroundColor = UIColor.black.withAlphaComponent(0.2)
        layer.shadowOpacity = 0
        container.backgroundColor = .clear

        NSLayoutConstraint.deactivate(constraints.filter {
            $0.firstItem === container && $0.firstAttribute == .top
        })
        NSLayoutConstraint.deactivate(container.constraints)
        NSLayoutConstraint.deactivate(nextButton.constraints)
        NSLayoutConstraint.deactivate(previousButton.constraints)
        NSLayoutConstraint.deactivate(searchBackground.constraints.filter {
            $0.firstAttribute == .height && $0.secondItem == nil
        })

        let doneEffect = UIGlassEffect(style: .regular)
        doneEffect.tintColor = .systemBlue
        let doneGlass = UIVisualEffectView(effect: doneEffect)
        let searchGlass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        let navigationGlass = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
        for glass in [doneGlass, searchGlass, navigationGlass] {
            glass.cornerConfiguration = .capsule()
            glass.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(glass)
        }

        let doneLabel = doneButton.title(for: .normal)
        doneButton.setTitle(nil, for: .normal)
        doneButton.setImage(UIImage(systemName: "checkmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)), for: .normal)
        doneButton.accessibilityLabel = doneLabel
        doneGlass.contentView.addSubview(doneButton)
        searchGlass.contentView.addSubview(searchBackground)
        searchGlass.contentView.addSubview(activityView)
        navigationGlass.contentView.addSubview(previousButton)
        navigationGlass.contentView.addSubview(nextButton)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalTo: widthAnchor, constant: -24),
            container.heightAnchor.constraint(equalToConstant: 48),
            doneGlass.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            doneGlass.topAnchor.constraint(equalTo: container.topAnchor),
            doneGlass.widthAnchor.constraint(equalToConstant: 48),
            doneGlass.heightAnchor.constraint(equalToConstant: 48),
            searchGlass.leadingAnchor.constraint(equalTo: doneGlass.trailingAnchor, constant: 8),
            searchGlass.topAnchor.constraint(equalTo: container.topAnchor),
            searchGlass.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            navigationGlass.leadingAnchor.constraint(equalTo: searchGlass.trailingAnchor, constant: 8),
            navigationGlass.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            navigationGlass.topAnchor.constraint(equalTo: container.topAnchor),
            navigationGlass.widthAnchor.constraint(equalToConstant: 80),
            navigationGlass.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            doneButton.topAnchor.constraint(equalTo: doneGlass.contentView.topAnchor),
            doneButton.leadingAnchor.constraint(equalTo: doneGlass.contentView.leadingAnchor),
            doneButton.trailingAnchor.constraint(equalTo: doneGlass.contentView.trailingAnchor),
            doneButton.bottomAnchor.constraint(equalTo: doneGlass.contentView.bottomAnchor),
            searchBackground.topAnchor.constraint(equalTo: searchGlass.contentView.topAnchor),
            searchBackground.leadingAnchor.constraint(equalTo: searchGlass.contentView.leadingAnchor),
            searchBackground.trailingAnchor.constraint(equalTo: searchGlass.contentView.trailingAnchor),
            searchBackground.bottomAnchor.constraint(equalTo: searchGlass.contentView.bottomAnchor),
            previousButton.topAnchor.constraint(equalTo: navigationGlass.contentView.topAnchor),
            previousButton.leadingAnchor.constraint(equalTo: navigationGlass.contentView.leadingAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 40),
            previousButton.bottomAnchor.constraint(equalTo: navigationGlass.contentView.bottomAnchor),
            nextButton.topAnchor.constraint(equalTo: navigationGlass.contentView.topAnchor),
            nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor),
            nextButton.trailingAnchor.constraint(equalTo: navigationGlass.contentView.trailingAnchor),
            nextButton.bottomAnchor.constraint(equalTo: navigationGlass.contentView.bottomAnchor),
            activityView.trailingAnchor.constraint(equalTo: searchGlass.contentView.trailingAnchor, constant: -8),
            activityView.centerYAnchor.constraint(equalTo: searchGlass.contentView.centerYAnchor)
        ])

        tintColor = .label
        doneButton.tintColor = .white
        nextButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        nextButton.tintColor = .secondaryLabel
        previousButton.setImage(UIImage(systemName: "chevron.up"), for: .normal)
        previousButton.tintColor = .secondaryLabel
        counterLabel.textColor = .secondaryLabel
        searchBackground.backgroundColor = .clear
        inputText.textColor = .label
        inputText.clearButtonMode = .whileEditing
        searchLoupe.tintColor = .label
    }
    
    override func resignFirstResponder() -> Bool {
        return inputText.resignFirstResponder()
    }
    
    func update(with findInPage: FindInPage?, updateTextField: Bool) {
        activityView.stopAnimating()
        
        self.findInPage = findInPage
        isHidden = findInPage == nil
        if updateTextField {
            inputText?.text = findInPage?.searchTerm
        }
        counterLabel.isHidden = findInPage?.total ?? 0 == 0

        let current = findInPage?.current ?? 0
        let total = findInPage?.total ?? 0
        counterLabel.text = UserText.findInPageCount.format(arguments: current, total)
    }

    override func becomeFirstResponder() -> Bool {
        return inputText.becomeFirstResponder()
    }

    @IBAction func done() {
        // Idempotent — `closeFindInPage` defensively calls this on every WKWebView navigation
        // (see TabViewController's decidePolicyFor handler), but the delegate's `done` side-effect
        // un-hides the bottom navigation bar. Bail if the view is not actually visible so we
        // don't leak that un-hide into states that need the bar hidden (e.g. Duck.ai voice mode).
        guard !isHidden else { return }
        isHidden = true
        findInPage?.done()
        delegate?.done(findInPageView: self)
        inputText.resignFirstResponder()
    }

    @IBAction func next() {
        findInPage?.next()
    }

    @IBAction func previous() {
        findInPage?.previous()
    }

    @IBAction func textChanged() {
        guard let text = inputText.text else {
            return
        }
        counterLabel.isHidden = true
        
        guard let findInpage = findInPage,
            findInpage.search(forText: text) else {
                return
        }
        activityView.startAnimating()
    }
    
}

extension FindInPageView: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        inputText.resignFirstResponder()
        next()
        return true
    }
    
}

extension FindInPageView {
    private func decorate() {
        let theme = ThemeManager.shared.currentTheme
        backgroundColor = theme.barBackgroundColor
        tintColor = theme.barTintColor
        nextButton.tintColor = theme.barTintColor
        previousButton.tintColor = theme.barTintColor
        counterLabel.textColor = theme.barTintColor
        searchBackground.backgroundColor = theme.searchBarBackgroundColor
        inputText.textColor = theme.searchBarTextColor
        inputText.tintColor = UIColor(designSystemColor: .accentPrimary)
        inputText.keyboardAppearance = theme.keyboardAppearance
        searchLoupe.tintColor = theme.barTintColor.withAlphaComponent(0.5)
        doneButton.setTitleColor(theme.barTintColor, for: .normal)
        activityView.style = theme.activityStyle
    }
}

extension FindInPageView: NibLoading {
    static func loadFromXib() -> FindInPageView {
        return FindInPageView.load(nibName: "FindInPage")
    }
}
