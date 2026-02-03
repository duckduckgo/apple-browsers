//
//  NSAttributedString+OnboardingRebranding.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

#if os(iOS)
import Foundation
import UIKit

extension NSAttributedString {
    func withText(_ text: String) -> NSAttributedString {
        guard let mutableText = mutableCopy() as? NSMutableAttributedString else {
            return NSAttributedString(string: text)
        }
        mutableText.mutableString.setString(text)
        return mutableText
    }

    var font: UIFont? {
        attributes(at: 0, effectiveRange: nil)[.font] as? UIFont
    }

    func stringWithFontSize(_ size: CGFloat) -> NSAttributedString? {
        guard let font = font else { return nil }
        let newFont = font.withSize(size)

        let newString = NSMutableAttributedString(attributedString: self)
        newString.setAttributes([.font: newFont], range: string.nsRange)
        return newString
    }

    func withFont(_ font: UIFont) -> NSAttributedString {
        with(attribute: .font, value: font)
    }

    func withTextColor(_ color: UIColor) -> NSAttributedString {
        with(attribute: .foregroundColor, value: color)
    }

    func withFont(_ font: UIFont, forText text: String) -> NSAttributedString {
        let range = self.string.range(of: text)
        guard range.location != NSNotFound else {
            return self
        }

        return with(attribute: .font, value: font, in: range)
    }

    func with(attribute key: NSAttributedString.Key, value: Any, in range: NSRange? = nil) -> NSAttributedString {
        with(attributes: [key: value], in: range)
    }

    func with(attributes: [NSAttributedString.Key: Any], in range: NSRange? = nil) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: self)
        mutableString.addAttributes(attributes, range: range ?? string.nsRange)
        return mutableString
    }
}

extension String {
    var attributed: NSAttributedString {
        NSAttributedString(string: self)
    }

    var nsRange: NSRange {
        NSRange(startIndex..., in: self)
    }

    func range(of string: String) -> NSRange {
        (self as NSString).range(of: string)
    }
}

func + (lhs: NSAttributedString, rhs: NSAttributedString) -> NSAttributedString {
    let mutable = NSMutableAttributedString(attributedString: lhs)
    mutable.append(rhs)
    return mutable
}

func + (lhs: NSAttributedString, rhs: String) -> NSAttributedString {
    lhs + NSAttributedString(string: rhs)
}

func + (lhs: String, rhs: NSAttributedString) -> NSAttributedString {
    NSAttributedString(string: lhs) + rhs
}
#endif
