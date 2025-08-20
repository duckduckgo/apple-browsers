//
//  StringExtension.swift
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
import Punycode
import Network

public typealias RegEx = NSRegularExpression

public func regex(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
    return (try? NSRegularExpression(pattern: pattern, options: options))!
}

extension RegEx {
    // from https://stackoverflow.com/a/25717506/73479
    static let hostName = regex("^(((?!-)[A-Za-z0-9-]{1,63}(?<!-)\\.)*[A-Za-z0-9-]{2,63})$", .caseInsensitive)

    static let email = regex(#"[^\s]+@[^\s]+\.[^\s]+"#)

    static let mathExpression = regex(#"^[\s$]*([\d]+(\.[\d]+)?|\\.[\d]+)([\s]*[+\-*/][\s]*([\d]+(\.[\d]+)?|\\.[\d]+))*[\s$]*$"#)
}

// Use this instead of NSLocalizedString for strings that are not supposed to be translated
// swiftlint:disable:next identifier_name
public func NotLocalizedString(_ key: String, tableName: String? = nil, bundle: Bundle = Bundle.main, value: String = "", comment: String) -> String {
    return value
}

public extension String {

    static let localhost = "localhost"

    init(_ staticString: StaticString) {
        self = "\(staticString)"
    }

    // MARK: Prefix/Suffix

    func trimmingWhitespace() -> String {
        return trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func dropping(prefix: String) -> String {
        return hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }

    func dropping(suffix: String) -> String {
        return hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }

    func droppingWwwPrefix() -> String {
        self.dropping(prefix: "www.")
    }

    var hashedSuffixRange: PartialRangeFrom<String.Index>? {
        if let idx = self.firstIndex(of: "#") {
            return idx...
        } else if self.hasPrefix("about:"),
                  let range = self.range(of: "%23") {
            return range.lowerBound...
        }
        return nil
    }

    var hashedSuffix: String? {
        hashedSuffixRange.map { range in String(self[range]) }
    }

    func droppingHashedSuffix() -> String {
        if let range = self.hashedSuffixRange {
            guard range.lowerBound > self.startIndex else { return "" }
            return String(self[..<range.lowerBound])
        }
        return self
    }

    func autofillNormalized() -> String {
        let autofillCharacterSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)

        var normalizedString = self

        normalizedString = normalizedString.removingCharacters(in: autofillCharacterSet)
        normalizedString = normalizedString.folding(options: .diacriticInsensitive, locale: .current)
        normalizedString = normalizedString.localizedLowercase

        return normalizedString
    }

    // MARK: Sanitizing

    // clean-up file paths and email addresses
    func sanitized() -> String {
        // clean-up emails
        var message = self.replacing(RegEx.email, with: "<removed>")

        // find all the substring ranges looking like a file path
        let pathRanges = message.rangesOfFilePaths()

        let moduleNamePrefix = #fileID.split(separator: "/")[0] + "/"
        let bundleUrlPrefix = Bundle.main.bundleURL.absoluteString.dropping(suffix: "/")
        let bundlePathPrefix = Bundle.main.bundlePath.dropping(suffix: "/")
        let allowedExtensions = ["swift", "m", "mm", "c", "cpp", "js", "go", "o", "a", "framework", "lib", "dylib", "xib", "storyboard"]

        for range in pathRanges.reversed() {
            if message[range].hasPrefix(moduleNamePrefix) {
                // allow DuckDuckGo_Privacy_Browser/something…
            } else if let appUrlRange = message[range].range(of: bundleUrlPrefix),
                      appUrlRange.upperBound == range.upperBound || message[appUrlRange.upperBound] == "/" {
                // replace path to the app with just "DuckDuckGo.app"
                message.replaceSubrange(appUrlRange, with: "file:///DuckDuckGo.app")
            } else if let appPathRange = message[range].range(of: bundlePathPrefix),
                      appPathRange.upperBound == range.upperBound || message[appPathRange.upperBound] == "/" {
                // replace path to the app with just "DuckDuckGo.app"
                message.replaceSubrange(appPathRange, with: "DuckDuckGo.app")
            } else {
                let path = String(message[range])
                if allowedExtensions.contains(path.pathExtension) && !(path.hasPrefix("http://") || path.hasPrefix("https://")) {
                    // drop leading path components
                    message.replaceSubrange(range, with: path.lastPathComponent)
                } else {
                    // remove file path
                    message.replaceSubrange(range, with: "<removed>")
                }
            }
        }

        return message
    }

    /// Repeatedly removes percent-encoding until no more percent-escapes remain.
    /// - Returns: The fully unescaped string.
    func fullyRemovingPercentEncoding() -> String {
        var currentString = self
        var previousString: String

        repeat {
            previousString = currentString
            if let unescapedString = currentString.removingPercentEncoding {
                currentString = unescapedString
            }
        } while currentString != previousString

        return currentString
    }

    private enum FileRegex {
        //                           "(matching url/file/path/at/in..-like prefix)(not an end of expr)(=|:)  (open quote/brace)
        static let varStart = regex(#"(?:"# +
                                    #"ur[il]\b|"# +
                                    #"\b(?:config|input|output|temp|log|backup|resource)?file(?:ur[il]|name)?\b|"# +
                                    #"\b(?:absolute|relative|network|temp|url|uri|config|input|output|log|backup|resource)?(?:file|directory|dir)?path(?:ur[il])?\b|"# +
                                    #"\bin\b|\bfrom\b|\bat"# +
                                    #")[^.,;?!"'`\])}>]\s*[:= ]?\s*["'“`\[({<]?"#, .caseInsensitive)
        static let closingQuotes = [
            "\"": regex(#""[,.;:]?(?:\s|$)|$"#),
            "'": regex(#"'[,.;:]?(?:\s|$)|$"#),
            "“": regex(#"”[,.;:]?(?:\s|$)|$"#),
            "`": regex(#"`[,.;:]?(?:\s|$)|$"#),
            "[": regex(#"`[,.;:]?(?:\s|$)|$"#),
            "{": regex(#"`[,.;:]?(?:\s|$)|$"#),
            "(": regex(#"`[,.;:]?(?:\s|$)|$"#),
            "<": regex(#">[,.;:]?(?:\s|$)|$"#),
        ]
        static let leadingSlash = regex(#"[\s\[({<"'`“](\/)"#)
        static let trailingSlash = regex(#"[^\s](\/)"#)
        static let filePathBound = regex(#"([\p{L}\p{N}])[.,;:\])}>"”'`](?:\s\S+|$)"#)
        static let fileExt = regex(#"(\.(?:\w|\.){1,15})(?:\s|[.,;:\])}>"”'`](?:\s|$)|:\d+|$)"#)

        static let filePathStart = regex(#"/[\p{L}\p{N}._+]"#)
        static let urlScheme = regex(#"\w+:$"#)

        static let fileName = regex(#"([\p{L}\p{N}._+]+\.\w{1,15})(?:$|\s|[.,;:\])}>])"#)

        static let lineNumber = regex(#":\d+$"#)
        static let trailingSpecialCharacters = regex(#"[\s\.,;:\])}>"”'`]+$"#)

        static let moduleTypeName = regex(#"^\.*[A-Za-z_]*(?:DuckDuckGo|DataBroker|NetworkProtection|VPNProxy)[A-Za-z_]*\.(?:(?:[A-Z_]+[a-z_]+)+)$"#)
        static let swiftTypeName = regex(#"^\.*[A-Za-z_]+\.Type$"#)
    }

    // MARK: File Paths

    var pathExtension: String {
        (self as NSString).pathExtension
    }

    var lastPathComponent: String {
        (self as NSString).lastPathComponent
    }

    func appendingPathComponent(_ component: String) -> String {
        (self as NSString).appendingPathComponent(component)
    }

    func appendingPathExtension(_ pathExtension: String?) -> String {
        guard let pathExtension, !pathExtension.isEmpty else { return self }
        return self + "." + pathExtension
    }

    /// find all the substring ranges looking like a file path
    internal func rangesOfFilePaths() -> [Range<String.Index>] { // swiftlint:disable:this cyclomatic_complexity function_body_length
        var result = IndexSet()

        func dropLineNumberAndTrimSpaces(_ range: inout Range<String.Index>) {
            if let lineNumberRange = self.firstMatch(of: FileRegex.lineNumber, range: range)?.range(in: self) {
                range = range.lowerBound..<lineNumberRange.lowerBound
            }
            if let trailingSpacesRange = self.firstMatch(of: FileRegex.trailingSpecialCharacters, range: range)?.range(in: self) {
                range = range.lowerBound..<trailingSpacesRange.lowerBound
            }
        }

        var searchRange = startIndex..<endIndex
        // find all expressions like `file=filename.ext` and similar
        while !searchRange.isEmpty {
            // find path start
            guard let matchRange = self.firstMatch(of: FileRegex.varStart, range: searchRange)?.range(in: self) else { break }
            // adjust search range
            searchRange = matchRange.upperBound..<endIndex

            // possible quote or brace character index
            let openingCharIdx = self.index(before: matchRange.upperBound)
            var resultRange: Range<String.Index>
            var isCertainlyFilePath = false
            // if the path is enquoted – find trailing quote
            if FileRegex.closingQuotes.keys.contains(String(self[openingCharIdx])) {
                isCertainlyFilePath = self[matchRange].localizedCaseInsensitiveContains("file") || self[matchRange].localizedCaseInsensitiveContains("path") || self[matchRange].localizedCaseInsensitiveContains("directory")
                searchRange = matchRange.upperBound..<endIndex

                let endRegex = FileRegex.closingQuotes[String(self[openingCharIdx])]!
                resultRange = matchRange.upperBound..<(self.firstMatch(of: endRegex, range: searchRange)?.range(in: self)?.lowerBound ?? endIndex)

            } else {
                // the task becomes harder: there‘s no opening quote, apply some file path matching heuristics
                let pathEndIdx = self.findFilePathEnd(from: matchRange.upperBound)

                // is there something like `file included from /Volumes…`? try finding the leading slash
                if let leadingSlashIdx = self.firstMatch(of: FileRegex.leadingSlash, range: matchRange.upperBound..<pathEndIdx)?.range(in: self),
                   // should be no slashes in between
                   self.range(of: "/", range: matchRange.upperBound..<leadingSlashIdx.lowerBound) == nil {
                    resultRange = self.index(after: leadingSlashIdx.lowerBound)..<pathEndIdx
                } else {
                    resultRange = matchRange.upperBound..<pathEndIdx
                }
            }
            dropLineNumberAndTrimSpaces(&resultRange)
            searchRange = resultRange.upperBound..<endIndex

            // look backwards for a possible URL scheme
            if let schemeRange = self.firstMatch(of: FileRegex.urlScheme, range: startIndex..<resultRange.lowerBound)?.range(in: self) {
                resultRange = schemeRange.lowerBound..<resultRange.upperBound
            }

            // does it look like a valid file path?
            guard isCertainlyFilePath
                    || self[resultRange].contains("/")
                    || String(self[resultRange]).matches(FileRegex.fileName)
                    || String(self[resultRange]).matches(FileRegex.fileExt) else { continue }

            guard let pathRange = Range(NSRange(resultRange, in: self)), pathRange.count > 2 else { continue }
            // collect the result
            result.insert(integersIn: pathRange)
        }

        // next find all non-matched expressions looking like a file path
        // 1. find `/something` pattern
        searchRange = startIndex..<endIndex
        while !searchRange.isEmpty {
            // find absolute start
            guard let match = self.firstMatch(of: FileRegex.filePathStart, range: searchRange),
                  let matchIndices = Range(match.range), let matchRange = Range(match.range, in: self) else { break }
            guard !result.intersects(integersIn: matchIndices) else {
                // already matched
                searchRange = matchRange.upperBound..<endIndex
                continue
            }

            // 2. look backwards for possibly relative path first component start (limited by a whitespace or newline)
            var pathStartIdx = self.rangeOfCharacter(from: .whitespacesAndNewlines.union(.init(charactersIn: "[({<\"'`“=")), options: .backwards, range: startIndex..<matchRange.lowerBound)?.upperBound
                // otherwise take search range start as all the preceding characters are valid path characters
                ?? searchRange.lowerBound

            // 3. look backwards for a possible URL scheme
            if let schemeRange = self.firstMatch(of: FileRegex.urlScheme, range: pathStartIdx..<pathStartIdx)?.range(in: self) {
                pathStartIdx = schemeRange.lowerBound
            }
            // 4. heuristically find the end of the path
            let pathEndIdx = self.findFilePathEnd(from: pathStartIdx)
            var resultRange = pathStartIdx..<pathEndIdx
            searchRange = max(resultRange.upperBound, self.index(after: matchRange.lowerBound))..<endIndex

            dropLineNumberAndTrimSpaces(&resultRange)

            guard let pathRange = Range(NSRange(resultRange, in: self)), pathRange.count > 2 else { continue }
            // collect the result
            result.insert(integersIn: pathRange)
        }

        // next find all non-matched expressions looking like a file name (filename.ext)
        for match in FileRegex.fileName.matches(in: self, range: fullRange) {
            guard let matchIndices = Range(match.range(at: 1)), matchIndices.count > 2, var resultRange = Range(match.range, in: self),
                  !result.intersects(integersIn: matchIndices) else { continue /* already matched */ }

            dropLineNumberAndTrimSpaces(&resultRange)

            guard let pathRange = Range(NSRange(resultRange, in: self)), pathRange.count > 2 else { continue }
            // don‘t remove type names like _NSViewAnimator_DuckDuckGo_Privacy_Browser.MouseOverButton or Any.Type
            let fileName = String(self[resultRange])
            guard FileRegex.moduleTypeName.matches(in: fileName, range: fileName.fullRange).isEmpty,
                  FileRegex.swiftTypeName.matches(in: fileName, range: fileName.fullRange).isEmpty else { continue }
            // collect the result
            result.insert(integersIn: pathRange)
        }

        return result.rangeView.compactMap {
            guard let range = Range(NSRange($0), in: self) else {
                assertionFailure("Could not convert \($0) to Range in \(self)")
                return nil
            }
            return range
        }
    }

    private func findFilePathEnd(from pathStartIdx: String.Index) -> String.Index {
        // macOS file names can contain literally any Unicode character except `/` and newline with max length=255
        // but let‘s assume some general naming conventions:
        // - `filename.extension` followed by a word boundary [ ,.:;], not `/`, terminates the file path
        // - file/folder names should not contain trailing spaces
        //   although technically it‘s possible, but if the next path component starts with `/` we'll treat it as another path
        //
        // 1. find end of the line
        var lineEnd = self.rangeOfCharacter(from: .newlines, range: pathStartIdx..<endIndex)?.lowerBound ?? endIndex
        // next leading slash means another path start so set it as a current component boundary
        if let firstNonSlashCharacter = self.rangeOfCharacter(from: .init(charactersIn: "/").inverted, range: pathStartIdx..<lineEnd)?.lowerBound,
           let leadingSlashIdx = self.firstMatch(of: FileRegex.leadingSlash, range: firstNonSlashCharacter..<lineEnd)?.range(in: self)?.lowerBound {
            lineEnd = leadingSlashIdx
        }

        // 2. find a boundary of the path component
        var componentStart = pathStartIdx
        while componentStart < lineEnd {
            // max path component end (line end or after 255 characters)
            var pathCompEnd = self.distance(from: componentStart, to: lineEnd) < 255 ? lineEnd : self.index(componentStart, offsetBy: 255)
            let trailingSlashIdx = self.firstMatch(of: FileRegex.trailingSlash, range: componentStart..<pathCompEnd)?.range(in: self)?.upperBound
            // limit path component end by next trailing slash
            if let trailingSlashIdx {
                pathCompEnd = trailingSlashIdx
            }

            // find the most probable file name end (file with extension followed by a separator)
            let fileExtEnd = self.firstMatch(of: FileRegex.fileExt, range: componentStart..<pathCompEnd)?.range(at: 1, in: self)?.upperBound
            // find possible file path boundary (unicode letters followed by a separator)
            let filePathBound = self.firstMatch(of: FileRegex.filePathBound, range: componentStart..<pathCompEnd)?.range(at: 1, in: self)?.upperBound ?? fileExtEnd

            if let filePathBound {
                let boundary = min(filePathBound, fileExtEnd ?? filePathBound)
                return boundary

            } else if let trailingSlashIdx {
                componentStart = trailingSlashIdx
            } else {
                // this is the last component but we could not find its boundary – take max available
                return pathCompEnd
            }
        }
        return lineEnd
    }

    // MARK: Host name validation

    var isValidHost: Bool {
        return (isValidHostname || isValidIpHost) && !isMathFormula
    }

    private var isMathFormula: Bool {
        return matches(.mathExpression)
    }

    var isValidHostname: Bool {
        return matches(.hostName)
    }

    var isValidIpHost: Bool {
        if IPv4Address(self) != nil || IPv6Address(self) != nil {
            return true
        }
        return false
    }

    var isValidIpv4Host: Bool {
        guard let toIPv4Host, !toIPv4Host.isEmpty else { return false }
        return true
    }

    var toIPv4Host: String? {
        guard let ipv4 = IPv4Address(self) else { return nil }
        return [UInt8](ipv4.rawValue).map { String($0) }.joined(separator: ".")
    }

    // MARK: Regex

    func matches(_ regex: RegEx) -> Bool {
        let firstMatch = firstMatch(of: regex, options: .anchored)
        return firstMatch != nil
    }

    func matches(pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return false
        }
        return matches(regex)
    }

    func replacing(_ regex: RegEx, with replacement: String) -> String {
        regex.stringByReplacingMatches(in: self, range: self.fullRange, withTemplate: replacement)
    }

    func replacing(regex pattern: String, with replacement: String) -> String {
        self.replacing(regex(pattern), with: replacement)
    }

    func firstMatch(of regex: RegEx, options: RegEx.MatchingOptions = [], range: Range<String.Index>? = nil) -> NSTextCheckingResult? {
        let nsRange = range.map { NSRange($0, in: self) } ?? fullRange
        return regex.firstMatch(in: self, options: options, range: nsRange)
    }

}

public extension NSTextCheckingResult {

    func range(in string: String) -> Range<String.Index>? {
        let range = self.range
        guard range.location != NSNotFound, let matchRange = Range(self.range, in: string) else {
            assertionFailure("Could not convert match range \(range) to Range in \"\(string)\"")
            return nil
       }
       return matchRange
    }

    func range(at idx: Int, in string: String) -> Range<String.Index>? {
        guard numberOfRanges > idx else { return nil }
        let range = self.range(at: idx)
        guard range.location != NSNotFound else { return nil }
        guard let matchRange = Range(range, in: string) else {
            assertionFailure("Could not convert match range \(range) to Range in \"\(string)\"")
            return nil
       }
       return matchRange
    }

}

public extension StringProtocol {

    var utf8data: Data {
        data(using: .utf8)!
    }

    // MARK: NSRange

    var fullRange: NSRange {
        NSRange(startIndex..<endIndex, in: self)
    }

    func length() -> Int {
        self.fullRange.length
    }

    subscript (_ range: NSRange) -> Self.SubSequence? {
        Range(range, in: self).map { self[$0] }
    }

    // MARK: Percent encoding

    // Replaces plus symbols in a string with the space character encoding
    // Space UTF-8 encoding is 0x20
    func encodingPlusesAsSpaces() -> String {
        return replacingOccurrences(of: "+", with: "%20")
    }

    func percentEncoded(withAllowedCharacters allowedCharacters: CharacterSet) -> String {
        if let percentEncoded = self.addingPercentEncoding(withAllowedCharacters: allowedCharacters) {
            return percentEncoded
        }
        assertionFailure("Unexpected failure")
        return components(separatedBy: allowedCharacters.inverted).joined()
    }

    func removingCharacters(in set: CharacterSet) -> String {
        let filtered = unicodeScalars.filter { !set.contains($0) }
        return String(String.UnicodeScalarView(filtered))
    }

    // MARK: Punycode
    var punycodeEncodedHostname: String {
        return self.split(separator: ".")
            .map { String($0) }
            .map { $0.idnaEncoded ?? $0 }
            .joined(separator: ".")
    }

}

public extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool {
        if case .some(let wrapped) = self {
            return wrapped.isEmpty
        }
        return true
    }
}
