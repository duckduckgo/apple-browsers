//
//  XCTestCompat.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

// Forwarders for XCTest symbols referenced by test bundles built with newer Xcode
// but missing from Xcode 13.4.1's XCTest. Compiled as module "XCUIAutomation".
import XCTest

extension XCUIElement {
    public func typeKey(_ key: XCUIKeyboardKey, modifierFlags: XCUIElement.KeyModifierFlags) {
        typeKey(key.rawValue, modifierFlags: modifierFlags)
    }
}

@_silgen_name("$s6XCTest8XCTIssueV4type18compactDescription08detailedE017sourceCodeContext15associatedError11attachments8severityACSo0B4TypeV_S2SSgSo09XCTSourcehI0Cs0K0_pSgSaySo13XCTAttachmentCGSo0B8SeverityVtcfC")
public func compatXCTIssueInit(type: XCTIssue.IssueType,
                               compactDescription: String,
                               detailedDescription: String?,
                               sourceCodeContext: XCTSourceCodeContext,
                               associatedError: Error?,
                               attachments: [XCTAttachment],
                               severity _: Int) -> XCTIssue {
    XCTIssue(type: type,
             compactDescription: compactDescription,
             detailedDescription: detailedDescription,
             sourceCodeContext: sourceCodeContext,
             associatedError: associatedError,
             attachments: attachments)
}
