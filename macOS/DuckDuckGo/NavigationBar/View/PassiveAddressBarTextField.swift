//
//  PassiveAddressBarTextField.swift
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

import AppKit
import Combine
import Common

final class PassiveAddressBarTextField: NSTextField {

    weak var tabCollectionViewModel: TabCollectionViewModel? {
        didSet {
            subscribeToSelectedTabViewModel()
        }
    }

    private(set) weak var tabViewModel: TabViewModel?
    private var selectedTabViewModelCancellable: AnyCancellable?
    private var valueCancellable: AnyCancellable?

    var theme: ThemeStyleProviding = NSApp.delegateTyped.themeManager.theme

    override var acceptsFirstResponder: Bool { false }

    // Keep arrow cursor (no I-beam)
    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isEditable = false
        isBordered = false
        drawsBackground = false
        focusRingType = .none
        usesSingleLineMode = true
        textColor = theme.colorsProvider.textPrimaryColor
    }

    private func subscribeToSelectedTabViewModel() {
        guard let tabCollectionViewModel else {
            setTabViewModel(nil)
            selectedTabViewModelCancellable = nil
            return
        }

        selectedTabViewModelCancellable = tabCollectionViewModel.$selectedTabViewModel
            .compactMap { $0 }
            .sink { [weak self] selectedTabViewModel in
                self?.setTabViewModel(selectedTabViewModel)
            }
    }

    private func setTabViewModel(_ tabViewModel: TabViewModel?) {
        self.tabViewModel = tabViewModel

        // Subscribe to the passive address bar attributed string from TabViewModel
        valueCancellable = tabViewModel?.$passiveAddressBarAttributedString
            .receive(on: DispatchQueue.main)
            .sink { [weak self] attributedString in
                self?.setAttributedStringValue(attributedString)
            }
    }

    private func setAttributedStringValue(_ attributedString: NSAttributedString?) {
        if let attributedString, attributedString.containsAttachments { // used to draw page icon (TabViewModel.updatePassiveAddressBarString)
            self.attributedStringValue = attributedString
        } else {
            self.stringValue = attributedString?.string ?? "" // allow truncation of regular (non-attributed) URLs
        }
    }

    override func cursorUpdate(with event: NSEvent) {
    }

}
// MARK: - NSTextViewDelegate
extension PassiveAddressBarTextField: NSTextViewDelegate {
    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        // Set up sharing menu if present
        if let sharingMenuItem = menu.item(with: Selector(("_performStandardShareMenuItem:"))) {
            sharingMenuItem.title = UserText.shareMenuItem
            sharingMenuItem.submenu = SharingMenu(title: UserText.shareMenuItem, location: .addressBarTextField, delegate: self)
        }
        // filter out menu items with action from `selectorsToRemove` or containing submenu items with action from the list
        menu.items = menu.items.filter { menuItem in
            menuItem.action.map { action in AddressBarTextField.selectorsToRemove.contains(action) } != true
            && AddressBarTextField.selectorsToRemove.isDisjoint(with: menuItem.submenu?.items.compactMap(\.action) ?? [])
        }

        menu.delegate = self
        return menu
    }
}
// MARK: - NSMenuDelegate
extension PassiveAddressBarTextField: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        // The menu is only shown in pop-up windows, 
        // so we need to make the Web View first responder back.
        // BrowserTabViewController adjusts the first responder when `nil` is passed.
        window?.makeFirstResponder(nil)
    }
}
// MARK: - SharingMenuDelegate
extension PassiveAddressBarTextField: SharingMenuDelegate {
    func sharingMenuRequestsSharingData() -> SharingMenu.SharingData? {
        guard let selectedTabViewModel = tabCollectionViewModel?.selectedTabViewModel,
              selectedTabViewModel.canReload,
              !selectedTabViewModel.isShowingErrorPage,
              let url = selectedTabViewModel.tab.content.userEditableUrl else { return nil }

        return (selectedTabViewModel.title, [url])
    }
}
// MARK: - PassiveAddressBarTextFieldCell
final class PassiveAddressBarTextFieldCell: NSTextFieldCell {
    lazy var customEditor = PassiveAddressBarTextFieldEditor()

    override var isSelectable: Bool {
        get {
            // allow context menu but don‘t show beam cursor in pop ups
            return super.isSelectable || NSApp.currentEvent?.isContextClick ?? false
        }
        set {
            super.isSelectable = newValue
        }
    }

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        return customEditor
    }
}
// MARK: - PassiveAddressBarTextFieldEditor
final class PassiveAddressBarTextFieldEditor: NSTextView {

    private var passiveAddressBar: PassiveAddressBarTextField? {
        guard let delegate else { return nil }
        guard let passiveAddressBar = delegate as? PassiveAddressBarTextField else {
            assertionFailure("PassiveAddressBarTextFieldEditor: unexpected kind of delegate")
            return nil
        }
        return passiveAddressBar
    }

    override var isSelectable: Bool {
        get {
            // allow context menu but don‘t show beam cursor in pop ups
            return passiveAddressBar?.isSelectable ?? false || NSApp.currentEvent?.isContextClick ?? false
        }
        set {
            super.isSelectable = newValue
        }
    }

    // MARK: - Copy/Paste

    override func copy(_ sender: Any?) {
        // Always copy the actual URL from the tab view model, regardless of selection or displayed text
        let url: URL? = passiveAddressBar?.tabViewModel?.tab.content.userEditableUrl
        let stringToCopy = url?.absoluteString ?? passiveAddressBar?.stringValue ?? ""

        guard !stringToCopy.isEmpty else {
            super.copy(sender)
            return
        }

        if let url {
            NSPasteboard.general.copy(url, withString: stringToCopy)
        } else {
            NSPasteboard.general.copy(stringToCopy)
        }
    }

}
