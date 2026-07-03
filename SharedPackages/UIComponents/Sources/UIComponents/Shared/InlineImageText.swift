//
//  InlineImageText.swift
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

import SwiftUI
import Foundation

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Platform-native image type
#if os(iOS)
public typealias PlatformImageType = UIImage
#elseif os(macOS)
public typealias PlatformImageType = NSImage
#endif

/// Image abstraction that can be rendered inline inside `SwiftUI.Text` component.
public protocol InlinableImage {
    /// Platform-native image.
    var platformImage: PlatformImageType { get }
    /// Baseline offset applied when rendering the image inline with text.
    var baselineOffset: CGFloat { get }
}

private extension InlinableImage {
    var swiftUIImage: Image {
#if os(iOS)
        .init(uiImage: platformImage)
#elseif os(macOS)
        .init(nsImage: platformImage)
#endif
    }
}

/// Inlinable image wrapper with custom baseline offset.
public struct BaselineOffsetInlinableImage: InlinableImage {
    public let platformImage: PlatformImageType
    public let baselineOffset: CGFloat

    public init(platformImage: PlatformImageType, baselineOffset: CGFloat) {
        self.platformImage = platformImage
        self.baselineOffset = baselineOffset
    }
}

extension PlatformImageType: InlinableImage {
    public var platformImage: PlatformImageType { self }
    public var baselineOffset: CGFloat { 0 }
}

public extension PlatformImageType {
    /// Returns an inlinable image with a custom baseline offset.
    func withBaselineOffset(_ baselineOffset: CGFloat) -> BaselineOffsetInlinableImage {
        BaselineOffsetInlinableImage(platformImage: self, baselineOffset: baselineOffset)
    }
}

/// Inline text component used to build a single `SwiftUI.Text` with mixed text and image segments.
public enum InlineTextItem {
    /// A text segment with optional style flags.
    case text(String, isBold: Bool = false, isItalic: Bool = false)
    /// An attributed text segment.
    case attributed(NSAttributedString)
    /// An inline image segment.
    case image(any InlinableImage, color: Color? = nil)
}

public extension Text {
    /// Renders one inline segment used by placeholder-based text composition.
    ///
    /// Use this when building rich inline content where text and platform images
    /// are interleaved in a single SwiftUI `Text` value.
    init(_ textItem: InlineTextItem) {
        switch textItem {
        case .text(let value, let isBold, let isItalic):
            var text = Text(value)
            if isBold {
                text = text.bold()
            }
            if isItalic {
                text = text.italic()
            }
            self = text
        case .attributed(let attributedString):
            if #available(iOS 15, *) {
                self = Text(AttributedString(attributedString))
            } else {
                self = Text(attributedString.string)
            }
        case .image(let image, let color):
            var imageText = Text(image.swiftUIImage).baselineOffset(image.baselineOffset)
            if let color {
                imageText = imageText.foregroundColor(color)
            }
            self = imageText
        }
    }

    /// Builds a single `Text` value from an ordered sequence of inline segments.
    ///
    /// This is intended for localized strings where placeholders are replaced by
    /// inline icons while preserving text styling and baseline alignment.
    init(_ textItems: [InlineTextItem]) {
        self = Text(textItems.first ?? .text(""))
        for textItem in textItems.dropFirst() {
            // swiftlint:disable:next shorthand_operator
            self = self + Text(textItem)
        }
    }

    /// Creates text from an attributed string by splitting attachment runs into inline image segments.
    init(attributedStringWithAttachments attributedString: NSAttributedString) {
        self = Text(inlineTextItems(from: attributedString))
    }

    /// Creates text by replacing placeholders with inline images.
    init(_ text: String, replacing replacements: [String: any InlinableImage]) {
        self = Text(inlineTextItems(from: text, replacing: replacements))
    }

    /// Creates text by replacing one placeholder with one inline image.
    init(_ text: String, replacing placeholder: String, with image: any InlinableImage) {
        self.init(text, replacing: [placeholder: image])
    }
}

