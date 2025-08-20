//
//  OnboardingGradient.swift
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

import SwiftUI
import Common

public struct OnboardingGradient: View {
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    public var body: some View {
        if #available(iOS 15, macOS 13, *) {
            gradient
        } else {
            gradientImage
        }
    }

    @available(iOS 15, macOS 13, *)
    @ViewBuilder
    private var gradient: some View {
        switch colorScheme {
        case .light:
            LightGradient()
        case .dark:
            DarkGradient()
        @unknown default:
            LightGradient()
        }
    }

    private var gradientImage: some View {
        Image("OnboardingGradient", bundle: bundle)
            .resizable()
    }

    enum GradientType {
        case bottom
        case top
    }

    static func center(for type: GradientType) -> UnitPoint {
        switch type {
        case .bottom:
            if DevicePlatform.isMac {
                return Center.macOSBottom
            } else if DevicePlatform.isIpad {
                return Center.iPadBottom
            } else {
                return Center.iOSBottom
            }
        case .top:
            if DevicePlatform.isMac {
                return Center.macOSTop
            } else if DevicePlatform.isIpad {
                return Center.iPadTop
            } else {
                return Center.iOSTop
            }
        }
    }

    struct Center {
        static let iOSBottom = UnitPoint(x: 1.11, y: 0.76)
        static let iOSTop = UnitPoint(x: 0.87, y: 1.0)

        static let iPadBottom = UnitPoint(x: 0.82, y: 0.98)
        static let iPadTop = UnitPoint(x: 0.9, y: 1.14)

        static let macOSBottom = UnitPoint(x: 0.5, y: 1.45)
        static let macOSTop = UnitPoint(x: 0.71, y: 1.2)
    }
}

@available(iOS 15, macOS 13, *)
extension OnboardingGradient {

    struct LightGradient: View {

        init() {}

        var body: some View {
            ZStack {
                EllipticalGradient(
                    stops: [
                        Gradient.Stop(color: Color(red: 1, green: 0.94, blue: 0.76).opacity(0.64), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.7, green: 0.77, blue: 0.98).opacity(0.8), location: 1.00)
                    ],
                    center: OnboardingGradient.center(for: .top),
                    endRadiusFraction: 1
                )
                EllipticalGradient(
                    stops: [
                        Gradient.Stop(color: Color(red: 1, green: 0.91, blue: 0.64).opacity(0), location: 0.00),
                        Gradient.Stop(color: Color(red: 1, green: 0.91, blue: 0.64).opacity(0), location: 1.00)
                    ],
                    center: center(for: .bottom),
                    endRadiusFraction: 1
                )
            }
            .background(.white)
        }
    }

    struct DarkGradient: View {

        init() {}

        var body: some View {
            ZStack {
                EllipticalGradient(
                    stops: [
                        Gradient.Stop(color: Color(red: 0.28, green: 0.39, blue: 0.92).opacity(0.48), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.02, green: 0.1, blue: 0.42).opacity(0.72), location: 1.00),
                    ],
                    center: center(for: .bottom),
                    endRadiusFraction: 1
                )
                EllipticalGradient(
                    stops: [
                        Gradient.Stop(color: Color(red: 0.26, green: 0.26, blue: 0.84).opacity(0.64), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.25, green: 0.14, blue: 0.56).opacity(0), location: 1.00),
                    ],
                    center: OnboardingGradient.center(for: .top),
                    endRadiusFraction: 1
                )
            }
            .background(Color(red: 0.07, green: 0.07, blue: 0.07))
        }
    }
}

#Preview("Light Mode") {
    OnboardingGradient()
        .preferredColorScheme(.light)
}

#Preview("Dark Mode - Elliptical") {
    OnboardingGradient()
        .preferredColorScheme(.dark)
}
