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

}
