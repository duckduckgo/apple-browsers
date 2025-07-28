//
//  SystemSettingsPiPTutorialPixelHandler.swift
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

import Core
import SystemSettingsPiPTutorial

final class SystemSettingsPiPTutorialPixelHandler: SystemSettingsPiPTutorialEventMapper {
    private static let regex = #"([a-zA-Z\-]+\.lproj/[^/]+)$"#

    private let dailyPixelFiring: DailyPixelFiring.Type

    init(dailyPixelFiring: DailyPixelFiring.Type = DailyPixel.self) {
        self.dailyPixelFiring = dailyPixelFiring
    }

    func fireFailedToLoadPiPTutorialEvent(error: (any Error)?, urlPath: String?) {
        let parameters = extractVideoUrlPath(from: urlPath).flatMap { ["video_url_path": $0] } ?? [:]
        dailyPixelFiring.fireDailyAndCount(.systemSettingsPiPTutorialFailedToLoadVideo, error: error, withAdditionalParameters: parameters)
    }

    private func extractVideoUrlPath(from path: String?) -> String? {
        guard
            let path,
            let range = path.range(of: Self.regex, options: .regularExpression)
        else {
            return nil
        }
        return String(path[range])
    }

}
