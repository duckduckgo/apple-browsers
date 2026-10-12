//
//  PageSignalsPixel.swift
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

import Common
import DDGNavigation
import PixelKit

enum PageSignalsPixel: PixelKit.Event {
    case resourceLoadDelegateAlreadySet

    var name: String {
        switch self {
        case .resourceLoadDelegateAlreadySet:
            return "page-signals_resource-load-delegate-already-set"
        }
    }
}

final class PageSignalsEventMapper: EventMapping<PageSignalsEvent> {

    init(pixelFiring: (any PixelKitFiring)? = PixelKit.shared) {
        super.init { event, _, _, _ in
            switch event {
            case .resourceLoadDelegateAlreadySet:
                pixelFiring?.fire(PageSignalsPixel.resourceLoadDelegateAlreadySet, frequency: .dailyAndCount)
            }
        }
    }

    @available(*, unavailable, message: "Use init(pixelFiring:) instead")
    override init(mapping: @escaping EventMapping<PageSignalsEvent>.Mapping) {
        fatalError("Use init(pixelFiring:) instead")
    }
}
