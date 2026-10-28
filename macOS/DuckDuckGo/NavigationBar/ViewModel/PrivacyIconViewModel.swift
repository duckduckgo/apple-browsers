//
//  PrivacyIconViewModel.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import Foundation
import PrivacyDashboard

struct PrivacyIconViewModel {

    private static let maxNumberOfIcons = 4

    static func trackerImages(from trackerInfo: TrackerInfo) -> [CGImage] {
        let sortedEntities = sortedEntities(from: trackerInfo).prefix(maxNumberOfIcons)
        var images: [CGImage] = sortedEntities.map {
            if let logo = logo(for: $0) {
                return logo
            } else if let letter = letters[$0[$0.startIndex]] {
                return letter
            } else {
                return blankTrackerImage
            }
        }
        if images.count == maxNumberOfIcons {
            images[maxNumberOfIcons - 1] = shadowTrackerImage
        }
        return images
    }

    private static func sortedEntities(from trackerInfo: TrackerInfo) -> [String] {
        struct LightEntity: Hashable {
            let name: String
            let prevalence: Double
        }

        let blockedEntities: Set<LightEntity> =
            // Filter entity duplicates by using Set
            Set(trackerInfo.trackersBlocked
                    // Filter trackers without entity or entity name
                    .compactMap {
                        if let entityName = $0.entityName, entityName.count > 0 {
                            return LightEntity(name: entityName, prevalence: $0.prevalence ?? 0)
                        }
                        return nil
                    })

        return blockedEntities
            // Sort by prevalence
            .sorted { l, r -> Bool in
                return l.prevalence > r.prevalence
            }
            // Get first character
            .map {
                return $0.name.lowercased()
            }
            // Prioritise entities with images
            .sorted { _, r -> Bool in
                return "aeiou".contains(r[r.startIndex])
            }
    }

    // MARK: - Images

    static var shadowTrackerImage: CGImage! {
        {
            if NSApp.effectiveAppearance.name == .aqua {
                NSImage(resource: .shadowtracker)
            } else {
                NSImage(resource: .shadowtrackerDark)
            }
        }().cgImage(forProposedRect: nil, context: .current, hints: nil)
    }

    static var blankTrackerImage: CGImage! {
        {
            if NSApp.effectiveAppearance.name == .aqua {
                NSImage(resource: .blanktracker)
            } else {
                NSImage(resource: .blanktrackerDark)
            }
        }().cgImage(forProposedRect: nil, context: .current, hints: nil)
    }

    static var letters: [Character: CGImage] {
        if NSApp.effectiveAppearance.name == .aqua {
            return lettersAqua
        } else {
            return lettersDark
        }
    }

    private static let lettersAqua: [Character: CGImage] = {
        Character.reduceCharacters(from: "a", to: "z", into: [:]) {
            $0[$1] = NSImage(named: "\($1)")!.cgImage(forProposedRect: nil, context: .current, hints: nil)
        }
    }()

    private static let lettersDark: [Character: CGImage] = {
        Character.reduceCharacters(from: "a", to: "z", into: [:]) {
            $0[$1] = NSImage(named: "\($1)_dark")!.cgImage(forProposedRect: nil, context: .current, hints: nil)
        }
    }()

    static func logo(for trackerNetworkName: String) -> CGImage? {
        guard let trackerNetwork = TrackerNetwork(trackerNetworkName: trackerNetworkName) else { return nil }
        return {
            if NSApp.effectiveAppearance.name == .aqua {
                aquaLogo(for: trackerNetwork)
            } else {
                darkLogo(for: trackerNetwork)
            }
        }()?.cgImage(forProposedRect: nil, context: .current, hints: nil)
    }

