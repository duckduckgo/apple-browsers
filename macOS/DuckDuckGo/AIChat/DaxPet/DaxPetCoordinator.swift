//
//  DaxPetCoordinator.swift
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
import ConcurrencyExtensions
import SwiftUI

/// Puts Dax on the desktop while the setting is on, and keeps him standing where he was left.
@MainActor
final class DaxPetCoordinator: NSObject {

    private let preferences: DaxPetPreferences
    private var persistor: DaxPetPreferencesPersistor
    private let submitter: DaxPetPromptSubmitting

    private var window: DaxPetWindow?
    private var model: DaxPetViewModel?
    private var enabledCancellable: AnyCancellable?
    private var pointerTimer: Timer?
    private var isPointerOverCharacter = false
    private let notificationCenter: NotificationCenter
    private let isBrowserActive: () -> Bool
    private var responseStateCancellable: AnyCancellable?
    private var answers = DaxAnswerTracker()

    init(preferences: DaxPetPreferences,
         persistor: DaxPetPreferencesPersistor,
         submitter: DaxPetPromptSubmitting,
         notificationCenter: NotificationCenter = .default,
         isBrowserActive: @escaping () -> Bool = { NSApp.isActive }) {
        self.preferences = preferences
        self.persistor = persistor
        self.submitter = submitter
        self.notificationCenter = notificationCenter
        self.isBrowserActive = isBrowserActive
    }

