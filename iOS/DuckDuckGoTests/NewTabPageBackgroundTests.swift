//
//  NewTabPageBackgroundTests.swift
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

import Combine
import Foundation
import Testing
import UIKit
@testable import DuckDuckGo

@Suite("Seeded New Tab Page backgrounds")
@MainActor
struct NewTabPageBackgroundTests {
    private func withStore(_ body: (NewTabPageBackgroundStore, UserDefaults) -> Void) {
        let suite = "NewTabPageBackgroundTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(NewTabPageBackgroundStore(keyValueStore: defaults, makeSeed: { 42 }), defaults)
    }

    @available(iOS 16, macOS 13, *)
    @Test("First seed is generated once and survives a new store", .timeLimit(.minutes(1)))
    func initialSeedPersists() {
        withStore { store, defaults in
            #expect(store.settings == NewTabPageBackgroundSettings(isProcedural: true, seed: 42))
            let reloaded = NewTabPageBackgroundStore(keyValueStore: defaults, makeSeed: { 99 })
            #expect(reloaded.settings == store.settings)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("All UInt64 seeds survive storage, including zero", .timeLimit(.minutes(1)), arguments: [UInt64.min, 42, UInt64.max])
    func seedRoundTrip(seed: UInt64) {
        withStore { store, defaults in
            store.settings = NewTabPageBackgroundSettings(isProcedural: false, seed: seed)
            let reloaded = NewTabPageBackgroundStore(keyValueStore: defaults)
            #expect(reloaded.settings == NewTabPageBackgroundSettings(isProcedural: false, seed: seed))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Open pages receive mode and seed changes from other stores", .timeLimit(.minutes(1)))
    func observesOtherStores() {
        withStore { store, defaults in
            var received: [NewTabPageBackgroundSettings] = []
            let subscription = store.publisher.sink { received.append($0) }
            let otherStore = NewTabPageBackgroundStore(keyValueStore: defaults)
            otherStore.settings = NewTabPageBackgroundSettings(isProcedural: false, seed: 42)
            otherStore.settings = NewTabPageBackgroundSettings(isProcedural: true, seed: 99)
            otherStore.settings = otherStore.settings
            #expect(received == [
                NewTabPageBackgroundSettings(isProcedural: true, seed: 42),
                NewTabPageBackgroundSettings(isProcedural: false, seed: 42),
                NewTabPageBackgroundSettings(isProcedural: true, seed: 99)
            ])
            withExtendedLifetime(subscription) {}
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Invalid seeds never replace the saved scene", .timeLimit(.minutes(1)),
          arguments: ["", " ", "-1", "1.5", "abc", "18446744073709551616"])
    func invalidSeedIsIgnored(text: String) {
        withStore { store, _ in
            let model = NewTabPageCustomizationModel(pixelFiring: nil, backgroundStore: store)
            model.backgroundSeedDraft = text
            #expect(!model.isBackgroundSeedValid)
            model.applyBackgroundSeed()
            #expect(store.settings.seed == 42)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Applying a seed and switching to standard preserves the generated pond", .timeLimit(.minutes(1)))
    func appliesSeedAndRestoresMode() {
        withStore { store, _ in
            let model = NewTabPageCustomizationModel(pixelFiring: nil, backgroundStore: store)
            model.backgroundSeedDraft = " 18446744073709551615 "
            model.applyBackgroundSeed()
            #expect(model.backgroundSeedDraft == String(UInt64.max))
            model.isProceduralBackgroundEnabled = false
            let reopened = NewTabPageCustomizationModel(pixelFiring: nil, backgroundStore: store)
            #expect(!reopened.isProceduralBackgroundEnabled)
            #expect(reopened.backgroundSeedDraft == String(UInt64.max))
            reopened.isProceduralBackgroundEnabled = true
            #expect(store.settings == NewTabPageBackgroundSettings(isProcedural: true, seed: .max))
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Randomizing always produces a different seed and enables the pond", .timeLimit(.minutes(1)))
    func randomizationChangesSeed() {
        withStore { store, _ in
            let model = NewTabPageCustomizationModel(pixelFiring: nil, backgroundStore: store, makeBackgroundSeed: { 42 })
            model.isProceduralBackgroundEnabled = false
            model.randomizeBackgroundSeed()
            #expect(store.settings == NewTabPageBackgroundSettings(isProcedural: true, seed: 43))
            #expect(model.backgroundSeedDraft == "43")
            model.randomizeBackgroundSeed()
            #expect(store.settings.seed == 42)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Seeds reproduce the entire scene and different seeds vary the landscape", .timeLimit(.minutes(1)),
          arguments: [UInt64.min, 42, UInt64.max])
    func deterministicScene(seed: UInt64) {
        let scene = NewTabPagePondScene(seed: seed)
        #expect(scene == NewTabPagePondScene(seed: seed))
        let other = NewTabPagePondScene(seed: seed &+ 1)
        #expect(scene.shoreline != other.shoreline)
        #expect(scene.plants != other.plants)
        #expect(scene.lilyPads != other.lilyPads)
        #expect(scene.ripples != other.ripples)
        #expect(scene.shoreline.allSatisfy { (0.77 ... 0.88).contains($0.y) })
    }

    @available(iOS 16, macOS 13, *)
    @Test("Reed heads overlap their stalk and follow its tangent", .timeLimit(.minutes(1)),
          arguments: [UInt64.min, 42, 2026, 8675309, UInt64.max])
    func reedHeadsStayConnected(seed: UInt64) {
        for plant in NewTabPagePondScene(seed: seed).plants {
            #expect(plant.headPath.contains(plant.stem.end))
            #expect(plant.headPath.contains(plant.stem.point(at: 0.995)))
            let headAxis = CGPoint(x: 0, y: -1).applying(plant.headTransform)
            let attachment = CGPoint.zero.applying(plant.headTransform)
            let tangent = CGPoint(x: plant.stem.end.x - plant.stem.control2.x, y: plant.stem.end.y - plant.stem.control2.y)
            let crossProduct = (headAxis.x - attachment.x) * tangent.y - (headAxis.y - attachment.y) * tangent.x
            #expect(abs(crossProduct) < 0.000001)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Foreground banks end below the image and lily pads do not overlap", .timeLimit(.minutes(1)),
          arguments: [UInt64.min, 42, 2026, 8675309, UInt64.max])
    func landscapeHasNoCutoffEdgesOrOverlappingPads(seed: UInt64) {
        let scene = NewTabPagePondScene(seed: seed)
        #expect(scene.leftBank.last!.y > 1)
        #expect(scene.rightBank.last!.y > 1)
        for (index, pad) in scene.lilyPads.enumerated() {
            #expect(!scene.lilyPads.dropFirst(index + 1).contains { $0.intersects(pad) })
            let corners = [CGPoint(x: pad.minX, y: pad.minY), CGPoint(x: pad.maxX, y: pad.minY),
                           CGPoint(x: pad.minX, y: pad.maxY), CGPoint(x: pad.maxX, y: pad.maxY)]
            #expect(!corners.contains { NewTabPagePondScene.bankPath(for: scene.leftBank).contains($0) })
            #expect(!corners.contains { NewTabPagePondScene.bankPath(for: scene.rightBank).contains($0) })
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Ripple segments meet without corners", .timeLimit(.minutes(1)), arguments: [UInt64.min, 42, UInt64.max])
    func rippleTangentsStayContinuous(seed: UInt64) {
        let ripples = NewTabPagePondScene(seed: seed).ripples
        for index in stride(from: 0, to: ripples.count, by: 2) {
            let first = ripples[index]
            let second = ripples[index + 1]
            #expect(first.end == second.start)
            let incoming = CGPoint(x: first.end.x - first.control2.x, y: first.end.y - first.control2.y)
            let outgoing = CGPoint(x: second.control1.x - second.start.x, y: second.control1.y - second.start.y)
            #expect(abs(incoming.x * outgoing.y - incoming.y * outgoing.x) < 0.000001)
            #expect(incoming.x * outgoing.x + incoming.y * outgoing.y > 0)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Light and dark render different palettes while each seed stays reproducible", .timeLimit(.minutes(1)))
    func rendersBothAppearances() {
        let light = render(seed: 42, style: .light)
        #expect(light == render(seed: 42, style: .light))
        #expect(light != render(seed: 43, style: .light))
        let dark = render(seed: 42, style: .dark)
        #expect(light != dark)
        #expect(dark == render(seed: 42, style: .dark))
    }

    private func render(seed: UInt64, style: UIUserInterfaceStyle) -> Data? {
        let view = NewTabPageBackgroundView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        let controller = UIViewController()
        controller.view = view
        let window = UIWindow(frame: view.bounds)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        #expect(view.traitCollection.userInterfaceStyle == style)
        view.settings = NewTabPageBackgroundSettings(isProcedural: true, seed: seed)
        view.layoutIfNeeded()
        view.layer.displayIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).pngData { context in
            view.layer.render(in: context.cgContext)
        }
    }
}
