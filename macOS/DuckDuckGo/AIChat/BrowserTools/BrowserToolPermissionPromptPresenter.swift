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
import SwiftUI
import WebKit

/// Shows browser tool permission prompts from the window's Duck.ai button. A prompt belongs to its chat's
/// owner tab, which is selected when the prompt arrives; each window shows the oldest prompt for its
/// selected tab, and a prompt for another tab waits until that tab is selected again.
@MainActor
final class BrowserToolPermissionPromptPresenter {

    typealias Respond = @MainActor (ClientToolPermissionPrompt, ClientToolPermissionDecision, any ClientToolPermissionPrompting) -> Void

    private struct Request {
        let prompt: ClientToolPermissionPrompt
        let ownerTabID: TabIdentifier
        weak var collection: TabCollectionViewModel?
        weak var prompter: (any ClientToolPermissionPrompting)?
    }

    private struct Shown {
        let requestID: String
        let popover: NSPopover
        weak var tabBar: TabBarViewController?
        let keyMonitor: Any?
    }

    private let windowControllersManager: WindowControllersManagerProtocol
    private let respond: Respond
    private var requests: [Request] = []
    private var shown: [ObjectIdentifier: Shown] = [:]
    private var selectionChanges: [ObjectIdentifier: AnyCancellable] = [:]

    init(windowControllersManager: WindowControllersManagerProtocol, respond: @escaping Respond) {
        self.windowControllersManager = windowControllersManager
        self.respond = respond
    }

    /// False when the chat has no owner tab in a regular window, which cancels the call.
    func present(_ prompt: ClientToolPermissionPrompt, chatWebView: WKWebView?, prompter: any ClientToolPermissionPrompting) -> Bool {
        guard let ownerTabID = AIChatTabPickerSource.ownerTabID(for: chatWebView, in: windowControllersManager),
              let collection = AIChatTabPickerSource.collection(containingTabID: ownerTabID, in: windowControllersManager),
              !collection.isBurner,
              let windowController = windowController(for: collection) else { return false }

        requests.append(Request(prompt: prompt, ownerTabID: ownerTabID, collection: collection, prompter: prompter))
        observeSelection(of: collection)
        if collection.selectedTabViewModel?.tab.uuid != ownerTabID,
           let index = collection.indexInAllTabs(where: { $0.uuid == ownerTabID }) {
            collection.select(at: index)
        }
        windowController.window?.makeKeyAndOrderFront(nil)
        refresh()
        return true
    }

    func withdraw(requestID: String) {
        requests.removeAll { $0.prompt.requestID == requestID }
        refresh()
    }

    private func answer(_ requestID: String, with decision: ClientToolPermissionDecision) {
        guard let index = requests.firstIndex(where: { $0.prompt.requestID == requestID }) else { return }
        let request = requests.remove(at: index)
        refresh()
        guard let prompter = request.prompter else { return }
        respond(request.prompt, decision, prompter)
    }

    /// Shows, per window, the oldest prompt for its selected tab and closes any other.
    private func refresh() {
        requests.removeAll { $0.collection == nil || $0.prompter == nil }
        let collections = Dictionary(requests.compactMap { request in request.collection.map { (ObjectIdentifier($0), $0) } },
                                     uniquingKeysWith: { first, _ in first })

        for (key, current) in shown {
            let next = collections[key].flatMap(oldestRequest(selectedIn:))
            guard next?.prompt.requestID != current.requestID else { continue }
            shown[key] = nil
            current.popover.close()
            current.keyMonitor.map(NSEvent.removeMonitor)
            if next == nil { current.tabBar?.hideBrowserToolPermissionButton() }
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

    /// Slides in the window's tool permission button, beside the Duck.ai control, and opens the prompt from it.
    private func show(_ request: Request, in collection: TabCollectionViewModel, key: ObjectIdentifier) {
        guard let tabBar = windowController(for: collection)?.mainViewController.tabBarViewController else { return }
        let prompt = request.prompt
        let popover = NSPopover()
        // Stays open until answered: clicking elsewhere must not settle the call.
        popover.behavior = .applicationDefined
        let content = NSHostingController(rootView: BrowserToolPermissionPromptView(prompt: prompt) { [weak self] decision in
            self?.answer(prompt.requestID, with: decision)
        })
        popover.contentViewController = content
        // Sized before showing: a popover resized afterwards keeps its bottom edge and drifts off its anchor.
        popover.contentSize = content.view.fittingSize
        let open: (NSView) -> Void = { [weak self, weak popover] anchor in
            guard let popover, !popover.isShown,
                  self?.shown.values.contains(where: { $0.requestID == prompt.requestID }) == true else { return }
            popover.show(positionedBelow: anchor.bounds.insetFromLineOfDeath(flipped: anchor.isFlipped), in: anchor)
        }
        // Recorded first: the button may already be in place and open the prompt right away.
        shown[key] = Shown(requestID: prompt.requestID, popover: popover, tabBar: tabBar,
                           keyMonitor: keyMonitor(answering: prompt.requestID, popover: popover, in: tabBar.view.window))
        tabBar.showBrowserToolPermissionButton(icon: BrowserToolPermissionPromptText.icon(toolName: prompt.toolName),
                                               title: BrowserToolPermissionPromptText.title(toolName: prompt.toolName,
                                                                                            targetsOtherTab: prompt.targetsOtherTab),
                                               action: { [weak self] _ in self?.answer(prompt.requestID, with: .dismiss) },
                                               shown: open)
    }

    /// Esc answers "not this time" and ⌘↵ allows once, while the prompt shows in `window`. The popover
    /// itself doesn't take key focus, so SwiftUI keyboard shortcuts don't reach it.
    private func keyMonitor(answering requestID: String, popover: NSPopover, in window: NSWindow?) -> Any? {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak popover, weak window] event in
            guard let self, let popover, popover.isShown,
                  event.window === window || event.window === popover.contentViewController?.view.window else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            switch (event.keyCode, modifiers) {
            case (53, []): // Esc
                answer(requestID, with: .dismiss)
            case (36, .command), (76, .command): // ⌘Return, ⌘Enter
                answer(requestID, with: .allowOnce)
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
