//
//  DuckPlayerStorage.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Foundation

public enum DuckPlayerVariant {
    case classicA
    case nativeB
    case nativeC
}

protocol DuckPlayerVariantManager {
    
    var variant: DuckPlayerVariant { get }
    var settings: DuckPlayerSettings { get }

    func setVariant(variant: DuckPlayerVariant)
}

class DefaultDuckPlayerVariantManager: DuckPlayerVariantManager {
    
    // By default, we use the classic variant
    var variant: DuckPlayerVariant = .classicA
    var settings: DuckPlayerSettings

    init(variant: DuckPlayerVariant, settings: DuckPlayerSettings) {
        self.variant = variant
        self.settings = settings
    }

    func setVariant(variant: DuckPlayerVariant) {
        self.variant = variant

        switch variant {
        case .classicA:
            setClassicAVariant()
        case .nativeB:
            setNativeBVariant()
        case .nativeC:
            setNativeCVariant()
        }
    }

    // Private methods
    private func setClassicAVariant() {
        settings.nativeUI = false
        settings.mode = .alwaysAsk
        settings.openInNewTab = true
        self.variant = .classicA
    }

    private func setNativeBVariant() {
        settings.nativeUI = true
        settings.nativeUISERPEnabled = true
        settings.nativeUIYoutubeMode = .ask
        settings.autoplay = true
        self.variant = .nativeB
    }

    private func setNativeCVariant() {
        settings.nativeUI = true
        settings.nativeUISERPEnabled = true
        settings.nativeUIYoutubeMode = .auto
        settings.autoplay = true
        self.variant = .nativeC
    }

}
