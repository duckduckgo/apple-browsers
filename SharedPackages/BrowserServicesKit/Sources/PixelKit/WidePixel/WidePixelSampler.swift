import Foundation
//
//  WidePixelSampler.swift
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

public protocol WidePixelSampling {
    func shouldSend(sampleRate: Float, contextID: String, pixelName: String) -> Bool
}

public struct DefaultWidePixelSampler: WidePixelSampling {

    private let storage: WidePixelStoring

    public init(storage: WidePixelStoring) {
        self.storage = storage
    }

    public func shouldSend(sampleRate: Float, contextID: String, pixelName: String) -> Bool {
        let rate = max(0.0, min(1.0, sampleRate))
        let percentile = storage.percentile(for: pixelName, contextID: contextID)
        return percentile < rate
    }

}
