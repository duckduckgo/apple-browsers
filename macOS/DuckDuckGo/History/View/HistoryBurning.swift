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

protocol HistoryBurning: AnyObject {
    func burn(_ visits: [Visit], animated: Bool) async
    func burnAll() async
}

final class FireHistoryBurner: HistoryBurning {
    let fireproofDomains: DomainFireproofStatusProviding
    let fire: () async -> Fire

    /**
     * The arguments here are async closures because FireHistoryBurner is initialized
     * on a background thread, while both `FireproofDomains` and `FireCoordinator` need to be accessed on main thread.
     */
    init(
        fireproofDomains: DomainFireproofStatusProviding,
        fire: @escaping () async -> Fire
    ) {
        self.fireproofDomains = fireproofDomains
        self.fire = fire
    }

    func burn(_ visits: [Visit], animated: Bool) async {
        guard !visits.isEmpty else {
            return
        }

        await withCheckedContinuation { continuation in
            Task { @MainActor in
                await fire().burnVisits(visits, except: fireproofDomains, isToday: animated, urlToOpenIfWindowsAreClosed: .history) {
                    continuation.resume()
                }
            }
        }
    }

    func burnAll() async {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                await fire().burnAll(opening: .history) {
                    continuation.resume()
                }
            }
        }
    }
}
