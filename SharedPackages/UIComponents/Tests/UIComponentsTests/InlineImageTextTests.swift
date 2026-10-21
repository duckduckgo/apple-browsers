//
//  InlineImageTextTests.swift
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

import Foundation
import Testing
@testable import UIComponents

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

@Suite("Inline image text parsing")
struct InlineImageTextTests {

    @Test("When replacement map is empty then parser returns the original text as a single item", .timeLimit(.minutes(1)))
    func whenReplacementMapIsEmptyThenParserReturnsSingleTextItem() {
        let items = inlineTextItems(from: "Hello world", replacing: [:])

        #expect(items.count == 1)
        guard case .text(let value, let isBold, let isItalic) = items[0] else {
            Issue.record("Expected a .text item")
            return
        }
        #expect(value == "Hello world")
        #expect(isBold == false)
        #expect(isItalic == false)
    }

    @Test("When input text is empty and replacements exist then parser returns a single empty text item", .timeLimit(.minutes(1)))
    func whenInputTextIsEmptyAndReplacementsExistThenParserReturnsSingleEmptyTextItem() {
        let items = inlineTextItems(from: "", replacing: ["[[chat]]": makeTestImage().withBaselineOffset(-2)])

        #expect(items.count == 1)
        guard case .text(let value, let isBold, let isItalic) = items[0] else {
            Issue.record("Expected a .text item")
            return
        }
        #expect(value.isEmpty)
        #expect(isBold == false)
        #expect(isItalic == false)
    }

    @Test("When text contains one placeholder then parser returns text-image-text segments", .timeLimit(.minutes(1)))
    func whenTextContainsOnePlaceholderThenParserReturnsTextImageText() {
        let expectedImage = makeTestImage()
        let items = inlineTextItems(from: "Try [[chat]] now", replacing: ["[[chat]]": expectedImage.withBaselineOffset(-2)])

        #expect(items.count == 3)
        guard case .text(let prefix, _, _) = items[0] else {
            Issue.record("Expected prefix text")
            return
        }
        #expect(prefix == "Try ")

        guard case .image(let middleImage, _) = items[1] else {
            Issue.record("Expected image segment")
            return
        }
        #expect(middleImage.platformImage === expectedImage)
        #expect(middleImage.baselineOffset == -2)

        guard case .text(let suffix, _, _) = items[2] else {
            Issue.record("Expected suffix text")
            return
        }
        #expect(suffix == " now")
    }

    @Test("When text contains multiple placeholders then each placeholder is replaced in order", .timeLimit(.minutes(1)))
    func whenTextContainsMultiplePlaceholdersThenEachPlaceholderIsReplacedInOrder() {
        let chatImage = makeTestImage()
        let fireImage = makeTestImage()
        let items = inlineTextItems(from: "A [[chat]] B [[fire]] C", replacing: [
            "[[chat]]": chatImage.withBaselineOffset(-2),
            "[[fire]]": fireImage.withBaselineOffset(-3)
        ])

        #expect(items.count == 5)
        guard case .text(let prefix, _, _) = items[0] else {
            Issue.record("Expected first segment to be prefix text")
            return
        }
        #expect(prefix == "A ")

        guard case .image(let firstImage, _) = items[1] else {
            Issue.record("Expected first placeholder to be image")
            return
        }
        #expect(firstImage.platformImage === chatImage)
        #expect(firstImage.baselineOffset == -2)

        guard case .text(let middleText, _, _) = items[2] else {
            Issue.record("Expected third segment to be middle text")
            return
        }
        #expect(middleText == " B ")

        guard case .image(let secondImage, _) = items[3] else {
            Issue.record("Expected second placeholder to be image")
            return
        }
        #expect(secondImage.platformImage === fireImage)
        #expect(secondImage.baselineOffset == -3)

        guard case .text(let suffix, _, _) = items[4] else {
            Issue.record("Expected final segment to be suffix text")
            return
        }
        #expect(suffix == " C")
    }

