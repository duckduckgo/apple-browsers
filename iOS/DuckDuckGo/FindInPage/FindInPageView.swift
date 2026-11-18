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

    weak var delegate: FindInPageViewDelegate?
    weak var findInPage: (any FindInPageSearching)?
    private var usesFloatingUI = false
    private var clearButton: UIButton?
    private var diagnosticLabel: UILabel?

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
        inputText.accessibilityIdentifier = "FindInPage.Query"
        (inputText as? FindInPageTextField)?.findControls = self
        counterLabel.accessibilityIdentifier = "FindInPage.ResultCount"

        decorate()
    }

    @available(iOS 26.0, *)
    func applyFloatingUI() {
        usesFloatingUI = true
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
        NSLayoutConstraint.deactivate(searchBackground.constraints.filter {
            $0.firstItem === counterLabel && $0.firstAttribute == .leading
                || $0.firstItem === searchBackground && $0.firstAttribute == .trailing && $0.secondItem === counterLabel
        })

        let clearButton = UIButton(type: .system)
        clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearButton.tintColor = .tertiaryLabel
        clearButton.accessibilityLabel = NSLocalizedString("findInPage.clear", value: "Clear search", comment: "Clear Find in Page query")
        clearButton.accessibilityIdentifier = "FindInPage.Clear"
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.addTarget(self, action: #selector(clearSearch), for: .touchUpInside)
        searchBackground.addSubview(clearButton)
        self.clearButton = clearButton

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
        navigationGlass.contentView.addSubview(previousButton)
        navigationGlass.contentView.addSubview(nextButton)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 768),
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
            clearButton.trailingAnchor.constraint(equalTo: searchBackground.trailingAnchor, constant: -12),
            clearButton.centerYAnchor.constraint(equalTo: searchBackground.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 28),
            clearButton.heightAnchor.constraint(equalToConstant: 28),
            counterLabel.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8),
            inputText.trailingAnchor.constraint(equalTo: counterLabel.leadingAnchor, constant: -8)
        ])

        let containerWidth = container.widthAnchor.constraint(equalTo: widthAnchor, constant: -24)
        containerWidth.priority = .defaultHigh
        containerWidth.isActive = true

        tintColor = .label
        doneButton.tintColor = .white
        nextButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        nextButton.tintColor = .secondaryLabel
        previousButton.setImage(UIImage(systemName: "chevron.up"), for: .normal)
        previousButton.tintColor = .secondaryLabel
        counterLabel.textColor = .secondaryLabel
        searchBackground.backgroundColor = .clear
        inputText.textColor = .label
        inputText.clearButtonMode = .never
        searchLoupe.tintColor = .label
        clearButton.isHidden = inputText.text?.isEmpty ?? true
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !usesFloatingUI || container.frame.contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }
    
    override func resignFirstResponder() -> Bool {
        return inputText.resignFirstResponder()
    }
    
    func update(with findInPage: (any FindInPageSearching)?, updateTextField: Bool) {
        self.findInPage = findInPage
        isHidden = findInPage == nil
        if updateTextField {
            inputText?.text = findInPage?.searchTerm
        }
        counterLabel.isHidden = findInPage?.searchTerm.isEmpty != false
            || (findInPage?.isDelegateSessionExperiment != true && (findInPage?.total ?? 0) == 0)

        let current = findInPage?.current ?? 0
        let total = findInPage?.total ?? 0
        counterLabel.text = UserText.findInPageCount.format(arguments: current, total)
        clearButton?.isHidden = inputText.text?.isEmpty ?? true
        updateDiagnostics(findInPage?.diagnosticStatus)
    }

    private func updateDiagnostics(_ status: String?) {
        if status != nil, diagnosticLabel == nil {
            let label = UILabel()
            label.accessibilityIdentifier = "FindInPage.ExperimentStatus"
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .label
            label.backgroundColor = .secondarySystemBackground
            label.numberOfLines = 0
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.bottomAnchor.constraint(equalTo: container.topAnchor, constant: -6),
                label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                label.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor)
            ])
            diagnosticLabel = label
        }
        diagnosticLabel?.text = status
        diagnosticLabel?.isHidden = status == nil
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
        findInPage = nil
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
        clearButton?.isHidden = text.isEmpty
        
        _ = findInPage?.search(forText: text)
    }

    @objc private func clearSearch() {
        inputText.text = ""
        textChanged()
        inputText.becomeFirstResponder()
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
    }
}

extension FindInPageView: NibLoading {
    static func loadFromXib() -> FindInPageView {
        return FindInPageView.load(nibName: "FindInPage")
    }
}

final class FindInPageTextField: UITextField {
    weak var findControls: FindInPageView?

    override var keyCommands: [UIKeyCommand]? {
        guard findControls?.findInPage?.isDelegateSessionExperiment == true else { return super.keyCommands }
        let commands = [
            UIKeyCommand(input: "g", modifierFlags: .command, action: #selector(nextExperimentResult)),
            UIKeyCommand(input: "g", modifierFlags: [.command, .shift], action: #selector(previousExperimentResult)),
            UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(focusExperiment))
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return commands + (super.keyCommands ?? []).filter { candidate in
            !commands.contains { $0.input == candidate.input && $0.modifierFlags == candidate.modifierFlags }
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        if findControls?.findInPage?.isDelegateSessionExperiment == true,
           presses.contains(where: { $0.key?.keyCode == .keyboardEscape }) {
            findControls?.done()
            return
        }
        super.pressesBegan(presses, with: event)
    }

    @objc private func nextExperimentResult() { findControls?.next() }
    @objc private func previousExperimentResult() { findControls?.previous() }
    @objc private func focusExperiment() { becomeFirstResponder() }
}
