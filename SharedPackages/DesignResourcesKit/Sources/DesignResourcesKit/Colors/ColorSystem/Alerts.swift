//
//  Alerts.swift
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

import SwiftUI

extension Color {
    static let alertGreen = Color(0x21C000)
    static let alertYellow = Color(0xFFD000)
    static let alertRed = Color(0xEE1025)

    // MARK: - Alert Reds
    static let alertRed10 = Color(0xFF7378)
    static let alertRed20 = Color(0xFF545A)
    static let alertRed30 = Color(0xE04A4F)
    static let alertRed40 = Color(0xD1454A)
    static let alertRed50 = Color(0xEB102D)
    static let alertRed60 = Color(0xCF0E28)
    static let alertRed70 = Color(0xC10D25)

    // MARK: - Alert Yellow Backgrounds
    static let alertYellowBackgroundLight = Color(0xFFF3BF)
    static let alertYellowBackgroundDark = Color(0x4A3C1C)

    // MARK: - Alert Red OnLight & OnDark
    static let alertRedOnLight = alertRed50
    static let alertRedOnDark = alertRed20
}