    @Test("When placeholders overlap at the same position then longest placeholder wins", .timeLimit(.minutes(1)))
    func whenPlaceholdersOverlapThenLongestPlaceholderWins() {
        let longImage = makeTestImage()
        let shortImage = makeTestImage()
        let replacements: [String: any InlinableImage] = [
            "abc": longImage.withBaselineOffset(-1),
            "ab": shortImage.withBaselineOffset(-2)
        ]

        let items = inlineTextItems(from: "abc is here", replacing: replacements)

        #expect(items.count == 2)
        guard case .image(let image, _) = items[0] else {
            Issue.record("Expected first segment to be image")
            return
        }
        #expect(image.platformImage === longImage)
        #expect(image.baselineOffset == -1)

        guard case .text(let suffix, _, _) = items[1] else {
            Issue.record("Expected second segment to be suffix text")
            return
        }
        #expect(suffix == " is here")
    }

    @Test("When two placeholders match at the same start index then the longer token is selected", .timeLimit(.minutes(1)))
    func whenPlaceholdersMatchAtSameIndexThenLongerTokenIsSelected() {
        let longImage = makeTestImage()
        let shortImage = makeTestImage()
        let replacements: [String: any InlinableImage] = [
            "abc": longImage.withBaselineOffset(-1),
            "ab": shortImage.withBaselineOffset(-2)
        ]

        let items = inlineTextItems(from: "abc", replacing: replacements)

        #expect(items.count == 1)
        guard case .image(let image, _) = items[0] else {
            Issue.record("Expected only segment to be image")
            return
        }
        #expect(image.platformImage === longImage)
        #expect(image.baselineOffset == -1)
    }

    @Test("When the same placeholder appears twice then both occurrences are replaced", .timeLimit(.minutes(1)))
    func whenSamePlaceholderAppearsTwiceThenBothOccurrencesAreReplaced() {
        let expectedImage = makeTestImage()
        let items = inlineTextItems(
            from: "A [[chat]] B [[chat]] C",
            replacing: ["[[chat]]": expectedImage.withBaselineOffset(-2)]
        )

        #expect(items.count == 5)
        guard case .text(let firstText, _, _) = items[0] else {
            Issue.record("Expected first segment to be text")
            return
        }
        #expect(firstText == "A ")

        guard case .image(let firstImage, _) = items[1] else {
            Issue.record("Expected second segment to be image")
            return
        }
        #expect(firstImage.platformImage === expectedImage)
        #expect(firstImage.baselineOffset == -2)

        guard case .text(let middleText, _, _) = items[2] else {
            Issue.record("Expected middle segment to be text")
            return
        }
        #expect(middleText == " B ")

        guard case .image(let secondImage, _) = items[3] else {
            Issue.record("Expected fourth segment to be image")
            return
        }
        #expect(secondImage.platformImage === expectedImage)
        #expect(secondImage.baselineOffset == -2)

        guard case .text(let lastText, _, _) = items[4] else {
            Issue.record("Expected final segment to be text")
            return
        }
        #expect(lastText == " C")
    }

    @Test("When attributed string is empty then parser returns one empty text item", .timeLimit(.minutes(1)))
    func whenAttributedStringIsEmptyThenParserReturnsSingleEmptyTextItem() {
        let items = inlineTextItems(from: NSAttributedString(string: ""))

        #expect(items.count == 1)
        guard case .text(let value, let isBold, let isItalic) = items[0] else {
            Issue.record("Expected a .text item")
            return
        }
        #expect(value.isEmpty)
        #expect(isBold == false)
        #expect(isItalic == false)
    }

    @Test("When attributed string has no attachments then parser returns attributed segment", .timeLimit(.minutes(1)))
    func whenAttributedStringHasNoAttachmentsThenParserReturnsAttributedSegment() {
        let attributedString = NSAttributedString(string: "Hello world")
        let items = inlineTextItems(from: attributedString)

        #expect(items.count == 1)
        guard case .attributed(let value) = items[0] else {
            Issue.record("Expected a .attributed item")
            return
        }
        #expect(value.string == "Hello world")
    }

