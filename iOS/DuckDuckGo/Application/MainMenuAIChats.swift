//
//  MainMenuAIChats.swift
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

import AIChat
import Combine
import Foundation

struct MainMenuAIChat: Equatable {
    let id: String
    let title: String
}

struct MainMenuAIChatPayload {
    let isFireMode: Bool
    var url: URL?
    var chatCount: Int?

    init(isFireMode: Bool, url: URL? = nil, chatCount: Int? = nil) {
        self.isFireMode = isFireMode
        self.url = url
        self.chatCount = chatCount
    }

    init?(propertyList: Any?) {
        guard let payload = propertyList as? [String: Any], let isFireMode = payload["isFireMode"] as? Bool else { return nil }
        self.init(isFireMode: isFireMode, url: (payload["url"] as? String).flatMap(URL.init(string:)), chatCount: payload["chatCount"] as? Int)
    }

    var propertyList: [String: Any] {
        var payload: [String: Any] = ["isFireMode": isFireMode]
        if let url { payload["url"] = url.absoluteString }
        if let chatCount { payload["chatCount"] = chatCount }
        return payload
    }

    func isEnabled(for command: MainMenuCommand, currentMode: BrowsingMode, switcherMode: BrowsingMode?) -> Bool {
        guard isFireMode == ((switcherMode ?? currentMode) == .fire) else { return false }
        switch command {
        case .openRecentChat: return url != nil
        case .deleteAllChats: return (chatCount ?? 0) > 0
        default: return false
        }
    }
}

@MainActor
final class MainMenuAIChats {
    struct Snapshot {
        let recent: [MainMenuAIChat]
        let totalCount: Int
    }

    struct Deletion {
        let count: Int
        let isFireMode: Bool
        let confirm: () async -> Void
    }

    private let regularReader: ChatHistoryReading?
    private let fireReader: ChatHistoryReading?
    private let instrumentation: AIChatHistoryInstrumentation
    private let updates = PassthroughSubject<Void, Never>()
    private var regularObservation: AnyCancellable?
    private var fireObservation: AnyCancellable?
    private var requests: [UUID: AnyCancellable] = [:]
    var updatesPublisher: AnyPublisher<Void, Never> {
        observe(isFireMode: false)
        observe(isFireMode: true)
        return updates.handleEvents(receiveCancel: { [weak self] in
            self?.regularObservation = nil
            self?.fireObservation = nil
        }).eraseToAnyPublisher()
    }

    init(regularReader: ChatHistoryReading?, fireReader: ChatHistoryReading?,
         instrumentation: AIChatHistoryInstrumentation = DefaultAIChatHistoryInstrumentation()) {
        self.regularReader = regularReader
        self.fireReader = fireReader
        self.instrumentation = instrumentation
    }

    func isAvailable(isFireMode: Bool) -> Bool {
        reader(isFireMode: isFireMode) != nil
    }

    private func reader(isFireMode: Bool) -> ChatHistoryReading? {
        isFireMode ? fireReader : regularReader
    }

    private func observe(isFireMode: Bool) {
        let observation = reader(isFireMode: isFireMode)?.chatsPublisher()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] _ in self?.updates.send() })
        if isFireMode { fireObservation = observation } else { regularObservation = observation }
    }

    /// Resubscribe on every menu opening. Fire storage can rotate, and fallback readers emit only once.
    func loadSnapshot(isFireMode: Bool, completion: @escaping (Snapshot?) -> Void) {
        guard let reader = reader(isFireMode: isFireMode) else { completion(nil); return }
        observe(isFireMode: isFireMode)
        let request = UUID()
        requests[request] = reader.chatsPublisher()
            .first()
            .map { chats -> Snapshot? in
                let recent = chats.sorted { $0.lastEdit > $1.lastEdit }.prefix(8)
                    .map { MainMenuAIChat(id: $0.chatId, title: $0.title) }
                return Snapshot(recent: recent, totalCount: chats.count)
            }
            .catch { [weak self] error -> Just<Snapshot?> in
                self?.instrumentation.loadFailed(error: error)
                return Just(nil)
            }
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { [weak self] _ in self?.requests[request] = nil }, receiveValue: completion)
    }

    func chatOpened() {
        instrumentation.chatOpened()
    }

    func deletion(snapshot: Snapshot, isFireMode: Bool, executor: FireExecuting,
                  onDeleted: @escaping () -> Void = {}) -> Deletion? {
        guard snapshot.totalCount > 0 else { return nil }
        instrumentation.fireAllTapped()
        return Deletion(count: snapshot.totalCount, isFireMode: isFireMode) { [self] in
            instrumentation.fireAllConfirmed()
            let result = await executor.burnAllChats(isFireMode: isFireMode)
            guard case .success = result else { return }
            if !isFireMode { executor.scheduleSync() }
            onDeleted()
        }
    }
}