    private static func aquaLogo(for trackerNetwork: TrackerNetwork) -> NSImage? {
        switch trackerNetwork {
        case .adform:            NSImage(resource: .adform)
        case .adobe:             NSImage(resource: .adobe)
        case .amazon:            NSImage(resource: .amazon)
        case .amobee:            NSImage(resource: .amobee)
        case .appnexus:          NSImage(resource: .appnexus)
        case .centro:            NSImage(resource: .centro)
        case .cloudflare:        NSImage(resource: .cloudflare)
        case .comscore:          NSImage(resource: .comscore)
        case .conversant:        NSImage(resource: .conversant)
        case .criteo:            NSImage(resource: .criteo)
        case .dataxu:            NSImage(resource: .dataxu)
        case .facebook:          NSImage(resource: .facebook)
        case .google:            NSImage(resource: .google)
        case .hotjar:            NSImage(resource: .hotjar)
        case .indexexchange:     NSImage(resource: .indexexchange)
        case .iponweb:           NSImage(resource: .iponweb)
        case .linkedin:          NSImage(resource: .linkedin)
        case .lotame:            NSImage(resource: .lotame)
        case .mediamath:         NSImage(resource: .mediamath)
        case .microsoft:         NSImage(resource: .microsoft)
        case .neustar:           NSImage(resource: .neustar)
        case .newrelic:          NSImage(resource: .newrelic)
        case .nielsen:           NSImage(resource: .nielsen)
        case .openx:             NSImage(resource: .openx)
        case .oracle:            NSImage(resource: .oracle)
        case .pubmatic:          NSImage(resource: .pubmatic)
        case .qwantcast:         NSImage(resource: .qwantcast)
        case .rubicon:           NSImage(resource: .rubicon)
        case .salesforce:        NSImage(resource: .salesforce)
        case .smartadserver:     NSImage(resource: .smartadserver)
        case .spotx:             NSImage(resource: .spotx)
        case .stackpath:         NSImage(resource: .stackpath)
        case .taboola:           NSImage(resource: .taboola)
        case .tapad:             NSImage(resource: .tapad)
        case .theTradeDesk:      NSImage(resource: .thetradedesk)
        case .towerdata:         NSImage(resource: .towerdata)
        case .twitter:           NSImage(resource: .twitter)
        case .verizonMedia:      NSImage(resource: .verizonmedia)
        case .windows:           NSImage(resource: .windows)
        case .xaxis:             NSImage(resource: .xaxis)
        }
    }

    private static func darkLogo(for trackerNetwork: TrackerNetwork) -> NSImage? {
        switch trackerNetwork {
        case .adform:            NSImage(resource: .adformDark)
        case .adobe:             NSImage(resource: .adobeDark)
        case .amazon:            NSImage(resource: .amazonDark)
        case .amobee:            NSImage(resource: .amobeeDark)
        case .appnexus:          NSImage(resource: .appnexusDark)
        case .centro:            NSImage(resource: .centroDark)
        case .cloudflare:        NSImage(resource: .cloudflareDark)
        case .comscore:          NSImage(resource: .comscoreDark)
        case .conversant:        NSImage(resource: .conversantDark)
        case .criteo:            NSImage(resource: .criteoDark)
        case .dataxu:            NSImage(resource: .dataxuDark)
        case .facebook:          NSImage(resource: .facebookDark)
        case .google:            NSImage(resource: .googleDark)
        case .hotjar:            NSImage(resource: .hotjarDark)
        case .indexexchange:     NSImage(resource: .indexexchangeDark)
        case .iponweb:           NSImage(resource: .iponwebDark)
        case .linkedin:          NSImage(resource: .linkedinDark)
        case .lotame:            NSImage(resource: .lotameDark)
        case .mediamath:         NSImage(resource: .mediamathDark)
        case .microsoft:         NSImage(resource: .microsoftDark)
        case .neustar:           NSImage(resource: .neustarDark)
        case .newrelic:          NSImage(resource: .newrelicDark)
        case .nielsen:           NSImage(resource: .nielsenDark)
        case .openx:             NSImage(resource: .openxDark)
        case .oracle:            NSImage(resource: .oracleDark)
        case .pubmatic:          NSImage(resource: .pubmaticDark)
        case .qwantcast:         NSImage(resource: .qwantcastDark)
        case .rubicon:           NSImage(resource: .rubiconDark)
        case .salesforce:        NSImage(resource: .salesforceDark)
        case .smartadserver:     NSImage(resource: .smartadserverDark)
        case .spotx:             NSImage(resource: .spotxDark)
        case .stackpath:         NSImage(resource: .stackpathDark)
        case .taboola:           NSImage(resource: .taboolaDark)
        case .tapad:             NSImage(resource: .tapadDark)
        case .theTradeDesk:      NSImage(resource: .thetradedeskDark)
        case .towerdata:         NSImage(resource: .towerdataDark)
        case .twitter:           NSImage(resource: .twitterDark)
        case .verizonMedia:      NSImage(resource: .verizonmediaDark)
        case .windows:           NSImage(resource: .windowsDark)
        case .xaxis:             NSImage(resource: .xaxisDark)
        }
    }
}

extension Character {

    @inlinable static func reduceCharacters<Result>(from startCharacter: Character, to endCharacter: Character, into initialResult: Result, _ updateAccumulatingResult: (_ partialResult: inout Result, Character) throws -> Void) rethrows -> Result {
        assert(startCharacter.unicodeScalars.count == 1)
        assert(endCharacter.unicodeScalars.count == 1)
        guard let start = startCharacter.unicodeScalars.first?.value,
              let end = endCharacter.unicodeScalars.first?.value,
              start <= end else {
            assertionFailure("Characters \(startCharacter) and \(endCharacter) do not form sequence")
            return initialResult
        }

        return try (start...end).reduce(into: initialResult) { result, char in
            try updateAccumulatingResult(&result, Character(UnicodeScalar(char)!))
        }
    }

}
