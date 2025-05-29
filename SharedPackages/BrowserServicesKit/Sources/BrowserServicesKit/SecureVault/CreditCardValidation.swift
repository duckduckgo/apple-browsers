//
//  CreditCardValidation.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

public struct CreditCardValidation {

    public enum CardType {
        case amex
        case dinersClub
        case discover
        case mastercard
        case jcb
        case unionPay
        case visa

        case unknown

        public var displayName: String {
            switch self {
            case .amex:
                return "American Express"
            case .dinersClub:
                return "Diner's Club"
            case .discover:
                return "Discover"
            case .mastercard:
                return "MasterCard"
            case .jcb:
                return "JCB"
            case .unionPay:
                return "Union Pay"
            case .visa:
                return "Visa"
            case .unknown:
                return "Card"
            }
        }

        public var displayCardType: String {
            switch self {
            case .amex:
                return "amex"
            case .dinersClub:
                return "dinersClub"
            case .discover:
                return "discover"
            case .mastercard:
                return "masterCard"
            case .jcb:
                return "jcb"
            case .unionPay:
                return "unionPay"
            case .visa:
                return "visa"
            case .unknown:
                return "generic"
            }
        }

        static fileprivate var patterns: [(type: CardType, pattern: String)] {
            return [
                (.amex, "^3[47][0-9]{5,}$"),
                (.dinersClub, "^3(?:0[0-5]|[68][0-9])[0-9]{4,}$"),
                (.discover, "^6(?:011|5[0-9]{2})[0-9]{3,}$"),
                (.mastercard, "^(?:5[1-5][0-9]{2}|222[1-9]|22[3-9][0-9]|2[3-6][0-9]{2}|27[01][0-9]|2720)[0-9]{12}$"),
                (.jcb, "^(?:2131|1800|35[0-9]{3})[0-9]{3,}$"),
                (.unionPay, "^62[0-5]\\d{13,16}$"),
                (.visa, "^4[0-9]{6,}$")
            ]
        }
    }

    public var type: CardType {
        let card = CardType.patterns.first { type in
            NSPredicate(format: "SELF MATCHES %@", type.pattern).evaluate(with: cardNumber.numbers)
        }

        return card?.type ?? .unknown
    }

    public static func type(for cardNumber: String) -> CardType {
        return CreditCardValidation(cardNumber: cardNumber).type
    }

    public static func formattedCardNumber(_ number: String) -> String {
        let digitsOnly = number.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)

        let formatted: String

        // American Express: 4 digits, 6 digits, 5 digits (XXXX XXXXXX XXXXX)
        if digitsOnly.hasPrefix("34") || digitsOnly.hasPrefix("37") {
            formatted = digitsOnly.chunked(by: [4, 6, 5])
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        // All other cards: groups of 4 (XXXX XXXX XXXX XXXX)
        else {
            formatted = digitsOnly.chunked(by: 4)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }

        return formatted
    }

    public static func extractDigits(from formatted: String) -> String {
        return formatted.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
    }

    public static func hasMinimumLength(_ cardNumber: String) -> Bool {
        return cardNumber.count >= 8
    }

    public static func hasMaximumLength(_ cardNumber: String) -> Bool {
        return cardNumber.count <= 19
    }

    public static func isValidCardNumber(_ number: String) -> Bool {
        guard hasMinimumLength(number), hasMaximumLength(number) else {
            return false
        }
        // Implement Luhn algorithm (mod 10)
        var sum = 0
        let reversedDigits = number.reversed().map { Int(String($0)) ?? 0 }

        for (index, digit) in reversedDigits.enumerated() {
            if index % 2 == 1 {
                // Double every second digit
                let doubled = digit * 2
                // If doubled value is greater than 9, subtract 9
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += digit
            }
        }

        // Valid if sum is divisible by 10
        return sum % 10 == 0
    }

    private let cardNumber: String

    public init(cardNumber: String) {
        self.cardNumber = cardNumber
    }

}

fileprivate extension String {

    var numbers: String {
        let set = CharacterSet.decimalDigits.inverted
        let numbers = components(separatedBy: set)
        return numbers.joined(separator: "")
    }

    func chunked(by lengths: [Int]) -> [String] {
        var result: [String] = []
        var startIndex = self.startIndex

        for length in lengths {
            guard startIndex < self.endIndex else { break }

            let endIndex = self.index(startIndex, offsetBy: length, limitedBy: self.endIndex) ?? self.endIndex
            result.append(String(self[startIndex..<endIndex]))
            startIndex = endIndex
        }

        // If there are remaining characters, add them as the last chunk
        if startIndex < self.endIndex {
            result.append(String(self[startIndex..<self.endIndex]))
        }

        return result
    }

    func chunked(by length: Int) -> [String] {
        var result: [String] = []
        var startIndex = self.startIndex

        while startIndex < self.endIndex {
            let endIndex = self.index(startIndex, offsetBy: length, limitedBy: self.endIndex) ?? self.endIndex
            result.append(String(self[startIndex..<endIndex]))
            startIndex = endIndex
        }

        return result
    }

}
