//
//  PageContextExtractionPixelHandlerTests.swift
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

import AIChat
import Testing

@testable import DuckDuckGo_Privacy_Browser

struct PageContextExtractionPixelHandlerTests {

    private func capture(_ outcome: PageContextExtractionOutcome) -> AIChatPixel? {
        var fired: AIChatPixel?
        let handler = PageContextExtractionPixelHandler(firePixel: { fired = $0 })
        handler.fire(outcome)
        return fired
    }

    @Test("success maps to the extraction-success pixel")
    func successMapsToSuccessPixel() {
        #expect(capture(.success)?.name == "aichat_page_context_extraction_success")
    }

    @Test("failure(emptyContent) maps to failed pixel with reason")
    func emptyContentMapsToFailedWithReason() {
        let pixel = capture(.failure(.emptyContent))
        #expect(pixel?.name == "aichat_page_context_extraction_failed")
        #expect(pixel?.parameters?["reason"] == "emptyContent")
    }

    @Test("failure(malformed) maps to failed pixel with reason")
    func malformedMapsToFailedWithReason() {
        #expect(capture(.failure(.malformed))?.parameters?["reason"] == "malformed")
    }

    @Test("prevented maps to prevented pixel with category")
    func preventedMapsToPreventedWithCategory() {
        let pixel = capture(.prevented("pdf"))
        #expect(pixel?.name == "aichat_page_context_extraction_prevented")
        #expect(pixel?.parameters?["category"] == "pdf")
    }
}
