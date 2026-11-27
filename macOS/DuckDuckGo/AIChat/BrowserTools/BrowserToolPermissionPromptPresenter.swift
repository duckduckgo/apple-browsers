//
//  BrowserToolPermissionPromptPresenter.swift
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

import AIChat
import AppKit
import Combine
import DesignResourcesKitIcons
import SwiftUI
import WebKit

@MainActor
final class BrowserToolPermissionPromptPresenter {

    typealias Respond = @MainActor (ClientToolPermissionPrompt, ClientToolPermissionDecision, any ClientToolPermissionPrompting) -> Void

    private struct Request {
        enum Kind {
            case toolPrompt(ToolPrompt)
            case translateOffer(languageCode: String, choice: TranslateOfferChoice)
        }

        struct ToolPrompt {
            let prompt: ClientToolPermissionPrompt
            weak var prompter: (any ClientToolPermissionPrompting)?
            // Kept for the prompt's life, so tools taken out stay out when its popover is rebuilt.
            let selection: BrowserToolAccessSelection
        }

        let id: String
        let ownerTabID: TabIdentifier
        weak var collection: TabCollectionViewModel?
        let kind: Kind

        @MainActor var isLive: Bool {
            guard let collection else { return false }
            switch kind {
            case .toolPrompt(let tool): return tool.prompter != nil
            case .translateOffer: return collection.indexInAllTabs(where: { $0.uuid == ownerTabID }) != nil
            }
        }

        var translateOfferLanguageCode: String? {
            guard case .translateOffer(let languageCode, _) = kind else { return nil }
            return languageCode
        }

        var translateOfferChoice: TranslateOfferChoice? {
            guard case .translateOffer(_, let choice) = kind else { return nil }
            return choice
        }
    }

    private struct Shown {
        let requestID: String
        let popover: NSPopover
        weak var tabBar: TabBarViewController?
        let keyMonitor: Any?
    }

    private struct Use {
        let key: ObjectIdentifier
        weak var tabBar: TabBarViewController?
        let toolName: String
    }

    private let windowControllersManager: WindowControllersManagerProtocol
    private let respond: Respond
    private var requests: [Request] = []
    private var shown: [ObjectIdentifier: Shown] = [:]
    private var uses: [String: Use] = [:]
    private var selectionChanges: [ObjectIdentifier: AnyCancellable] = [:]
    private var translateOfferDismissedTabIDs: Set<TabIdentifier> = []
    private let translatePages: TranslatePagesSetting
    private var translatePagesChanges: AnyCancellable?

    init(windowControllersManager: WindowControllersManagerProtocol,
         translatePages: TranslatePagesSetting = TranslatePagesSetting(),
         respond: @escaping Respond) {
        self.windowControllersManager = windowControllersManager
        self.translatePages = translatePages
        self.respond = respond
        translatePagesChanges = translatePages.changes.sink { [weak self] in self?.refresh() }
    }

    func present(_ prompt: ClientToolPermissionPrompt, chatWebView: WKWebView?, prompter: any ClientToolPermissionPrompting) -> Bool {
        guard let ownerTabID = AIChatTabPickerSource.ownerTabID(for: chatWebView, in: windowControllersManager),
              let collection = AIChatTabPickerSource.ownerCollection(for: chatWebView, ownerTabID: ownerTabID, in: windowControllersManager),
              !collection.isBurner,
              let windowController = windowController(for: collection) else { return false }

        requests.append(Request(id: prompt.requestID, ownerTabID: ownerTabID, collection: collection,
                                kind: .toolPrompt(.init(prompt: prompt, prompter: prompter, selection: BrowserToolAccessSelection()))))
        observeSelection(of: collection)
        if collection.selectedTabViewModel?.tab.uuid != ownerTabID,
           let index = collection.indexInAllTabs(where: { $0.uuid == ownerTabID }) {
            collection.select(at: index)
        }
        windowController.window?.makeKeyAndOrderFront(nil)
        refresh()
        return true
    }

