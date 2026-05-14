//
//  RebrandingColor.swift
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

/// Rebranding colors sourced from Figma: https://www.figma.com/design/3W4vi0zX8hrpQc7zInQQB6/%F0%9F%8E%A8-Global-Colors---Styles?node-id=11-1&m=dev&vars=1&var-set-id=7943-516.
/// These are currently scoped for limited use and will be promoted to a ColorPalette when approved for app-wide use.
enum RebrandingColor {

    enum GrayScale {
        static let white = Color(0xFFFFFF)
        static let gray0 = Color(0xFCFCFC)
        static let gray10 = Color(0xF5F5F5)
        static let gray20 = Color(0xE5E5E5)
        static let gray30 = Color(0xC5C5C5)
        static let gray40 = Color(0xAAAAAA)
        static let gray50 = Color(0x888888)
        static let gray60 = Color(0x686868)
        static let gray70 = Color(0x484848)
        static let gray80 = Color(0x383838)
        static let gray90 = Color(0x222222)
        static let gray100 = Color(0x181818)
        static let gray111 = Color(0x111111)
        static let black = Color(0x000000)
    }

    enum Eggshell {
        static let eggshell0 = Color(0xFBFAF9)
        static let eggshell10 = Color(0xF7F5F2)
        static let eggshell20 = Color(0xECEBE7)
        static let eggshell30 = Color(0xD1CECB)
        static let eggshell40 = Color(0xB2B0AD)
        static let eggshell50 = Color(0x8A8886)
        static let eggshell60 = Color(0x6B6968)
        static let eggshell70 = Color(0x454443)
        static let eggshell80 = Color(0x30302F)
        static let eggshell90 = Color(0x242323)
        static let eggshell100 = Color(0x171716)
    }

    enum Mandarin {
        static let mandarin0 = Color(0xFFFAF9)
        static let mandarin10 = Color(0xFFEDE5)
        static let mandarin20 = Color(0xFFDACC)
        static let mandarin30 = Color(0xFFB294)
        static let mandarin40 = Color(0xFF8D5C)
        static let mandarin50 = Color(0xF05F2B)
        static let mandarin60 = Color(0xCC3B0A)
        static let mandarin70 = Color(0x9E2B08)
        static let mandarin80 = Color(0x671907)
        static let mandarin90 = Color(0x47140B)
        static let mandarin100 = Color(0x290E0A)
    }

    enum Pondwater {
        static let pondwater0 = Color(0xF5FBFE)
        static let pondwater10 = Color(0xE6F6FF)
        static let pondwater20 = Color(0xCBEAFF)
        static let pondwater30 = Color(0xA1D0F7)
        static let pondwater40 = Color(0x75B6EB)
        static let pondwater50 = Color(0x4397E0)
        static let pondwater60 = Color(0x1074CC)
        static let pondwater70 = Color(0x045EB2)
        static let pondwater80 = Color(0x034180)
        static let pondwater90 = Color(0x02254D)
        static let pondwater100 = Color(0x01142D)
    }

    enum Lilypad {
        static let lilypad0 = Color(0xF8FCF9)
        static let lilypad10 = Color(0xE2F3E9)
        static let lilypad20 = Color(0xCFEBDA)
        static let lilypad30 = Color(0xAED5C2)
        static let lilypad40 = Color(0x84BBA8)
        static let lilypad50 = Color(0x589D88)
        static let lilypad60 = Color(0x247A64)
        static let lilypad70 = Color(0x11604D)
        static let lilypad80 = Color(0x0A4739)
        static let lilypad90 = Color(0x052F25)
        static let lilypad100 = Color(0x082119)
    }

    enum Blossom {
        static let blossom0 = Color(0xFBF7FF)
        static let blossom10 = Color(0xF5EDFF)
        static let blossom20 = Color(0xEADAFD)
        static let blossom30 = Color(0xD3B9EB)
        static let blossom40 = Color(0xC19EDB)
        static let blossom50 = Color(0x9F6EB8)
        static let blossom60 = Color(0x7D4794)
        static let blossom70 = Color(0x682A7A)
        static let blossom80 = Color(0x521A61)
        static let blossom90 = Color(0x3E0E47)
        static let blossom100 = Color(0x230829)
    }

    enum Pollen {
        static let pollen0 = Color(0xFFFBF0)
        static let pollen10 = Color(0xFEF4DA)
        static let pollen20 = Color(0xFFEAB8)
        static let pollen30 = Color(0xFFD885)
        static let pollen40 = Color(0xFFC95C)
        static let pollen50 = Color(0xFAB341)
        static let pollen60 = Color(0xF5A031)
        static let pollen70 = Color(0xB66A1F)
        static let pollen80 = Color(0x783B13)
        static let pollen90 = Color(0x47210A)
        static let pollen100 = Color(0x240F04)
    }

    enum Red {
        static let red0 = Color(0xFEF9FA)
        static let red10 = Color(0xFCECF0)
        static let red20 = Color(0xFAD8DC)
        static let red30 = Color(0xF7AAAD)
        static let red40 = Color(0xF06565)
        static let red50 = Color(0xEC434F)
        static let red60 = Color(0xCA2B3D)
        static let red70 = Color(0xA02231)
        static let red80 = Color(0x671421)
        static let red90 = Color(0x46111C)
        static let red100 = Color(0x2A0C14)
    }

    enum Green {
        static let green40 = Color(0x39B25E)
    }

}
