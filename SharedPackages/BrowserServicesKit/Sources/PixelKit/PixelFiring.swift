//
//  PixelFiring.swift
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

/// Protocol to support mocking pixel firing.
public protocol PixelFiring {
    func fire(_ event: PixelKitEvent,
              frequency: PixelKit.Frequency,
              includeAppVersionParameter: Bool,
              withAdditionalParameters: [String: String]?,
              withNamePrefix: String?,
              onComplete: @escaping PixelKit.CompletionBlock)
}

extension PixelFiring {
    public func fire(_ event: PixelKitEvent) {
        fire(event, frequency: .standard, includeAppVersionParameter: true)
    }

    public func fire(_ event: PixelKitEvent,
                     frequency: PixelKit.Frequency) {
        fire(event, frequency: frequency, includeAppVersionParameter: true, withAdditionalParameters: nil, withNamePrefix: nil, onComplete: { _, _ in })
    }

    public func fire(_ event: PixelKitEvent,
                     frequency: PixelKit.Frequency,
                     includeAppVersionParameter: Bool) {
        fire(event, frequency: frequency, includeAppVersionParameter: includeAppVersionParameter, withAdditionalParameters: nil, withNamePrefix: nil, onComplete: { _, _ in })
    }

    public func fire(_ event: PixelKitEvent,
                     frequency: PixelKit.Frequency,
                     onComplete: @escaping PixelKit.CompletionBlock) {
        fire(event, frequency: frequency, includeAppVersionParameter: true, withAdditionalParameters: nil, withNamePrefix: nil, onComplete: onComplete)
    }

    public func fire(_ event: PixelKitEvent,
                     frequency: PixelKit.Frequency,
                     withAdditionalParameters parameters: [String: String]?) {
        fire(event, frequency: frequency, includeAppVersionParameter: true, withAdditionalParameters: parameters, withNamePrefix: nil, onComplete: { _, _ in })
    }

    public func fire(_ event: PixelKitEvent,
                     frequency: PixelKit.Frequency,
                     withAdditionalParameters parameters: [String: String]?,
                     withNamePrefix namePrefix: String?) {
        fire(event, frequency: frequency, includeAppVersionParameter: true, withAdditionalParameters: parameters, withNamePrefix: namePrefix, onComplete: { _, _ in })
    }
}

extension PixelKit: PixelFiring {
    public func fire(_ event: PixelKitEvent,
                     frequency: PixelKit.Frequency,
                     includeAppVersionParameter: Bool,
                     withAdditionalParameters parameters: [String: String]?,
                     withNamePrefix namePrefix: String?,
                     onComplete: @escaping PixelKit.CompletionBlock) {
        fire(event, frequency: frequency, withHeaders: nil, withAdditionalParameters: parameters,
             withNamePrefix: namePrefix, includeAppVersionParameter: includeAppVersionParameter, onComplete: onComplete)
    }
}