    func startUse(requestID: String, toolName: String, chatWebView: WKWebView?) {
        guard let ownerTabID = AIChatTabPickerSource.ownerTabID(for: chatWebView, in: windowControllersManager),
              let collection = AIChatTabPickerSource.ownerCollection(for: chatWebView, ownerTabID: ownerTabID, in: windowControllersManager),
              !collection.isBurner,
              let tabBar = windowController(for: collection)?.mainViewController.tabBarViewController else { return }
        let key = ObjectIdentifier(collection)
        uses[requestID] = Use(key: key, tabBar: tabBar, toolName: toolName)
        if shown[key] == nil { showUse(toolName: toolName, in: tabBar) }
    }

    func endUse(requestID: String, completed: Bool) {
        guard let use = uses.removeValue(forKey: requestID),
              shown[use.key] == nil, !uses.values.contains(where: { $0.key == use.key }) else { return }
        if completed {
            use.tabBar?.finishBrowserToolUse()
        } else {
            use.tabBar?.hideBrowserToolPermissionButton()
        }
    }

    private func showUse(toolName: String, in tabBar: TabBarViewController) {
        tabBar.showBrowserToolUse(icon: BrowserToolPermissionPromptText.icon(toolName: toolName), title: UserText.browserToolInUse)
    }

    func withdraw(requestID: String) {
        requests.removeAll { $0.id == requestID }
        refresh()
    }

    private func answer(_ requestID: String, with decision: ClientToolPermissionDecision) {
        guard let index = requests.firstIndex(where: { $0.id == requestID }) else { return }
        let request = requests.remove(at: index)
        // Before refresh, so an allowed call's use has started when its prompt closes.
        if case .toolPrompt(let tool) = request.kind, let prompter = tool.prompter {
            respond(tool.prompt, decision, prompter)
        }
        refresh()
    }

    // MARK: - Translate offer

    /// Offers to translate the page `tabID` just loaded in `window`, replacing its earlier offer; nil withdraws it.
    func offerTranslation(languageCode: String?, tabID: TabIdentifier, window: NSWindow? = nil) {
        guard translateOfferLanguageCode(for: tabID) != languageCode else { return }
        requests.removeAll { $0.ownerTabID == tabID && $0.translateOfferLanguageCode != nil }
        if let languageCode, !translateOfferDismissedTabIDs.contains(tabID),
           isAllowedByTranslatePages(languageCode),
           let collection = ownerCollection(ofTabID: tabID, shownIn: window),
           !collection.isBurner,
           windowController(for: collection)?.mainViewController.aiChatCoordinator.isSidebarOpen(for: tabID) != true {
            requests.append(Request(id: UUID().uuidString, ownerTabID: tabID, collection: collection,
                                    kind: .translateOffer(languageCode: languageCode, choice: TranslateOfferChoice())))
            observeSelection(of: collection)
        }
        refresh()
    }

    // A pinned tab is in every window's collection: its web view's window picks one, or, when it shows in none, the main window.
    private func ownerCollection(ofTabID tabID: TabIdentifier, shownIn window: NSWindow?) -> TabCollectionViewModel? {
        if let collection = (window?.windowController as? MainWindowController)?.mainViewController.tabCollectionViewModel
            ?? AIChatTabPickerSource.collection(containingTabID: tabID, in: windowControllersManager) {
            return collection
        }
        let owners = windowControllersManager.mainWindowControllers.filter {
            $0.mainViewController.tabCollectionViewModel.indexInAllTabs(where: { $0.uuid == tabID }) != nil
        }
        return (owners.first { $0.window?.isMainWindow == true } ?? owners.first)?.mainViewController.tabCollectionViewModel
    }

    private func isAllowedByTranslatePages(_ languageCode: String) -> Bool {
        translatePages.mode == .alwaysAsk && !translatePages.isExcluded(languageCode: languageCode)
    }

