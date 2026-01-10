//
//  HistoryBurning.swift
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

import History

protocol HistoryBurning {
    func burn(_ visits: [Visit], and burnChats: Bool, animated: Bool) async
    func burnAll() async
    func burnChats() async
}

struct FireHistoryBurner: HistoryBurning {
    let fireproofDomains: DomainFireproofStatusProviding
    let fire: () async -> FireProtocol
    /// Records that AI chat history was cleared specifically for Sync (server-side delete timestamping).
    let recordAIChatHistoryClearForSync: (() -> Void)?

    /**
     * The arguments here are async closures because FireHistoryBurner is initialized
     * on a background thread, while both `FireproofDomains` and `FireCoordinator` need to be accessed on main thread.
     */
    init(
        fireproofDomains: DomainFireproofStatusProviding,
        fire: @escaping () async -> FireProtocol,
        recordAIChatHistoryClearForSync: (() -> Void)? = nil
    ) {
        self.fireproofDomains = fireproofDomains
        self.fire = fire
        self.recordAIChatHistoryClearForSync = recordAIChatHistoryClearForSync
    }

    func burn(_ visits: [Visit], and burnChats: Bool, animated: Bool) async {
        guard !visits.isEmpty else {
            return
        }

        if burnChats {
            recordAIChatHistoryClearForSync?()
        }

        await withCheckedContinuation { continuation in
            Task { @MainActor in
                await fire().burnVisits(visits,
                                        except: fireproofDomains,
                                        isToday: animated,
                                        closeWindows: false,
                                        clearSiteData: true,
                                        clearChatHistory: burnChats,
                                        urlToOpenIfWindowsAreClosed: .history) {
                    continuation.resume()
                }
            }
        }
    }

    func burnAll() async {
        recordAIChatHistoryClearForSync?()
        await fire().burnAll(opening: .history)
    }

    func burnChats() async {
        recordAIChatHistoryClearForSync?()
        await fire().burnChatHistory()
    }
}
