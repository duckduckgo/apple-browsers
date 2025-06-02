//
//  DuckPlayerPixelFiring.swift
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
import Core

/// Protocol defining the interface for firing DuckPlayer-related pixels
public protocol DuckPlayerPixelFiring {

    /// Fires a DuckPlayer pixel
    /// - Parameters:
    ///   - pixel: The pixel event to fire
    ///   - parameters: Additional parameters to include with the pixel
    ///   - debounceTime: Time in seconds to debounce identical pixel events
    static func fire(_ pixel: Pixel.Event,
                     withAdditionalParameters parameters: [String: String],
                     debounceTime: Int)

    /// Fires a daily DuckPlayer pixel
    /// - Parameters:
    ///   - pixel: The pixel event to fire
    ///   - parameters: Additional parameters to include with the pixel
    ///   - debounceTime: Time in seconds to debounce identical pixel events
    static func fireDaily(_ pixel: Pixel.Event,
                          withAdditionalParameters parameters: [String: String],
                          debounceTime: Int)
}

public extension DuckPlayerPixelFiring {
    static var defaultDebounceTime: Int { 2 }
    static var defaultParameters: [String: String] { [:] }

    static func fire(_ pixel: Pixel.Event) {
        fire(pixel, withAdditionalParameters: defaultParameters, debounceTime: defaultDebounceTime)
    }

    static func fire(_ pixel: Pixel.Event, debounceTime: Int) {
        fire(pixel, withAdditionalParameters: defaultParameters, debounceTime: debounceTime)
    }

    static func fire(_ pixel: Pixel.Event, withAdditionalParameters parameters: [String: String]) {
        fire(pixel, withAdditionalParameters: parameters, debounceTime: defaultDebounceTime)
    }

    static func fireDaily(_ pixel: Pixel.Event) {
        fireDaily(pixel, withAdditionalParameters: defaultParameters, debounceTime: defaultDebounceTime)
    }

    static func fireDaily(_ pixel: Pixel.Event, debounceTime: Int) {
        fireDaily(pixel, withAdditionalParameters: defaultParameters, debounceTime: debounceTime)
    }

    static func fireDaily(_ pixel: Pixel.Event, withAdditionalParameters parameters: [String: String]) {
        fireDaily(pixel, withAdditionalParameters: parameters, debounceTime: defaultDebounceTime)
    }
}

public final class DuckPlayerPixelHandler: DuckPlayerPixelFiring {
    public static func fire(_ pixel: Pixel.Event,
                            withAdditionalParameters parameters: [String: String],
                            debounceTime: Int) {
        Pixel.fire(pixel: pixel, withAdditionalParameters: parameters, debounce: debounceTime)
    }

    public static func fireDaily(_ pixel: Pixel.Event,
                                 withAdditionalParameters parameters: [String: String],
                                 debounceTime: Int) {
        DailyPixel.fire(pixel: pixel, withAdditionalParameters: parameters)
    }
}
