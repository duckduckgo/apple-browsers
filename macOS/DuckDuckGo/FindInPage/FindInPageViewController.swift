//
//  FindInPageViewController.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import Carbon.HIToolbox
import Combine

@objc protocol FindInPageDelegate: AnyObject {

    func findInPageNext(_ sender: Any)
    func findInPagePrevious(_ sender: Any)
    func findInPageDone(_ sender: Any)

}

final class FindInPageViewController: NSViewController {

    let themeManager: ThemeManaging = NSApp.delegateTyped.themeManager
    var themeUpdateCancellable: AnyCancellable?

    weak var delegate: FindInPageDelegate?

    @Published var model: FindInPageModel?

    private enum Constants {
        static let contentSize = CGSize(width: 400, height: 40)
        static let cornerRadius: CGFloat = 10
        static let buttonSize = CGSize(width: 32, height: 24)
        static let buttonCornerRadius: CGFloat = 4
        static let buttonSpacing: CGFloat = 4
        static let searchImageSize: CGFloat = 14
        static let focusRingHeight: CGFloat = 34
        static let focusRingInset: CGFloat = 12
        static let focusRingSpacing: CGFloat = 8
    }

    private(set) var backgroundView: ColorView!
    private(set) var closeButton: NSButton!
    private(set) var textField: NSTextField!
    private(set) var focusRingView: FocusRingView!
    private(set) var statusField: NSTextField!
    private(set) var nextButton: NSButton!
    private(set) var previousButton: NSButton!

    private var modelCancellables = Set<AnyCancellable>()
    private var cancellables = Set<AnyCancellable>()

    static func create() -> FindInPageViewController {
        FindInPageViewController()
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("\(type(of: self)): Bad initializer")
    }

    /// Image-only square button styled like the ones that used to live in FindInPage.storyboard.
    private func makeImageButton(image: NSImage, target: AnyObject?, action: Selector) -> MouseOverButton {
        let button = MouseOverButton(frame: .zero)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setButtonType(.momentaryPushIn)
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.image = image
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.alignment = .center
        button.contentTintColor = .button
        // `awakeFromNib` captures this for the nib path; there is no nib here.
        button.normalTintColor = button.contentTintColor
        button.mouseOverColor = .buttonMouseOver
        button.mouseDownColor = .buttonMouseDown
        button.cornerRadius = Constants.buttonCornerRadius
        button.target = target
        button.action = action
        return button
    }

    override func loadView() {
        let backgroundView = ColorView(frame: NSRect(origin: .zero, size: Constants.contentSize),
                                       cornerRadius: Constants.cornerRadius)
        self.backgroundView = backgroundView

        // `findInPageNext:`/`findInPagePrevious:` were wired to the First Responder in the storyboard,
        // so they travel the responder chain rather than targeting this controller directly.
        closeButton = makeImageButton(image: .closeLarge, target: self, action: #selector(findInPageDone))
        previousButton = makeImageButton(image: .findPrevious, target: nil, action: #selector(findInPagePrevious))
        previousButton.tag = 1
        nextButton = makeImageButton(image: .findNext, target: nil, action: #selector(findInPageNext))
        nextButton.tag = 2

        focusRingView = FocusRingView(frame: .zero)
        focusRingView.translatesAutoresizingMaskIntoConstraints = false

        let searchImageButton = NSButton(frame: .zero)
        searchImageButton.translatesAutoresizingMaskIntoConstraints = false
        searchImageButton.setButtonType(.momentaryPushIn)
        searchImageButton.isBordered = false
        searchImageButton.bezelStyle = .shadowlessSquare
        searchImageButton.image = .findSearch
        searchImageButton.imagePosition = .imageOnly
        searchImageButton.imageScaling = .scaleProportionallyUpOrDown
        searchImageButton.alignment = .center
        searchImageButton.contentTintColor = .button

        textField = NSTextField(frame: .zero)
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.isBordered = false
        textField.focusRingType = .none
        textField.lineBreakMode = .byClipping
        textField.font = .systemFont(ofSize: NSFont.systemFontSize)
        textField.textColor = .controlTextColor
        textField.drawsBackground = true
        textField.backgroundColor = .clear
        textField.cell?.sendsActionOnEndEditing = true
        (textField.cell as? NSTextFieldCell)?.isScrollable = true
        textField.setContentHuggingPriority(.init(750), for: .vertical)

        statusField = NSTextField(labelWithString: "")
        statusField.translatesAutoresizingMaskIntoConstraints = false
        statusField.font = .systemFont(ofSize: NSFont.systemFontSize)
        statusField.lineBreakMode = .byClipping
        statusField.setContentHuggingPriority(.init(251), for: .horizontal)
        statusField.setContentHuggingPriority(.init(750), for: .vertical)

        focusRingView.addSubview(searchImageButton)
        focusRingView.addSubview(textField)
        focusRingView.addSubview(statusField)

        backgroundView.addSubview(closeButton)
        backgroundView.addSubview(focusRingView)
        backgroundView.addSubview(previousButton)
        backgroundView.addSubview(nextButton)

        NSLayoutConstraint.activate([
            closeButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize.width),
            closeButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize.height),
            closeButton.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: Constants.buttonSpacing),
            closeButton.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),

            focusRingView.heightAnchor.constraint(equalToConstant: Constants.focusRingHeight),
            focusRingView.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: Constants.buttonSpacing),
            focusRingView.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),

            searchImageButton.widthAnchor.constraint(equalToConstant: Constants.searchImageSize),
            searchImageButton.heightAnchor.constraint(equalToConstant: Constants.searchImageSize),
            searchImageButton.leadingAnchor.constraint(equalTo: focusRingView.leadingAnchor, constant: Constants.focusRingInset),
            searchImageButton.centerYAnchor.constraint(equalTo: focusRingView.centerYAnchor),

