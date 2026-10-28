//
//  MainMenuAIChatTests.swift
//  DuckDuckGoTests
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
import Combine
import Core
import FeatureFlags_iOS
import Testing
import UIKit
@_spi(Testing) import PixelKit
@_spi(Testing) import Persistence
@testable import DuckDuckGo

@MainActor
struct MainMenuAIChatTests {
    private let duckAI = UIMenu.Identifier("com.duckduckgo.duckai")

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func menuVisibilityAndStaticShortcuts(menuEnabled: Bool, aiEnabled: Bool) throws {
        let spec = MainMenuSpec(isEnabled: menuEnabled, context: .init(aiChatEnabled: aiEnabled))
        #expect(spec.menus.contains { $0.identifier == duckAI } == (menuEnabled && aiEnabled))
        guard menuEnabled && aiEnabled else { return }
        let menu = try #require(spec.menus.first { $0.identifier == duckAI })
        if case .insertBefore(let sibling) = menu.placement {
            #expect(sibling == UIMenu.Identifier("com.duckduckgo.bookmarks"))
        } else { Issue.record("Duck.ai must be inserted before Bookmarks") }
        #expect(menu.allItems.map(\.command) == [.openDuckAI, .newChat, .newVoiceChat, .newImageChat])
        #expect(menu.allItems.compactMap { $0.shortcut?.input } == ["n", "v", "g"])
        #expect(menu.allItems.compactMap { $0.shortcut?.modifiers } == Array(repeating: [.alternate, .command], count: 3))
        let legacy = UIKeyCommand(title: "", action: #selector(MainViewController.menuNewChat), input: "n", modifierFlags: [.alternate, .command])
        #expect(spec.remainingKeyCommands(from: [legacy]).isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func nativeHistoryLoadsLazilyAndCarriesModeAndCount() throws {
        let disabled = MainMenuSpec(isEnabled: true, context: .init(aiChatEnabled: true))
        let enabled = MainMenuSpec(isEnabled: true, context: .init(aiChatEnabled: true, nativeChatsAvailable: true))
        #expect(!disabled.menus.flatMap(\.submenus).contains { $0.loadsChats })
        #expect(enabled.menus.flatMap(\.submenus).contains { $0.loadsChats })
        let snapshot = MainMenuAIChats.Snapshot(recent: [.init(id: "chat-id", title: "A chat")], totalCount: 11)
        let menus = MainMenuSpec.chatHistoryMenus(snapshot: snapshot, aiChatURL: URL(string: "https://duck.ai")!, isFireMode: true)
        #expect(menus.first?.title == UserText.menuRecentChats)
        let items = menus.flatMap(\.allItems)
        #expect(items.map(\.command) == [.openRecentChat, .deleteAllChats])
        #expect(items.allSatisfy { $0.shortcut == nil })
        let recent = try #require(MainMenuBuilder().makeCommand(for: items[0]).propertyList as? [String: Any])
        #expect(recent["isFireMode"] as? Bool == true)
        #expect(recent["url"] as? String == URL(string: "https://duck.ai")!.withChatID("chat-id").absoluteString)
        let deletion = try #require(MainMenuBuilder().makeCommand(for: items[1]).propertyList as? [String: Any])
        #expect(deletion["chatCount"] as? Int == 11)
        #expect(deletion["isFireMode"] as? Bool == true)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func recentChatsAreNewestEightAndStoresRemainSeparate() async throws {
        let regular = OneShotMenuChatReader(chats: (0..<12).map { chat(String($0), date: String(format: "%02d", $0), pinned: $0 == 0) })
        let fire = OneShotMenuChatReader(chats: [chat("fire")])
        let provider = MainMenuAIChats(regularReader: regular, fireReader: fire)
        let regularSnapshot = try #require(await snapshot(provider, fire: false))
        #expect(regularSnapshot.recent.map(\.id) == (4...11).reversed().map(String.init))
        #expect(regularSnapshot.totalCount == 12)
        #expect(await snapshot(provider, fire: true)?.recent.map(\.id) == ["fire"])
        #expect(!MainMenuAIChats(regularReader: nil, fireReader: fire).isAvailable(isFireMode: false))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func everyOpeningReadsOneShotReaderAgainAndRecoversFromFailure() async throws {
        let reader = OneShotMenuChatReader(chats: [chat("before")])
        let provider = MainMenuAIChats(regularReader: nil, fireReader: reader)
        #expect(await snapshot(provider, fire: true)?.recent.map(\.id) == ["before"])
        reader.result = .success([chat("after-store-rotation")])
        #expect(await snapshot(provider, fire: true)?.recent.map(\.id) == ["after-store-rotation"])
        reader.result = .failure(ChatHistoryError.storageUnavailable)
        #expect(await snapshot(provider, fire: true) == nil)
        reader.result = .success([chat("recovered")])
        #expect(await snapshot(provider, fire: true)?.recent.map(\.id) == ["recovered"])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func confirmedDeletionPreservesModeCountSyncAndPixels(isFireMode: Bool, fails: Bool) async throws {
        let pixels = PixelKitMock()
        let provider = MainMenuAIChats(regularReader: nil, fireReader: nil,
                                       instrumentation: DefaultAIChatHistoryInstrumentation(pixelFiring: pixels))
        let executor = MenuChatFireExecutor()
        executor.fails = fails
        var refreshCount = 0
        let deletion = try #require(provider.deletion(snapshot: .init(recent: [], totalCount: 42), isFireMode: isFireMode, executor: executor,
                                                      onDeleted: { refreshCount += 1 }))
        #expect(deletion.count == 42)
        #expect(deletion.isFireMode == isFireMode)
        #expect(executor.burnedModes.isEmpty)
        #expect(executor.syncCount == 0)
        #expect(refreshCount == 0)
        #expect(pixels.actualFireCalls.map { $0.pixel.name } == [Pixel.Event.aiChatHistoryFireAllTapped.name])
        await deletion.confirm()
        #expect(executor.burnedModes == [isFireMode])
        #expect(executor.syncCount == (!isFireMode && !fails ? 1 : 0))
        #expect(refreshCount == (fails ? 0 : 1))
        #expect(pixels.actualFireCalls.map { $0.pixel.name } == [Pixel.Event.aiChatHistoryFireAllTapped.name, Pixel.Event.aiChatHistoryFireAllConfirmed.name])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func cancellingNativeConfirmationNeverBurnsOrSyncs() throws {
        let executor = MenuChatFireExecutor()
        let pixels = PixelKitMock()
        let provider = MainMenuAIChats(regularReader: nil, fireReader: nil,
                                       instrumentation: DefaultAIChatHistoryInstrumentation(pixelFiring: pixels))
        let deletion = try #require(provider.deletion(snapshot: .init(recent: [], totalCount: 3), isFireMode: true, executor: executor))
        let confirmation = ScopedFireConfirmationViewModel(
            tabViewModel: nil, source: .browsing,
            fireContext: .deleteChats(count: deletion.count, onDelete: { Task { await deletion.confirm() } }),
            downloadManager: SpyDownloadManager(), keyValueStore: InMemoryKeyValueStore(), appSettings: AppSettingsMock(),
            dataClearingCapability: MockDataClearingCapability(), browsingMode: .fire, onConfirm: { _ in }, onCancel: {})
        confirmation.buttons[1].action()
        #expect(executor.burnedModes.isEmpty)
        #expect(executor.syncCount == 0)
        #expect(pixels.actualFireCalls.count == 1)
        #expect(provider.deletion(snapshot: .init(recent: [], totalCount: 0), isFireMode: false, executor: executor) == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true], [false, true])
    func voiceUsesNewTabOnIPadContentAndKeepsPhoneBehavior(hasContent: Bool, isPad: Bool) {
        for unifiedInput in [false, true] {
            for deepLink in [false, true] {
                let decision = AIBoundaryNavigationDecision.forVoiceChat(currentHasContent: hasContent, isPad: isPad,
                                                                         unifiedToggleInputAvailable: unifiedInput, fromDeepLink: deepLink)
                #expect(decision == (hasContent && (isPad || unifiedInput || deepLink) ? .openInNewTab : .loadInPlace))
            }
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func menuEntrySourcesUseExistingEntryPixel() {
        let pixels = PixelKitMock()
        let sources: [AIChatEntryPointSource] = [.menuBarOpen, .menuBarNewChat, .menuBarVoiceChat, .menuBarImageChat, .menuBarRecentChat]
        for source in sources {
            AIChatEntryPointPixel.fire(source: source, duckAIEnabled: true, toggleEnabled: false, opensNewTab: true,
                                      hasPrompt: false, pixelFiring: pixels)
        }
        #expect(pixels.actualFireCalls.map { $0.additionalParameters?["source"] } == sources.map(\.rawValue))
        #expect(pixels.actualFireCalls.allSatisfy { $0.pixel.name == "aichat_entry_point" && $0.frequency == .dailyAndCount })
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func settingsRemoteFlagsTabsAndChatsRebuildMenuAtRuntime() async {
        let flagger = MockFeatureFlagger()
        flagger.enabledFeatureFlags = [.ipadMenuBar]
        let notifications = NotificationCenter()
        let chats = PassthroughSubject<Void, Never>()
        let (rebuilds, continuation) = AsyncStream<Void>.makeStream()
        var iterator = rebuilds.makeAsyncIterator()
        var aiEnabled = true
        let controller = MainMenuController(featureFlagger: flagger, idiom: .pad, contextProvider: {
            .init(aiChatEnabled: aiEnabled, nativeChatsAvailable: flagger.isFeatureOn(.aiChatNativeStorage))
        }, notificationCenter: notifications, aiChatUpdates: chats.eraseToAnyPublisher(), rebuildDelay: .milliseconds(1)) {
            continuation.yield(())
        }
        aiEnabled = false
        notifications.post(name: .aiChatSettingsChanged, object: nil)
        _ = await iterator.next()
        #expect(!controller.spec.menus.contains { $0.identifier == duckAI })
        aiEnabled = true
        notifications.post(name: .aiChatSettingsChanged, object: nil)
        _ = await iterator.next()
        #expect(controller.spec.menus.contains { $0.identifier == duckAI })
        for nativeEnabled in [true, false] {
            flagger.enabledFeatureFlags = nativeEnabled ? [.ipadMenuBar, .aiChatNativeStorage] : [.ipadMenuBar]
            flagger.triggerUpdate()
            _ = await iterator.next()
            #expect(controller.spec.menus.flatMap(\.submenus).contains { $0.loadsChats } == nativeEnabled)
        }
        notifications.post(name: .mainMenuTabChanged, object: nil)
        _ = await iterator.next()
        chats.send()
        _ = await iterator.next()
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [MenuCommandAvailability.State.Presentation.browser, .bookmarks, .downloads, .settings, .tabSwitcher])
    func chatCommandsRespectEnabledSettingsAndNativeStorage(presentation: MenuCommandAvailability.State.Presentation) {
        var state = MenuCommandAvailability.State(shortcutsEnabled: true, presentation: presentation)
        let commands: [MainMenuCommand] = [.openDuckAI, .newChat, .newVoiceChat, .newImageChat, .openRecentChat, .deleteAllChats]
        #expect(commands.allSatisfy { !MenuCommandAvailability(state: state).isEnabled($0) })
        state.aiChatEnabled = true
        #expect(commands.prefix(4).allSatisfy { MenuCommandAvailability(state: state).isEnabled($0) })
        #expect(!MenuCommandAvailability(state: state).isEnabled(.deleteAllChats))
        state.nativeChatsAvailable = true
        #expect(commands.allSatisfy { MenuCommandAvailability(state: state).isEnabled($0) })
        state.canHideTabs = false
        if presentation == .tabSwitcher {
            #expect(commands.allSatisfy { !MenuCommandAvailability(state: state).isEnabled($0) })
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func historyPayloadUsesSelectedSwitcherModeAndRechecksAfterDismissal(isFireMode: Bool) throws {
        let menus = MainMenuSpec.chatHistoryMenus(snapshot: .init(recent: [.init(id: "id", title: "Chat")], totalCount: 2),
                                                  aiChatURL: URL(string: "https://duck.ai")!, isFireMode: isFireMode)
        for item in menus.flatMap(\.allItems) {
            let command = MainMenuBuilder().makeCommand(for: item)
            let payload = try #require(MainMenuAIChatPayload(propertyList: command.propertyList))
            #expect(payload.isEnabled(for: item.command, currentMode: .normal, switcherMode: .fire) == isFireMode)
            #expect(payload.isEnabled(for: item.command, currentMode: .normal, switcherMode: .normal) == !isFireMode)
            #expect(payload.isEnabled(for: item.command, currentMode: .fire, switcherMode: nil) == isFireMode)
            #expect(payload.isEnabled(for: item.command, currentMode: .normal, switcherMode: nil) == !isFireMode)
        }
        let empty = MainMenuAIChatPayload(isFireMode: isFireMode, chatCount: 0)
        #expect(!empty.isEnabled(for: .deleteAllChats, currentMode: isFireMode ? .fire : .normal, switcherMode: nil))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func recentChatMatchesChatIdentityWithinItsBrowsingMode(isFireMode: Bool) throws {
        let regular = TabsModel(desktop: false)
        let fire = TabsModel(desktop: false, mode: .fire)
        let url = URL(string: "https://duck.ai/?chatID=existing")!
        let regularTab = Tab(link: Link(title: "Regular", url: url), fireTab: false)
        let fireTab = Tab(link: Link(title: "Fire", url: url), fireTab: true)
        regular.insert(tab: regularTab, placement: .atEnd, selectNewTab: false)
        fire.insert(tab: fireTab, placement: .atEnd, selectNewTab: false)
        let tabs = isFireMode ? fire : regular
        let selected = try #require(tabs.firstAIChat(with: URL(string: "https://duckduckgo.com/?q=DuckDuckGo+AI+Chat&ia=chat&duckai=4&chatID=existing&native-input=true")!))
        #expect(selected === (isFireMode ? fireTab : regularTab))
        #expect(tabs.firstAIChat(with: URL(string: "https://duck.ai/?chatID=missing")!) == nil)
        #expect(tabs.firstAIChat(with: URL(string: "https://duck.ai/")!) == nil)
        #expect(tabs.firstAIChat(with: URL(string: "https://example.com/?chatID=existing")!) == nil)
        let unrelated = Tab(link: Link(title: "Website", url: URL(string: "https://example.com/?chatID=unrelated")!), fireTab: isFireMode)
        tabs.insert(tab: unrelated, placement: .atEnd, selectNewTab: false)
        #expect(tabs.firstAIChat(with: URL(string: "https://duck.ai/?chatID=unrelated")!) == nil)
    }

    private func snapshot(_ provider: MainMenuAIChats, fire: Bool) async -> MainMenuAIChats.Snapshot? {
        await withCheckedContinuation { continuation in
            provider.loadSnapshot(isFireMode: fire) { continuation.resume(returning: $0) }
        }
    }

    private func chat(_ id: String, date: String = "2026-01-01", pinned: Bool = false) -> DuckAiChat {
        DuckAiChat(chatId: id, title: id, model: "model", lastEdit: date, pinned: pinned)
    }
}

private final class OneShotMenuChatReader: ChatHistoryReading {
    var result: Result<[DuckAiChat], Error>
    init(chats: [DuckAiChat]) { result = .success(chats) }
    func chatsPublisher() -> AnyPublisher<[DuckAiChat], Error> {
        result.publisher.eraseToAnyPublisher()
    }
}

private final class MenuChatFireExecutor: FireExecuting {
    weak var delegate: FireExecutorDelegate?
    var burnInProgress = false
    var burnedModes: [Bool] = []
    var syncCount = 0
    var fails = false
    func prepare(for request: FireRequest) { }
    func burn(request: FireRequest, applicationState: DataStoreWarmup.ApplicationState) async { }
    func burnChat(chatID: String, isFireMode: Bool) async -> Result<Void, Error> { .success(()) }
    func burnChats(chatIDs: [String], isFireMode: Bool) async -> Result<Void, Error> { .success(()) }
    func burnAllChats(isFireMode: Bool) async -> Result<Void, Error> {
        burnedModes.append(isFireMode)
        return fails ? .failure(ChatHistoryError.storageUnavailable) : .success(())
    }
    func scheduleSync() { syncCount += 1 }
}