    func start() {
        enabledCancellable = preferences.isEffectivelyEnabledPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                if isEnabled {
                    self?.show()
                } else {
                    self?.dismiss()
                }
            }
    }

    private func show() {
        guard window == nil else { return }

        let model = DaxPetViewModel(submitter: submitter)
        let window = DaxPetWindow(contentRect: NSRect(origin: .zero, size: DaxPetView.Metrics.windowSize))
        window.contentView = NSHostingView(rootView: DaxPetView(model: model))
        window.delegate = self
        window.onCancel = { [weak model] in model?.endComposing() }

        model.onHide = { [weak self] in self?.preferences.isEnabled = false }
        model.onNeedsKeyboard = { [weak window] in window?.makeKey() }
        model.caretLocation = { [weak window] promptWidth in
            guard let frame = window?.frame else { return nil }
            let fieldWidth = DaxPetView.Metrics.composingWidth
            let fieldMinX = frame.midX - fieldWidth / 2
            let fieldMidY = frame.minY + DaxPetView.Metrics.padding + DaxPetView.Metrics.controlsHeight / 2
            return NSPoint(x: fieldMinX + DaxPetView.Metrics.promptLeadingInset + min(promptWidth, fieldWidth - 60), y: fieldMidY)
        }
        model.character.onClick = { [weak model] in model?.characterClicked() }
        model.character.onRightClick = { [weak self] event in self?.showMenu(for: event) }
        model.character.onDrop = { [weak model] pasteboard in
            let items = DaxPetDroppedItem.items(from: pasteboard)
            Task { await model?.receive(items) }
        }
        model.character.onDragEnded = { [weak self] in
            self?.keepOnScreen()
            self?.savePosition()
        }

        self.window = window
        self.model = model
        observeAnswers()

        let position = initialPosition()
        window.setFrameOrigin(NSPoint(x: (position.x - DaxPetView.Metrics.windowSize.width / 2).rounded(), y: position.y))
        window.orderFrontRegardless()
        startTrackingPointer()
        model.sayHello()
    }

    private func dismiss() {
        responseStateCancellable = nil
        answers = DaxAnswerTracker()
        model?.endComposing()
        window?.orderOut(nil)
        window?.close()
        window = nil
        model = nil
        pointerTimer?.invalidate()
        pointerTimer = nil
    }

    // MARK: - Quick actions

    private func showMenu(for event: NSEvent) {
        guard let model, let view = window?.contentView else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let summarize = NSMenuItem(title: UserText.daxPetMenuSummarize, action: #selector(summarizePage), keyEquivalent: "")
        summarize.isEnabled = model.canSummarizeCurrentPage
        menu.addItem(summarize)
        menu.addItem(NSMenuItem(title: UserText.daxPetMenuContinueChat, action: #selector(continueLastChat), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: UserText.daxPetOpenDuckAI, action: #selector(openDuckAI), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: UserText.daxPetHide, action: #selector(hide), keyEquivalent: ""))
        menu.items.forEach { $0.target = self }

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func summarizePage() {
        Task { await model?.summarizePage() }
    }

    @objc private func continueLastChat() {
        Task { await model?.continueLastChat() }
    }

    @objc private func openDuckAI() {
        model?.openDuckAI()
    }

    @objc private func hide() {
        model?.hide()
    }

    // MARK: - Duck.ai answers

    private func observeAnswers() {
        responseStateCancellable = notificationCenter.publisher(for: .aiChatResponseStateChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let status = notification.userInfo?[AIChatNotificationUserInfoKey.responseStatus] as? AIChatStatusValue else { return }
                self?.responseStateChanged(to: status, on: notification.object as AnyObject?)
            }
    }

    private func responseStateChanged(to status: AIChatStatusValue, on page: AnyObject?) {
        switch answers.update(status, on: page) {
        case .started:
            model?.answerStarted()
        case .finished(let succeeded):
            model?.answerFinished(succeeded: succeeded, isBrowserActive: isBrowserActive())
        case nil:
            break
        }
    }

    /// The window is mostly empty space: it only takes clicks over Dax, his controls and his speech bubble.
    private func startTrackingPointer() {
        let timer = Timer(timeInterval: 1 / 20, repeats: true) { [weak self] _ in
            MainActor.assumeMainThread { self?.updatePointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
        updatePointer()
    }

    private func updatePointer() {
        guard let window, let model else { return }
        let mouse = NSEvent.mouseLocation
        let point = NSPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY)

        let isOverCharacter = DaxPetView.Metrics.characterFrame().contains(point)
        var interactiveFrames = [DaxPetView.Metrics.characterFrame(), DaxPetView.Metrics.controlsFrame(isComposing: model.isComposing)]
        if model.speech != nil {
            interactiveFrames.append(DaxPetView.Metrics.bubbleFrame())
        }
        // A press in progress (e.g. dragging Dax) keeps its window.
        let isInteractive = NSEvent.pressedMouseButtons != 0 && !window.ignoresMouseEvents
            || interactiveFrames.contains { $0.contains(point) }
        if window.ignoresMouseEvents == isInteractive {
            window.ignoresMouseEvents = !isInteractive
        }

        if isOverCharacter, !isPointerOverCharacter {
            model.characterHovered()
        }
        isPointerOverCharacter = isOverCharacter
    }

    /// Dropped hanging off a screen, he slides back onto it.
    private func keepOnScreen() {
        guard let window else { return }
        let origin = Self.origin(keepingCharacterOnScreenFor: window.frame.origin,
                                 visibleFrames: NSScreen.screens.map(\.visibleFrame))
        guard origin != window.frame.origin else { return }
        window.setFrame(NSRect(origin: origin, size: window.frame.size), display: true, animate: true)
    }

    /// Where the window must stand for Dax to be wholly on the screen he's mostly on.
    static func origin(keepingCharacterOnScreenFor origin: NSPoint, visibleFrames: [NSRect]) -> NSPoint {
        let character = DaxPetView.Metrics.characterFrame().offsetBy(dx: origin.x, dy: origin.y)
        func overlap(_ screen: NSRect) -> CGFloat {
            let intersection = screen.intersection(character)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        let screen = visibleFrames.max { overlap($0) < overlap($1) }
        guard let screen, !screen.contains(character) else { return origin }
        let dx = character.minX < screen.minX ? screen.minX - character.minX
            : character.maxX > screen.maxX ? screen.maxX - character.maxX : 0
        let dy = character.minY < screen.minY ? screen.minY - character.minY
            : character.maxY > screen.maxY ? screen.maxY - character.maxY : 0
        return NSPoint(x: origin.x + dx, y: origin.y + dy)
    }

    private func savePosition() {
        guard let frame = window?.frame else { return }
        persistor.position = CGPoint(x: frame.midX, y: frame.minY)
    }

    /// Where he was left, as long as that's still on a screen; otherwise the bottom-right corner.
    private func initialPosition() -> CGPoint {
        if let saved = persistor.position,
           NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -1, dy: -1).contains(saved) }) {
            return saved
        }
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return CGPoint(x: visibleFrame.maxX - 120, y: visibleFrame.minY + 24)
    }
}

extension DaxPetCoordinator: NSWindowDelegate {

    func windowDidResignKey(_ notification: Notification) {
        model?.keyboardFocusLost()
    }
}

/// Turns Duck.ai pages' response states into one answer at a time: started when the first page starts
/// answering, finished when the last one is done. A page reporting it's ready without having answered
/// (e.g. on load) is ignored.
struct DaxAnswerTracker {

    enum Event: Equatable {
        case started
        case finished(succeeded: Bool)
    }

    private var answeringPages = Set<ObjectIdentifier>()

    mutating func update(_ status: AIChatStatusValue, on page: AnyObject?) -> Event? {
        let id = page.map(ObjectIdentifier.init) ?? ObjectIdentifier(NSNull.self)
        switch status {
        case .startStreamNewPrompt, .startStreamRestartStream, .loading, .streaming:
            let wasIdle = answeringPages.isEmpty
            answeringPages.insert(id)
            return wasIdle ? .started : nil
        case .ready, .error, .blocked:
            guard answeringPages.remove(id) != nil, answeringPages.isEmpty else { return nil }
            return .finished(succeeded: status == .ready)
        case .unknown:
            return nil
        }
    }
}

/// Floats above everything, on every Space, without ever activating the browser by itself.
final class DaxPetWindow: NSPanel {

    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isExcludedFromWindowsMenu = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
final class DaxPetPromptSubmitter: DaxPetPromptSubmitting {

    private let aiChatTabOpener: AIChatTabOpening
    private let windowControllersManager: WindowControllersManagerProtocol
    private let makeSuggestionsReader: () -> AIChatSuggestionsReading
    private let capabilitiesProvider: DaxPetAttachmentCapabilitiesProviding
    private let promptHandler: AIChatPromptHandler

    init(aiChatTabOpener: AIChatTabOpening,
         windowControllersManager: WindowControllersManagerProtocol,
         makeSuggestionsReader: @escaping () -> AIChatSuggestionsReading,
         capabilitiesProvider: DaxPetAttachmentCapabilitiesProviding,
         promptHandler: AIChatPromptHandler = .shared) {
        self.aiChatTabOpener = aiChatTabOpener
        self.windowControllersManager = windowControllersManager
        self.makeSuggestionsReader = makeSuggestionsReader
        self.capabilitiesProvider = capabilitiesProvider
        self.promptHandler = promptHandler
    }

    func submit(prompt: String, payload: AIChatNativePrompt?) {
        aiChatTabOpener.openAIChatTab(with: .query(prompt, shouldAutoSubmit: true), behavior: .newTab(selected: true))
        // The opener seeds a plain query, so the attachments have to land after it.
        if let payload {
            promptHandler.setData(payload)
        }
        // Dax never activates the app, so handing off is what brings the browser forward.
        NSApp.activate(ignoringOtherApps: true)
    }

    func openDuckAI() {
        aiChatTabOpener.openNewAIChat(in: .newTab(selected: true))
        NSApp.activate(ignoringOtherApps: true)
    }

    func showBrowser() {
        NSApp.activate(ignoringOtherApps: true)
    }

    func attachmentCapabilities() async -> DaxPetAttachmentCapabilities {
        await capabilitiesProvider.capabilities()
    }

    /// The window the user was last in, and the page it shows when that's a web page.
    private var currentPage: (windowController: MainWindowController, tab: Tab)? {
        guard let windowController = windowControllersManager.lastKeyMainWindowController,
              let tab = windowController.mainViewController.tabCollectionViewModel.selectedTabViewModel?.tab,
              tab.content.urlForWebView?.isHttpOrHttps == true else { return nil }
        return (windowController, tab)
    }

    var canSummarizeCurrentPage: Bool { currentPage != nil }

    func summarizeCurrentPage() async -> Bool {
        guard let (windowController, tab) = currentPage else { return false }
        let pageContext = await AIChatUserScriptHandler.extractPageContext(from: tab)
        let prompt = AIChatNativePrompt.queryPrompt(UserText.daxPetSummarizePrompt,
                                                    autoSubmit: true,
                                                    pageContext: pageContext.map { .single($0) })
        windowController.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windowController.mainViewController.aiChatCoordinator.revealChat(for: prompt)
        return true
    }

    func continueLastChat() async -> Bool {
        let reader = makeSuggestionsReader()
        defer { reader.tearDown() }
        let (pinned, recent) = await reader.fetchSuggestions(query: nil, maxChats: 10)
        guard let chat = Self.mostRecent(pinned + recent) else { return false }
        aiChatTabOpener.openAIChatTab(with: .existingChat(chatId: chat.chatId), behavior: .newTab(selected: true))
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    /// The chat touched last, pinned or not; chats without a date count as oldest.
    static func mostRecent(_ chats: [AIChatSuggestion]) -> AIChatSuggestion? {
        chats.max { ($0.timestamp ?? .distantPast) < ($1.timestamp ?? .distantPast) }
    }
}