    /// The box's state lives with the offer, so a popover rebuilt on a tab switch keeps it.
    func translateOfferChoice(for tabID: TabIdentifier) -> TranslateOfferChoice? {
        requests.lazy.compactMap { $0.ownerTabID == tabID ? $0.translateOfferChoice : nil }.first
    }

    func translateOfferLanguageCode(for tabID: TabIdentifier) -> String? {
        requests.lazy.compactMap { $0.ownerTabID == tabID ? $0.translateOfferLanguageCode : nil }.first
    }

    /// Anything but Translate keeps the tab from offering again (R6).
    func answerTranslateOffer(for tabID: TabIdentifier, translate: Bool) {
        guard let index = requests.firstIndex(where: { $0.ownerTabID == tabID && $0.translateOfferLanguageCode != nil }) else { return }
        let request = requests.remove(at: index)
        if request.translateOfferChoice?.dontAskAgain == true, let languageCode = request.translateOfferLanguageCode {
            translatePages.exclude(languageCode: languageCode)
        }
        if translate {
            // The owner tab is the selected one while its offer shows.
            let translator = request.collection.flatMap(windowController(for:))?.mainViewController.aiChatTranslator
            Task { await translator?.translateCurrentPage() }
        } else {
            translateOfferDismissedTabIDs.insert(tabID)
        }
        refresh()
    }

    private var isRefreshing = false

    private func refresh() {
        // Showing an offer records its language, and that write notifies back here.
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        requests.removeAll { !$0.isLive || !($0.translateOfferLanguageCode.map(isAllowedByTranslatePages) ?? true) }
        let collections = Dictionary(requests.compactMap { request in request.collection.map { (ObjectIdentifier($0), $0) } },
                                     uniquingKeysWith: { first, _ in first })

        for (key, current) in shown {
            let next = collections[key].flatMap(oldestRequest(selectedIn:))
            guard next?.id != current.requestID else { continue }
            shown[key] = nil
            current.popover.close()
            current.keyMonitor.map(NSEvent.removeMonitor)
            guard next == nil, let tabBar = current.tabBar else { continue }
            if let use = uses.values.first(where: { $0.key == key }) {
                showUse(toolName: use.toolName, in: tabBar)
            } else {
                tabBar.hideBrowserToolPermissionButton()
            }
        }
        for (key, collection) in collections where shown[key] == nil {
            guard let request = oldestRequest(selectedIn: collection) else { continue }
            show(request, in: collection, key: key)
        }
        selectionChanges = selectionChanges.filter { collections[$0.key] != nil }
    }

    private func oldestRequest(selectedIn collection: TabCollectionViewModel) -> Request? {
        guard let selectedTabID = collection.selectedTabViewModel?.tab.uuid else { return nil }
        return requests.first { $0.collection === collection && $0.ownerTabID == selectedTabID }
    }