            textField.leadingAnchor.constraint(equalTo: searchImageButton.trailingAnchor, constant: Constants.focusRingSpacing),
            textField.centerYAnchor.constraint(equalTo: focusRingView.centerYAnchor),

            statusField.leadingAnchor.constraint(equalTo: textField.trailingAnchor, constant: Constants.focusRingSpacing),
            focusRingView.trailingAnchor.constraint(equalTo: statusField.trailingAnchor, constant: Constants.focusRingInset),
            statusField.centerYAnchor.constraint(equalTo: focusRingView.centerYAnchor),

            previousButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize.width),
            previousButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize.height),
            previousButton.leadingAnchor.constraint(equalTo: focusRingView.trailingAnchor, constant: Constants.buttonSpacing),
            previousButton.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),

            nextButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize.width),
            nextButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize.height),
            nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: Constants.buttonSpacing),
            backgroundView.trailingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: Constants.buttonSpacing),
            nextButton.centerYAnchor.constraint(equalTo: backgroundView.centerYAnchor),
        ])

        self.view = backgroundView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        textField.placeholderString = UserText.findInPageTextFieldPlaceholder
        textField.delegate = self

        closeButton.toolTip = UserText.findInPageCloseTooltip
        nextButton.toolTip = UserText.findInPageNextTooltip
        previousButton.toolTip = UserText.findInPagePreviousTooltip

        nextButton.setAccessibilityIdentifier("FindInPageController.nextButton")
        closeButton.setAccessibilityIdentifier("FindInPageController.closeButton")
        previousButton.setAccessibilityIdentifier("FindInPageController.previousButton")
        textField.setAccessibilityIdentifier("FindInPageController.textField")
        textField.setAccessibilityRole(.textField)
        statusField.setAccessibilityIdentifier("FindInPageController.statusField")
        statusField.setAccessibilityRole(.textField)

        subscribeToThemeChanges()
        applyThemeStyle()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        subscribeToModel()
        subscribeToFirstResponder()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        modelCancellables.removeAll()
        cancellables.removeAll()
    }

    @objc func findInPageNext(_ sender: Any?) {
        delegate?.findInPageNext(self)
    }

    @objc func findInPagePrevious(_ sender: Any?) {
        delegate?.findInPagePrevious(self)
    }

    @objc func findInPageDone(_ sender: Any?) {
        delegate?.findInPageDone(self)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Handle pressing enter here rather than didEndEditing otherwise it moving to the next match doesn't work.
        guard NSApp.isReturnOrEnterPressed,
           var modifiers = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask)
        else {
            return false
        }
        modifiers.remove(.capsLock)
        switch modifiers {
        case .shift:
            delegate?.findInPagePrevious(self)
            return true
        case []:
            delegate?.findInPageNext(self)
            return true
        default:
            return false
        }
    }

    func makeMeFirstResponder() {
        if textField.isFirstResponder {
            // select all on Cmd+F while editing
            textField.currentEditor()?.selectAll(nil)
        } else {
            textField.makeMeFirstResponder()
        }
    }

    private func subscribeToModel() {
        $model.receive(on: DispatchQueue.main).sink { [weak self] model in
            self?.subscribeToModelChanges(model: model)
        }.store(in: &cancellables)
    }

    private func subscribeToModelChanges(model: FindInPageModel?) {
        modelCancellables.removeAll()

        guard let model else { return }
        updateFieldStates(model: model)

        model.$text.receive(on: DispatchQueue.main).sink { [weak self] text in
            self?.textField.stringValue = text
        }.store(in: &modelCancellables)

        model.$matchesFound.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.rebuildStatus()
            self?.updateFieldStates()
        }.store(in: &modelCancellables)

        model.$currentSelection.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.rebuildStatus()
        }.store(in: &modelCancellables)
    }

    private func rebuildStatus() {
        guard let model else { return }
        statusField.stringValue = {
            guard let matchesFound = model.matchesFound,
                  let currentSelection = model.currentSelection else { return "" }
            return String(format: UserText.findInPage, currentSelection, matchesFound)
        }()
    }

    private func updateView(firstResponder: Bool) {
        focusRingView.updateView(stroke: firstResponder)
    }

    private func updateFieldStates(model: FindInPageModel? = nil) {
        guard let model = model ?? self.model else { return }

        statusField.isHidden = model.text.isEmpty
        // enable next/prev buttons by default if current status is unknown (fallback to public find API)
        nextButton.isEnabled = model.matchesFound.map { $0 > 0 } ?? !model.text.isEmpty
        previousButton.isEnabled = model.matchesFound.map { $0 > 0 } ?? !model.text.isEmpty
    }

    private func subscribeToFirstResponder() {
        guard let window = view.window else {
            assertionFailure("FindInPageViewController.subscribeToFirstResponder: view.window is nil")
            return
        }

        NotificationCenter.default
            .publisher(for: MainWindow.firstResponderDidChangeNotification, object: window)
            .sink { [weak self] in
                self?.firstResponderDidChange($0)
            }
            .store(in: &cancellables)
    }

    private func firstResponderDidChange(_ notification: Notification) {
        if view.window?.firstResponder == textField.currentEditor() {
            updateView(firstResponder: true)
        } else {
            updateView(firstResponder: false)
        }
    }

}

extension FindInPageViewController: NSTextFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        model?.find(textField.stringValue)
    }

}

extension FindInPageViewController: ThemeUpdateListening {

    func applyThemeStyle(theme: ThemeStyleProviding) {
        backgroundView.backgroundColor = theme.palette.surfaceSecondary
        focusRingView.applyThemeStyle(theme: theme)
    }
}