    @Test("When attributed string includes image attachment then parser returns inline image with attachment baseline offset", .timeLimit(.minutes(1)))
    func whenAttributedStringHasImageAttachmentThenParserReturnsInlineImageSegment() {
        let message = NSMutableAttributedString(string: "before ")
        let attachment = NSTextAttachment()
        let expectedImage = makeTestImage()
        attachment.image = expectedImage
        attachment.bounds.origin.y = -3
        message.append(NSAttributedString(attachment: attachment))
        message.append(NSAttributedString(string: " after"))

        let items = inlineTextItems(from: message)

        #expect(items.count == 3)
        guard case .attributed(let prefix) = items[0] else {
            Issue.record("Expected first item to be attributed text")
            return
        }
        #expect(prefix.string == "before ")

        guard case .image(let image, _) = items[1] else {
            Issue.record("Expected second item to be image")
            return
        }
        #expect(image.baselineOffset == -3)
        #expect(image.platformImage === expectedImage)

        guard case .attributed(let suffix) = items[2] else {
            Issue.record("Expected third item to be attributed text")
            return
        }
        #expect(suffix.string == " after")
    }

    @available(iOS 18.0, *)
    @Test("When attachment run has foreground color then parser carries that color to image segment", .timeLimit(.minutes(1)))
    func whenAttachmentRunHasForegroundColorThenParserCarriesColorToImageSegment() {
        let message = NSMutableAttributedString(string: "before ")
        let attachment = NSTextAttachment()
        attachment.image = makeTestImage()
        attachment.bounds.origin.y = -2

#if os(iOS)
        let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.systemRed]
#else
        let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemRed]
#endif
        message.append(NSAttributedString(attachment: attachment, attributes: attributes))

        let items = inlineTextItems(from: message)

        #expect(items.count == 2)
        guard case .image(_, let color) = items[1] else {
            Issue.record("Expected second item to be image")
            return
        }
        #expect(color != nil)
    }

    @Test("When attributed string has several attachments then each attachment is converted to an image segment", .timeLimit(.minutes(1)))
    func whenAttributedStringHasSeveralAttachmentsThenEachAttachmentBecomesImageSegment() {
        let message = NSMutableAttributedString(string: "A ")

        let firstAttachment = NSTextAttachment()
        let firstExpectedImage = makeTestImage()
        firstAttachment.image = firstExpectedImage
        firstAttachment.bounds.origin.y = -1
        message.append(NSAttributedString(attachment: firstAttachment))

        message.append(NSAttributedString(string: " B "))

        let secondAttachment = NSTextAttachment()
        let secondExpectedImage = makeTestImage()
        secondAttachment.image = secondExpectedImage
        secondAttachment.bounds.origin.y = -4
        message.append(NSAttributedString(attachment: secondAttachment))

        message.append(NSAttributedString(string: " C"))

        let items = inlineTextItems(from: message)

        #expect(items.count == 5)
        guard case .attributed(let firstText) = items[0] else {
            Issue.record("Expected first segment to be attributed text")
            return
        }
        #expect(firstText.string == "A ")

        guard case .image(let firstImage, _) = items[1] else {
            Issue.record("Expected first attachment image segment")
            return
        }
        #expect(firstImage.baselineOffset == -1)
        #expect(firstImage.platformImage === firstExpectedImage)

        guard case .attributed(let middleText) = items[2] else {
            Issue.record("Expected middle segment to be attributed text")
            return
        }
        #expect(middleText.string == " B ")

        guard case .image(let secondImage, _) = items[3] else {
            Issue.record("Expected second attachment image segment")
            return
        }
        #expect(secondImage.baselineOffset == -4)
        #expect(secondImage.platformImage === secondExpectedImage)

        guard case .attributed(let lastText) = items[4] else {
            Issue.record("Expected final segment to be attributed text")
            return
        }
        #expect(lastText.string == " C")
    }

    @Test("When attachment has no image then parser falls back to attributed segment", .timeLimit(.minutes(1)))
    func whenAttachmentHasNoImageThenParserFallsBackToAttributedSegment() {
        let attachment = NSTextAttachment()
        let attributedString = NSAttributedString(attachment: attachment)

        let items = inlineTextItems(from: attributedString)

        #expect(items.count == 1)
        guard case .attributed(let value) = items[0] else {
            Issue.record("Expected a .attributed fallback item")
            return
        }
        #expect(value.length == 1)
    }

    private func makeTestImage() -> PlatformImageType {
#if os(iOS)
        let size = CGSize(width: 1, height: 1)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        UIColor.black.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIImage()
#elseif os(macOS)
        NSImage(size: NSSize(width: 1, height: 1))
#endif
    }

}
