//
//  Font.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import SwiftUI

#if canImport(UIKit)

public extension UIFont {

    static func daxTitle1() -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title1)
        let newDescriptor = descriptor.addingAttributes([.traits: [
            UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold]])
        return UIFont(descriptor: newDescriptor, size: descriptor.pointSize)
    }

    static func daxTitle2() -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title2)
        let newDescriptor = descriptor.addingAttributes([.traits: [
            UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold]])
        return UIFont(descriptor: newDescriptor, size: descriptor.pointSize)
    }

    static func daxTitle3() -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3)
        let newDescriptor = descriptor.addingAttributes([.traits: [
            UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold]])
        return UIFont(descriptor: newDescriptor, size: descriptor.pointSize)
    }

    static func daxHeadline() -> UIFont {
        return UIFont.preferredFont(forTextStyle: .headline)
    }

    static func daxBodyRegular() -> UIFont {
        return UIFont.preferredFont(forTextStyle: .callout)
    }

    static func daxBodyBold() -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .callout)
        let newDescriptor = descriptor.addingAttributes([.traits: [
            UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold]])
        return UIFont(descriptor: newDescriptor, size: descriptor.pointSize)
    }

    static func daxSubheadRegular() -> UIFont {
        return UIFont.preferredFont(forTextStyle: .subheadline)
    }

    static func daxSubheadSemibold() -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        let newDescriptor = descriptor.addingAttributes([.traits: [
            UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]])
        return UIFont(descriptor: newDescriptor, size: descriptor.pointSize)
    }

    static func daxButton() -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .subheadline)
        let newDescriptor = descriptor.addingAttributes([.traits: [
            UIFontDescriptor.TraitKey.weight: UIFont.Weight.bold]])
        return UIFont(descriptor: newDescriptor, size: descriptor.pointSize)
    }

    static func daxFootnoteRegular() -> UIFont {
        return UIFont.preferredFont(forTextStyle: .footnote)
    }

    static func daxFootnoteSemibold() -> UIFont {
        let descriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .footnote)
        let newDescriptor = descriptor.addingAttributes([.traits: [
            UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]])
        return UIFont(descriptor: newDescriptor, size: descriptor.pointSize)
    }

    static func daxCaption() -> UIFont {
        return UIFont.preferredFont(forTextStyle: .caption2)
    }
}

#endif
