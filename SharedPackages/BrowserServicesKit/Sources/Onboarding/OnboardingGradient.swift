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
                return Center.bottom_macOS
            } else if DevicePlatform.isIpad {
                return Center.bottom_iPad
            } else {
                return Center.bottom_iOS
            }
        case .top:
            if DevicePlatform.isMac {
                return Center.top_macOS
            } else if DevicePlatform.isIpad {
                return Center.top_iPad
            } else {
                return Center.top_iOS
            }
        }
    }

    struct Center {
        static let bottom_iOS = UnitPoint(x: 1.11, y: 0.76)
        static let top_iOS = UnitPoint(x: 0.87, y: 1.0)

        static let bottom_iPad = UnitPoint(x: 0.82, y: 0.98)
        static let top_iPad = UnitPoint(x: 0.9, y: 1.14)

        static let bottom_macOS = UnitPoint(x: 0.5, y: 1.45)
        static let top_macOS = UnitPoint(x: 0.71, y: 1.2)
    }
}

@available(iOS 15, macOS 13, *)
extension OnboardingGradient {

    struct LightGradient: View {

        init() {}

//        struct GradientColor {
//            static let top1_macOS = Color(red: 0.7, green: 0.77, blue: 0.98).opacity(0.16)
//            static let top2_macOS = Color(red: 0.7, green: 0.77, blue: 0.98).opacity(0.64)
//
//            static let top1_iOS = Color(red: 1, green: 0.94, blue: 0.76).opacity(0.64)
//            static let top2_iOS = Color(red: 0.7, green: 0.77, blue: 0.98).opacity(0.8)
//
//            static let bottom1_macOS = Color(red: 1, green: 0.94, blue: 0.76)
//            static let bottom2_macOS = Color(red: 1, green: 0.94, blue: 0.76).opacity(0)
//
//            static let bottom1_iOS = Color(red: 1, green: 0.91, blue: 0.64).opacity(0)
//            static let bottom2_iOS = Color(red: 1, green: 0.91, blue: 0.64).opacity(0)
//        }

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

//        func stops(for type: OnboardingGradient.GradientType) -> [Gradient.Stop] {
//            switch type {
//            case .bottom:
//                if DevicePlatform.isMac {
//                    return [
//                        Gradient.Stop(color: GradientColor.bottom1_macOS, location: 0.00),
//                        Gradient.Stop(color: GradientColor.bottom2_macOS, location: 1.00),
//                    ]
//                } else {
//                    return [
//                        Gradient.Stop(color: Color(red: 1, green: 0.91, blue: 0.64).opacity(0), location: 0.00),
//                        Gradient.Stop(color: Color(red: 1, green: 0.91, blue: 0.64).opacity(0), location: 1.00),
//                    ]
//                }
//            case .top:
//                if DevicePlatform.isMac {
//                    return [
//                        Gradient.Stop(color: GradientColor.top1_macOS, location: 0.00),
//                        Gradient.Stop(color: GradientColor.top2_macOS, location: 1.00),
//                    ]
//                } else {
//                    return [
//                        Gradient.Stop(color: GradientColor.top1_iOS, location: 0.00),
//                        Gradient.Stop(color: GradientColor.top2_iOS, location: 1.00),
//                    ]
//                }
//            }
//        }
    }

    struct DarkGradient: View {

        init() {}

//        struct GradientColor {
//            static let top1_macOS = Color(red: 0.28, green: 0.39, blue: 0.92).opacity(0.56)
//            static let top2_macOS = Color(red: 0.02, green: 0.1, blue: 0.42).opacity(0.9)
//
//            static let top1_iOS = Color(red: 0.28, green: 0.39, blue: 0.92).opacity(0.48)
//            static let top2_iOS = Color(red: 0.02, green: 0.1, blue: 0.42).opacity(0.72)
//
//            static let bottom1_macOS = Color(red: 0.26, green: 0.26, blue: 0.84).opacity(0.64)
//            static let bottom2_macOS = Color(red: 0.34, green: 0.17, blue: 0.8).opacity(0)
//
//            static let bottom1_iOS = Color(red: 0.26, green: 0.26, blue: 0.84).opacity(0.64)
//            static let bottom2_iOS = Color(red: 0.25, green: 0.14, blue: 0.56).opacity(0)
//        }

        var body: some View {
            ZStack {
                EllipticalGradient(
                    stops: [
                        Gradient.Stop(color: Color(red: 0.26, green: 0.26, blue: 0.84).opacity(0.64), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.25, green: 0.14, blue: 0.56).opacity(0), location: 1.00),
                    ],
                    center: center(for: .bottom),
                    endRadiusFraction: 1
                )
                EllipticalGradient(
                    stops: [
                        Gradient.Stop(color: Color(red: 0.28, green: 0.39, blue: 0.92).opacity(0.48), location: 0.00),
                        Gradient.Stop(color: Color(red: 0.25, green: 0.14, blue: 0.56).opacity(0), location: 1.00),
                    ],
                    center: OnboardingGradient.center(for: .top),
                    endRadiusFraction: 1
                )
            }
            .background(Color(red: 0.07, green: 0.07, blue: 0.07))
        }

//        func stops(for type: OnboardingGradient.GradientType) -> [Gradient.Stop] {
//            switch type {
//            case .bottom:
//                if DevicePlatform.isMac {
//                    return [
//                        Gradient.Stop(color: GradientColor.bottom1_macOS, location: 0.00),
//                        Gradient.Stop(color: GradientColor.bottom2_macOS, location: 1.00),
//                    ]
//                } else {
//                    return [
//                        Gradient.Stop(color: GradientColor.bottom1_iOS, location: 0.00),
//                        Gradient.Stop(color: GradientColor.bottom2_iOS, location: 1.00),
//                    ]
//                }
//            case .top:
//                if DevicePlatform.isMac {
//                    return [
//                        Gradient.Stop(color: GradientColor.top1_macOS, location: 0.00),
//                        Gradient.Stop(color: GradientColor.top2_macOS, location: 1.00),
//                    ]
//                } else {
//                    return [
//                        Gradient.Stop(color: GradientColor.top1_iOS, location: 0.00),
//                        Gradient.Stop(color: GradientColor.top2_iOS, location: 1.00),
//                    ]
//                }
//            }
//        }
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

enum DevicePlatform {
    static var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    static var isIpad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    static var isIphone: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }
}