/// Parses a plain string into inline segments by replacing placeholder tokens with inline image items.
///
/// The nearest placeholder match is consumed first; when placeholders start at the same index,
/// the longer placeholder wins to avoid partial-token replacement.
func inlineTextItems(from text: String, replacing replacements: [String: any InlinableImage]) -> [InlineTextItem] {
    guard !replacements.isEmpty else {
        return [.text(text)]
    }

    var items = [InlineTextItem]()
    var remaining = text[...]

    while !remaining.isEmpty {
        // Find the left-most placeholder occurrence in the remaining slice.
        // If two placeholders start at the same position, prefer the longer token.
        let nearestMatch = replacements.compactMap { placeholder, image -> (Range<String.Index>, String, any InlinableImage)? in
            guard !placeholder.isEmpty, let range = remaining.range(of: placeholder) else {
                return nil
            }
            return (range, placeholder, image)
        }
        .min { lhs, rhs in
            if lhs.0.lowerBound == rhs.0.lowerBound {
                return lhs.1.count > rhs.1.count
            }
            return lhs.0.lowerBound < rhs.0.lowerBound
        }

        guard let (range, _, image) = nearestMatch else {
            // No more placeholders found; append the rest as plain text.
            items.append(.text(String(remaining)))
            break
        }

        // Emit text before the placeholder.
        let prefix = remaining[..<range.lowerBound]
        if !prefix.isEmpty {
            items.append(.text(String(prefix)))
        }

        // Emit inline image for resolved placeholder.
        items.append(.image(image))

        // Continue scanning after the consumed placeholder.
        remaining = remaining[range.upperBound...]
    }

    return items.isEmpty ? [.text(text)] : items
}

/// Parses an attributed string into inline segments, converting `NSTextAttachment` runs into inline images.
///
/// Non-attachment runs are preserved as `.attributed` segments. Attachments without an image are converted
/// into transparent placeholder images sized from attachment bounds, preserving inline spacing.
func inlineTextItems(from attributedString: NSAttributedString) -> [InlineTextItem] {
    guard attributedString.length > 0 else {
        return [.text("")]
    }

    var items = [InlineTextItem]()
    let fullRange = NSRange(location: 0, length: attributedString.length)

    // Enumerates contiguous runs where `.attachment` has the same value.
    // Each run becomes either `.image(...)` (for valid attachment image)
    // or `.attributed(...)` (for normal text or invalid/missing image attachment).
    attributedString.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
        guard let attachment = value as? NSTextAttachment else {
            items.append(.attributed(attributedString.attributedSubstring(from: range)))
            return
        }
        guard let image = attachment.platformImage ?? placeholderImage(for: attachment.bounds.size) else { return }

        // Preserve vertical alignment configured on the attachment itself.
        let attributes = attributedString.attributes(at: range.location, effectiveRange: nil)
        items.append(
            .image(
                image.withBaselineOffset(attachment.bounds.origin.y),
                color: foregroundColor(from: attributes)
            )
        )
    }

    return items
}

private func placeholderImage(for size: CGSize) -> PlatformImageType? {
    let normalizedSize = CGSize(width: max(size.width, 0), height: max(size.height, 1) )
    guard normalizedSize.width > 0, normalizedSize.height > 0 else { return nil }
#if os(iOS)
    let renderer = UIGraphicsImageRenderer(size: normalizedSize)
    return renderer.image { _ in
        UIColor.clear.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: normalizedSize)).fill()
    }
#elseif os(macOS)
    return NSImage(size: normalizedSize)
#endif
}

private func foregroundColor(from attributes: [NSAttributedString.Key: Any]) -> Color? {
#if os(iOS)
    if let foregroundColor = attributes[.foregroundColor] as? UIColor {
        return Color(foregroundColor)
    }
#elseif os(macOS)
    if let foregroundColor = attributes[.foregroundColor] as? NSColor {
        return Color(foregroundColor)
    }
#endif
    return nil
}

private extension NSTextAttachment {
    var platformImage: PlatformImageType? {
#if os(iOS)
        image
#elseif os(macOS)
        image
#endif
    }
}
