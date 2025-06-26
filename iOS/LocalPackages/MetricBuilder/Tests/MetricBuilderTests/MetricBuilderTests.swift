//
//  MetricBuilderTests.swift
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

import Testing
import SwiftUI
import UIKit
@testable import MetricBuilder

@Suite("MetricBuilder Tests")
struct MetricBuilderTests {

    @MainActor
    struct InitialisationTest {

        @Test("Initialise with device-specific values")
        func initializeWithDeviceValues() {
            // GIVEN
            let builder = MetricBuilder(iPhone: 10, iPad: 20)

            // THEN
            #expect(builder.build(v: .compact, h: .compact) == 10) // iPhone Portrait
            #expect(builder.build(v: .regular, h: .compact) == 10) // iPhone Landscape
            #expect(builder.build(v: .regular, h: .regular) == 20) // iPad
        }

        @Test("Initialise with default value")
        func initializeWithDefaultValue() {
            // GIVEN
            let builder = MetricBuilder(default: 15)

            // THEN
            #expect(builder.build(v: .compact, h: .compact) == 15)
            #expect(builder.build(v: .regular, h: .compact) == 15)
            #expect(builder.build(v: .regular, h: .regular) == 15)
        }

        @Test("Initialise with custom screen bounds")
        func initializeWithScreenBounds() {
            // GIVEN
            let customBounds = CGRect(x: 0, y: 0, width: 320, height: 568)
            let builder = MetricBuilder(default: 10, screenBounds: customBounds)
                .iPhoneSmallScreen(5)

            // THEN
            #expect(builder.build(v: .regular, h: .compact) == 5) // Should detect small screen due to width < 375
        }

    }

    @MainActor
    struct iPhoneTests {

        @Test("Configure iPhone with single value")
        func configureIPhoneSingleValue() {
            // GIVEN
            let builder = MetricBuilder(default: 10)
                .iPhone(15)

            // THEN
            #expect(builder.build(v: .regular, h: .compact) == 15) // Portrait
            #expect(builder.build(v: .compact, h: .compact) == 15) // Landscape
        }

        @Test("Configure iPhone with orientation-specific values")
        func configureIPhoneOrientationValues() {
            // GIVEN
            let builder = MetricBuilder(default: 10)
                .iPhone(portrait: 12, landscape: 18)

            // THEN
            #expect(builder.build(v: .regular, h: .compact) == 12) // Portrait
            #expect(builder.build(v: .compact, h: .compact) == 18) // Landscape
        }

        @Test("Configure iPhone with partial orientation updates")
        func configureIPhonePartialUpdates() {
            // GIVEN
            let builder = MetricBuilder(default: 10)
                .iPhone(15) // Both orientations = 15
                .iPhone(landscape: 20) // Only update landscape

            // THEN
            #expect(builder.build(v: .regular, h: .compact) == 15) // Portrait unchanged
            #expect(builder.build(v: .compact, h: .compact) == 20) // Landscape updated
        }

    }

    @MainActor
    struct iPadTests {
        static let portraitBounds = CGRect(x: 0, y: 0, width: 768, height: 1024)
        static let landscapeBounds = CGRect(x: 0, y: 0, width: 1024, height: 768)

        @Test("Configure iPad with single value")
        func configureIPadSingleValue() {
            // GIVEN
            let portraitBuilder = MetricBuilder(default: 10, screenBounds: Self.portraitBounds)
                .iPad(25)
            let landscapeBuilder = MetricBuilder(default: 10, screenBounds: Self.landscapeBounds)
                .iPad(30)

            // THEN
            #expect(portraitBuilder.build(v: .regular, h: .regular) == 25)
            #expect(landscapeBuilder.build(v: .regular, h: .regular) == 30)
        }

        @Test("Configure iPad with orientation-specific values")
        func configureIPadOrientationValues() {
            // GIVEN
            let portraitBuilder = MetricBuilder(default: 10, screenBounds: Self.portraitBounds)
                .iPad(portrait: 30, landscape: 40)
            let landscapeBuilder = MetricBuilder(default: 10, screenBounds: Self.landscapeBounds)
                .iPad(portrait: 30, landscape: 40)

            // THEN
            #expect(portraitBuilder.build(v: .regular, h: .regular) == 30)
            #expect(landscapeBuilder.build(v: .regular, h: .regular) == 40)
        }

        @Test("Fallback from orientation to device default")
        func fallbackOrientationToDefault() {
            // GIVEN
            let portraitBuilder = MetricBuilder(iPhone: 10, iPad: 20, screenBounds: Self.portraitBounds)
                .iPad(portrait: 30)
            let landscape = MetricBuilder(iPhone: 10, iPad: 20, screenBounds: Self.landscapeBounds)
                .iPad(portrait: 30)

            // THEN
            #expect(portraitBuilder.build(v: .regular, h: .regular) == 30) // iPad Portrait uses override
            #expect(landscape.build(v: .regular, h: .regular) == 20) // iPad Landscape uses default value
        }

    }

    @MainActor
    struct iPhoneSmallScreenTests {