    private func show(_ request: Request, in collection: TabCollectionViewModel, key: ObjectIdentifier) {
        if let languageCode = request.translateOfferLanguageCode { translatePages.recordOffered(languageCode: languageCode) }
        guard let tabBar = windowController(for: collection)?.mainViewController.tabBarViewController else { return }
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        let content: NSViewController
        let icon: NSImage
        let title: String
        let dismiss: () -> Void
        let primary: () -> Void
        switch request.kind {
        case .toolPrompt(let tool):
            let prompt = tool.prompt
            let selection = tool.selection
            let hosting = NSHostingController(rootView: BrowserToolPermissionPromptView(prompt: prompt, selection: selection) { [weak self] decision in
                self?.answer(prompt.requestID, with: decision)
            })
            if #available(macOS 13.0, *), prompt.accessToolNames != nil {
                // Taking a tool out or undoing it changes the height.
                hosting.sizingOptions = .preferredContentSize
            }
            content = hosting
            // A waiting prompt shows the AI icon; only tools that run without asking show their own.
            icon = DesignSystemImages.Glyphs.Size16.aiGeneral
            title = BrowserToolPermissionPromptText.title(toolName: prompt.toolName, targetsOtherTab: prompt.targetsOtherTab)
            dismiss = { [weak self] in self?.answer(prompt.requestID, with: .dismiss) }
            primary = { [weak self] in
                let decision: ClientToolPermissionDecision
                if prompt.accessToolNames != nil {
                    decision = .allowAccess(excluding: Set(selection.removed))
                } else {
                    decision = prompt.offersAllowForChat ? .allowForChat : .allowOnce
                }
                self?.answer(prompt.requestID, with: decision)
            }
        case .translateOffer(let languageCode, let choice):
            let tabID = request.ownerTabID
            content = NSHostingController(rootView: TranslateOfferPromptView(
                pageLanguageName: TranslateOfferLanguage.name(of: languageCode) ?? languageCode,
                userLanguageName: TranslateOfferLanguage.name(of: Locale.preferredLanguages.first) ?? "",
                choice: choice
            ) { [weak self] translate in
                self?.answerTranslateOffer(for: tabID, translate: translate)
            })
            icon = DesignSystemImages.Glyphs.Size16.translate
            title = UserText.translateOfferTitle
            dismiss = { [weak self] in self?.answerTranslateOffer(for: tabID, translate: false) }
            primary = { [weak self] in self?.answerTranslateOffer(for: tabID, translate: true) }
        }
        popover.contentViewController = content
        // Resized after showing, a popover drifts off its anchor.
        popover.contentSize = content.view.fittingSize
        let requestID = request.id
        let open: (NSView) -> Void = { [weak self, weak popover] anchor in
            guard let popover, !popover.isShown,
                  self?.shown.values.contains(where: { $0.requestID == requestID }) == true else { return }
            popover.show(positionedBelow: anchor.bounds.insetFromLineOfDeath(flipped: anchor.isFlipped), in: anchor)
            // Key, so its shortcuts only answer it and never a key press meant for the page or address bar.
            popover.contentViewController?.view.window?.makeKey()
        }
        // Before the button: it may call `open` right away.
        shown[key] = Shown(requestID: requestID, popover: popover, tabBar: tabBar,
                           keyMonitor: keyMonitor(dismiss: dismiss, primary: primary, popover: popover, ownerWindow: tabBar.view.window,
                                                   answersPageKeys: request.translateOfferLanguageCode == nil))
        tabBar.showBrowserToolPermissionButton(icon: icon, title: title, action: { _ in dismiss() }, shown: open)
    }

    // The browser window takes focus back from the popover, so its key presses answer too,
    // unless a text field such as the address bar has focus. An unrequested offer also leaves keys typed in the page to it.
    private func keyMonitor(dismiss: @escaping () -> Void, primary: @escaping () -> Void, popover: NSPopover,
                            ownerWindow: NSWindow?, answersPageKeys: Bool) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak popover, weak ownerWindow] event in
            guard let popover, popover.isShown, let window = event.window else { return event }
            let inOwnerWindow = window === ownerWindow && !(window.firstResponder is NSText)
                && (answersPageKeys || !(window.firstResponder is WKWebView))
            guard window === popover.contentViewController?.view.window || inOwnerWindow else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            switch (event.keyCode, modifiers) {
            case (53, []): // Esc
                dismiss()
            case (36, .command), (76, .command): // ⌘Return, ⌘Enter
                primary()
            default:
                return event
            }
            return nil
        }
    }

    private func observeSelection(of collection: TabCollectionViewModel) {
        let key = ObjectIdentifier(collection)
        guard selectionChanges[key] == nil else { return }
        selectionChanges[key] = collection.$selectedTabViewModel
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
    }

    private func windowController(for collection: TabCollectionViewModel) -> MainWindowController? {
        windowControllersManager.mainWindowControllers.first { $0.mainViewController.tabCollectionViewModel === collection }
    }
}
