//
//  InitialViewLoaderTests.swift
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

import Testing
@testable import DuckDuckGo

@MainActor
@Suite("InitialViewLoader")
final class InitialViewLoaderTests {

    /// Each `start` call, holding whether it drew the after-idle New Tab Page.
    private var starts: [Bool] = []
    /// Each idle-return decision, holding whether a launch action was waiting.
    private var idleReturnDecisions: [Bool] = []
    private var drawsIdleReturnNewTabPage = false

    private func makeLoader(defersUntilForeground: Bool) -> InitialViewLoader {
        InitialViewLoader(
            defersUntilForeground: defersUntilForeground,
            drawsIdleReturnNewTabPage: { [unowned self] hasLaunchAction in
                idleReturnDecisions.append(hasLaunchAction)
                return drawsIdleReturnNewTabPage && !hasLaunchAction
            },
            start: { [unowned self] in starts.append($0) })
    }

    @available(iOS 16, macOS 13, *)
    @Test("Without deferral, the first screen is drawn when the scene connects and not again on foreground", .timeLimit(.minutes(1)))
    func notDeferredDrawsAtConnection() {
        drawsIdleReturnNewTabPage = true
        var loader = makeLoader(defersUntilForeground: false)

        loader.loadAtConnection(hasLaunchAction: false)
        loader.loadIfPending(hasLaunchAction: false)

        #expect(starts == [true])
        #expect(!loader.isPending)
        #expect(loader.drewIdleReturnNewTabPage)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With deferral, nothing is drawn or decided when the scene connects", .timeLimit(.minutes(1)))
    func deferredDrawsNothingAtConnection() {
        var loader = makeLoader(defersUntilForeground: true)

        loader.loadAtConnection(hasLaunchAction: false)

        #expect(starts.isEmpty)
        #expect(idleReturnDecisions.isEmpty)
        #expect(loader.isPending)
        #expect(!loader.drewIdleReturnNewTabPage)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With deferral, the first foreground draws the after-idle New Tab Page decided at that moment", .timeLimit(.minutes(1)))
    func deferredDecidesIdleReturnOnForeground() {
        var loader = makeLoader(defersUntilForeground: true)
        loader.loadAtConnection(hasLaunchAction: false)
        drawsIdleReturnNewTabPage = true

        loader.loadIfPending(hasLaunchAction: false)

        #expect(starts == [true])
        #expect(loader.drewIdleReturnNewTabPage)
        #expect(!loader.isPending)
    }

    @available(iOS 16, macOS 13, *)
    @Test("With deferral, a launch action waiting at the first foreground keeps the restored page", .timeLimit(.minutes(1)))
    func deferredUsesLaunchActionFromForeground() {
        drawsIdleReturnNewTabPage = true
        var loader = makeLoader(defersUntilForeground: true)
        loader.loadAtConnection(hasLaunchAction: false)

        loader.loadIfPending(hasLaunchAction: true)

        #expect(idleReturnDecisions == [true])
        #expect(starts == [false])
        #expect(!loader.drewIdleReturnNewTabPage)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The first screen is drawn only once across repeated foregrounds", .timeLimit(.minutes(1)))
    func drawsOnlyOnce() {
        var loader = makeLoader(defersUntilForeground: true)

        loader.loadIfPending(hasLaunchAction: false)
        drawsIdleReturnNewTabPage = true
        loader.loadIfPending(hasLaunchAction: false)

        #expect(starts == [false])
        #expect(idleReturnDecisions.count == 1)
        #expect(!loader.drewIdleReturnNewTabPage)
    }

}