        @Test("Configure small screen iPhone")
        func configureSmallScreenIPhone() {
            // GIVEN
            let smallScreenBounds = CGRect(x: 0, y: 0, width: 320, height: 568) // iPhone SE
            let regularBounds = CGRect(x: 0, y: 0, width: 428, height: 932) // iPhone 16 Pro

            let smallBuilder = MetricBuilder(iPhone: 16, iPad: 24, screenBounds: smallScreenBounds)
                .iPhoneSmallScreen(12)
            let regularBuilder = MetricBuilder(iPhone: 16, iPad: 24, screenBounds: regularBounds)
                .iPhoneSmallScreen(12)

            // THEN
            #expect(smallBuilder.build(v: .regular, h: .compact) == 12)
            #expect(regularBuilder.build(v: .regular, h: .compact) == 16)
        }

        @Test("Configure small screen with orientations")
        func configureSmallScreenOrientations() {
            // GIVEN
            let portraitBounds = CGRect(x: 0, y: 0, width: 320, height: 568)
            let landscapeBounds = CGRect(x: 0, y: 0, width: 568, height: 320)

            let portraitBuilder = MetricBuilder(default: 10, screenBounds: portraitBounds)
                .iPhoneSmallScreen(portrait: 8, landscape: 6)
            let landscapeBuilder = MetricBuilder(default: 10, screenBounds: landscapeBounds)
                .iPhoneSmallScreen(portrait: 8, landscape: 6)

            // THEN
            #expect(portraitBuilder.build(v: .regular, h: .compact) == 8)
            #expect(landscapeBuilder.build(v: .compact, h: .compact) == 6)
        }

        @Test("Fallback from small screen to iPhone to default")
        func fallbackSmallScreen() {
            // GIVEN
            let smallScreenBounds = CGRect(x: 0, y: 0, width: 320, height: 568)
            // No small screen value set, should fall back to iPhone
            var builder = MetricBuilder(iPhone: 15, iPad: 20, screenBounds: smallScreenBounds)

            // THEN
            #expect(builder.build(v: .regular, h: .compact) == 15)
            #expect(builder.build(v: .compact, h: .compact) == 15)

            // Small screen portrait set, landscape should fall back
            builder = MetricBuilder(iPhone: 15, iPad: 20, screenBounds: smallScreenBounds)
                .iPhoneSmallScreen(portrait: 8)
                .iPhone(landscape: 18)

            // THEN
            #expect(builder.build(v: .regular, h: .compact) == 8) // Uses small screen
            #expect(builder.build(v: .compact, h: .compact) == 18) // Falls back to iPhone landscape
        }

    }

    @MainActor
    struct OrientationSpecificTests {

        @Test("Configure portrait for all devices")
        func configurePortraitAllDevices() {
            // GIVEN
            let builder = MetricBuilder(default: 10)
                .portrait(20)

            // THEN
            #expect(builder.build(v: .regular, h: .compact) == 20) // iPhone portrait
            #expect(builder.build(v: .regular, h: .regular) == 20) // iPad portrait
        }

        @Test("Configure portrait for specific devices")
        func configurePortraitSpecificDevices() {
            // GIVEN
            let smallScreenBounds = CGRect(x: 0, y: 0, width: 320, height: 568)
            let builder = MetricBuilder(default: 10, screenBounds: smallScreenBounds)
                .portrait(iPhone: 15, iPhoneSmallScreen: 12, iPad: 25)

            // THEN Test small screen
            #expect(builder.build(v: .regular, h: .compact) == 12)

            // GIVEN (Test regular iPhone)
            let regularBuilder = MetricBuilder(default: 10)
                .portrait(iPhone: 15, iPhoneSmallScreen: 12, iPad: 25)
            // THEN
            #expect(regularBuilder.build(v: .regular, h: .compact) == 15)
            #expect(regularBuilder.build(v: .regular, h: .regular) == 25)
        }

        @Test("Configure landscape for all devices")
        func configureLandscapeAllDevices() {
            // GIVEN
            let landscapeBounds = CGRect(x: 0, y: 0, width: 844, height: 390)
            let builder = MetricBuilder(iPhone: 10, iPad: 20, screenBounds: landscapeBounds)
                .landscape(30)

            // THEN
            #expect(builder.build(v: .compact, h: .compact) == 30) // iPhone landscape
            #expect(builder.build(v: .regular, h: .regular) == 30) // iPad landscape
        }

    }

    @MainActor
    struct BuildWithTraitCollectionTests {

        @Test("Build with UITraitCollection")
        func buildWithTraitCollection() {
            // GIVEN
            let builder = MetricBuilder(iPhone: 10, iPad: 20)

            // Create trait collections
            let iPhoneTraits = UITraitCollection(traitsFrom: [
                UITraitCollection(horizontalSizeClass: .compact),
                UITraitCollection(verticalSizeClass: .regular)
            ])

            let iPadTraits = UITraitCollection(traitsFrom: [
                UITraitCollection(horizontalSizeClass: .regular),
                UITraitCollection(verticalSizeClass: .regular)
            ])

            // THEN
            #expect(builder.build(traits: iPhoneTraits) == 10)
            #expect(builder.build(traits: iPadTraits) == 20)
        }

    }

}
