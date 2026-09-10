//
//  BrokenSitePromptPresentationCoordinator.swift
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

protocol BrokenSitePromptPresentationCoordinating: AnyObject {
    func promptDidShow()
    func promptDidHide()
}

final class BrokenSitePromptPresentationCoordinator: BrokenSitePromptPresentationCoordinating, ExternalPromoDelegate {

    private let visibilitySubject = CurrentValueSubject<Bool, Never>(false)

    var isVisible: Bool { visibilitySubject.value }

    var isVisiblePublisher: AnyPublisher<Bool, Never> {
        visibilitySubject.removeDuplicates().eraseToAnyPublisher()
    }

    /// Records a dismissal so the prompt takes part in the shared global cooldown, with a zero interval because the
    /// limiter — not promo history — decides when the prompt may appear again.
    var resultWhenHidden: PromoResult { .ignored(cooldown: 0) }

    func promptDidShow() {
        visibilitySubject.send(true)
    }

    func promptDidHide() {
        visibilitySubject.send(false)
    }

}
