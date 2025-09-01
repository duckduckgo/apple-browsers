//
//  DefaultBrowserPiPTutorialURLProvider.swift
//  DuckDuckGo
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

import Foundation
import SystemSettingsPiPTutorial

final class DefaultBrowserPiPTutorialURLProvider: PiPTutorialURLProvider {

    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func pipTutorialURL() throws(PiPTutorialURLProviderError) -> URL {
        // Bundle searches for .lproj folders in order of user's preferred languages.
        // Falls back to development language if no preferred localization exists.
        guard let url = bundle.url(forResource: "default-browser-tutorial", withExtension: "mp4") else {
            throw .urlNotFound
        }
        return url
    }

}
