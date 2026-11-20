//
//  CallingSymbolTests.swift
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

#if DEBUG

@testable import Common
import Foundation
import Testing

struct CallingSymbolTests {

    // Lines as `Thread.callStackSymbols` prints them: the module column is padded and cut at 35 characters.
    @available(iOS 16, macOS 13, *)
    @Test("The symbol is read after the address, whatever the module column holds", .timeLimit(.minutes(1)), arguments: [
        ("4   DuckDuckGo.debug.dylib              0x0000000118a2815c $s10Navigation12currentURLvg + 684",
         "$s10Navigation12currentURLvg"),
        // A 36-character app name: the column is cut, so it no longer matches the executable name, and it has spaces.
        ("8   DuckDuckGo - verify-cmd-t-wrong-abc 0x0000000118a28438 $s10Navigation24isSameDocumentNavigationSbvg + 412",
         "$s10Navigation24isSameDocumentNavigationSbvg"),
        ("13  WebKit                              0x00000001b64d8b2c -[WKWebView _decidePolicy:] + 96",
         "-[WKWebView _decidePolicy:]"),
        // Frames without debug symbols show the module UUID; callers rely on getting it back.
        ("20  ???                                 0x00000001b7001074 8338D2BF-1C6B-3B01-B979-A50F6D272044 + 364",
         "8338D2BF-1C6B-3B01-B979-A50F6D272044"),
    ])
    func symbolFromLine(line: String, expected: String) {
        #expect(stackSymbol(fromCallStackLine: line) == expected)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A real stack line gives this function's symbol", .timeLimit(.minutes(1)))
    func symbolFromRealStack() {
        let line = Thread.callStackSymbols[0]
        #expect(stackSymbol(fromCallStackLine: line).contains("symbolFromRealStack"))
    }
}

#endif
