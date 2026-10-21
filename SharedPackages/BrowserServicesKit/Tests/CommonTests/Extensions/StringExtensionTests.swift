//
//  StringExtensionTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import CryptoKit
import Foundation
import Testing

@testable import Common

final class StringExtensionTests {

    @Test("String normalization for autofill removes diacritics")
    func normalizeStringsForAutofillRemovesDiacritics() {
        let stringToNormalize = "Dáx Thê Dûck"
        let normalizedString = stringToNormalize.autofillNormalized()
        #expect(normalizedString == "daxtheduck")
    }

    @Test("String normalization for autofill removes whitespace")
    func normalizeStringsForAutofillRemovesWhitespace() {
        let stringToNormalize = "Dax The Duck"
        let normalizedString = stringToNormalize.autofillNormalized()
        #expect(normalizedString == "daxtheduck")
    }

    @Test("String normalization for autofill removes punctuation")
    func normalizeStringsForAutofillRemovesPunctuation() {
        let stringToNormalize = ",Dax+The_Duck."
        let normalizedString = stringToNormalize.autofillNormalized()
        #expect(normalizedString == "daxtheduck")
    }

    @Test("String normalization for autofill retains numbers")
    func normalizeStringsForAutofillRetainsNumbers() {
        let stringToNormalize = "Dax123"
        let normalizedString = stringToNormalize.autofillNormalized()
        #expect(normalizedString == "dax123")
    }

    @Test("String normalization for autofill leaves already normalized strings untouched")
    func normalizeStringsForAutofillLeavesNormalizedStringsUntouched() {
        let stringToNormalize = "firstmiddlelast"
        let normalizedString = stringToNormalize.autofillNormalized()
        #expect(normalizedString == "firstmiddlelast")
    }

    @Test("String normalization for autofill removes emoji")
    func normalizeStringsForAutofillRemovesEmoji() {
        let stringToNormalize = "Dax 🤔"
        let normalizedString = stringToNormalize.autofillNormalized()
        #expect(normalizedString == "dax")
    }

    @Test("Punycode encoding works correctly for domains with emojis")
    func punycodeEncodingForDomainsWithEmojis() {
        #expect("example.com".punycodeEncodedHostname == "example.com")
        #expect("Dax🤔.com".punycodeEncodedHostname == "xn--dax-v153b.com")
        #expect("🤔.com".punycodeEncodedHostname == "xn--wp9h.com")
    }

    @Test("Hashed suffix extraction works correctly")
    func hashedSuffixExtraction() {
        #expect("http://localhost:8084/#navlink".hashedSuffix == "#navlink")
        #expect("http://localhost:8084/#navlink#1".hashedSuffix == "#navlink#1")
        #expect("http://localhost:8084/#".hashedSuffix == "#")
        #expect("http://localhost:8084/##".hashedSuffix == "##")
        #expect("http://localhost:8084/".hashedSuffix == nil)
        #expect("http://localhost:8084".hashedSuffix == nil)
    }

    @Test("Dropping hashed suffix works correctly")
    func droppingHashedSuffix() {
        #expect("http://localhost:8084/#navlink".droppingHashedSuffix() == "http://localhost:8084/")
        #expect("http://localhost:8084/#navlink#1".droppingHashedSuffix() == "http://localhost:8084/")
        #expect("about://blank/#navlink1".url!.absoluteString.droppingHashedSuffix() == "about://blank/")
        #expect("about:blank/#navlink1".url!.absoluteString.droppingHashedSuffix() == "about:blank/")
        #expect("about:blank#navlink1".url!.absoluteString.droppingHashedSuffix() == "about:blank")
    }

    @Test("IPv4 host conversion works correctly")
    func ipv4HostConversion() {
        #expect("1.1.1.1".toIPv4Host == "1.1.1.1")
        #expect("1".toIPv4Host == "0.0.0.1")
        #expect("1.2".toIPv4Host == "1.0.0.2")
    }

    // MARK: - File paths detection

    @Test("String sanitization preserves ObjC class names and Swift type names")
    func sanitizationPreservesClassNames() {
        // Test case 1: ObjC class name with namespace
        #expect("""
        NSInvalidArgumentException: -[_NSViewAnimator_DuckDuckGo_Privacy_Browser.MouseOverButton copy:]: unrecognized selector sent to instance 0x104335890
        """.sanitized() == """
        NSInvalidArgumentException: -[_NSViewAnimator_DuckDuckGo_Privacy_Browser.MouseOverButton copy:]: unrecognized selector sent to instance 0x104335890
        """)

        // Test case 2: ObjC class name with XPC interface
        #expect("""
        NSInvalidArgumentException: -[..__NSXPCInterfaceProxy_DataBrokerProtection.XPCServerInterface copy:]: unrecognized selector sent to instance 0x104335890
        """.sanitized() == """
        NSInvalidArgumentException: -[..__NSXPCInterfaceProxy_DataBrokerProtection.XPCServerInterface copy:]: unrecognized selector sent to instance 0x104335890
        """)

        // Test case 3: Swift generic type name
        #expect("""
        NSInvalidArgumentException: -[_ContiguousArrayStorage<AlignmentID.Type> copy:]: unrecognized selector sent to instance 0x104335890
        """.sanitized() == """
        NSInvalidArgumentException: -[_ContiguousArrayStorage<AlignmentID.Type> copy:]: unrecognized selector sent to instance 0x104335890
        """)

        // Test case 4: Swift WritableKeyPath type
        #expect("""
        NSInvalidArgumentException: -[WritableKeyPath<DistributedNavigationDelegate, Published<Optional<Navigation>>> copy:]: unrecognized selector sent to instance 0x104335890
        """.sanitized() == """
        NSInvalidArgumentException: -[WritableKeyPath<DistributedNavigationDelegate, Published<Optional<Navigation>>> copy:]: unrecognized selector sent to instance 0x104335890
        """)

        // Test case 5: Swift generic AudioFile type
        #expect("""
        NSInvalidArgumentException: -[AudioFile<DistributedNavigationDelegate> copy:]: unrecognized selector sent to instance 0x104335890
        """.sanitized() == """
        NSInvalidArgumentException: -[AudioFile<DistributedNavigationDelegate> copy:]: unrecognized selector sent to instance 0x104335890
        """)

        // Test case 6: Swift complex generic SetStorage type
        #expect("""
        NSInvalidArgumentException: -[_SetStorage<ConduitBase<(domain: String, permissionType: PermissionType, decision: PersistedPermissionDecision), Never>> copy:]: unrecognized selector sent to instance 0x104335890
        """.sanitized() == """
        NSInvalidArgumentException: -[_SetStorage<ConduitBase<(domain: String, permissionType: PermissionType, decision: PersistedPermissionDecision), Never>> copy:]: unrecognized selector sent to instance 0x104335890
        """)

        // Test case 7: Swift complex generic ContiguousArrayStorage type
        #expect("""
        NSInvalidArgumentException: -[_ContiguousArrayStorage<(key: Key, data: AnimatablePair<AnimatableData, AnimatablePair<Float, AnimatableArray<AnimatableData>>>)> copy:]: unrecognized selector sent to instance 0x104335890
        """.sanitized() == """
        NSInvalidArgumentException: -[_ContiguousArrayStorage<(key: Key, data: AnimatablePair<AnimatableData, AnimatablePair<Float, AnimatableArray<AnimatableData>>>)> copy:]: unrecognized selector sent to instance 0x104335890
        """)

        // Test case 8: Swift complex function type
        #expect("""
        NSInvalidArgumentException: -[_ContiguousArrayStorage<(inout UnsafeMutablePointer<UInt8>, inout Optional<UnsafeMutablePointer<Optional<NSObject>>>, inout Optional<UnsafeMutablePointer<Any>>) -> ()> copy:]: unrecognized selector sent to instance 0x104335890
        """.sanitized() == """
        NSInvalidArgumentException: -[_ContiguousArrayStorage<(inout UnsafeMutablePointer<UInt8>, inout Optional<UnsafeMutablePointer<Optional<NSObject>>>, inout Optional<UnsafeMutablePointer<Any>>) -> ()> copy:]: unrecognized selector sent to instance 0x104335890
        """)
    }

    @Test("String sanitization removes user file paths")
    func sanitizationRemovesUserFilePaths() {
        let input = "Error in /var/filename.txt In file included from /Volumes/data/framework dir"
        let expected = "Error in <removed> In file included from <removed>"
        #expect(input.sanitized() == expected)
    }

    @Test("String sanitization preserves library names and trims source files")
    func sanitizationPreservesLibraryNamesAndTrimsSourceFiles() {
        #expect("""
        exception thrown in libobjc.A.dylib:
        UserScript/UserScript.swift:69: Fatal error: Failed to load JavaScript contentScope from \(Bundle.main.bundlePath)/Contents/Resources/ContentScopeScripts_ContentScopeScripts.bundle/Contents/Resources/contentScope.js
        """.sanitized() == """
        exception thrown in libobjc.A.dylib:
        UserScript.swift:69: Fatal error: Failed to load JavaScript contentScope from DuckDuckGo.app/Contents/Resources/ContentScopeScripts_ContentScopeScripts.bundle/Contents/Resources/contentScope.js
        """)

        // module name (Common) should stay
        // user file paths and names should be <removed>
        #expect("""
        Common/MainMenuActions.swift:686: Fatal error: 'try!' expression unexpectedly raised an error: Error Domain=NSCocoaErrorDomain Code=260 "The file “pa”th.txt” couldn’t be opened because there is no such file." UserInfo={NSFilePath=/non/exиstent file/pa”th.txt, NSUnderlyingError=0x600001a62580 {Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"}}
        Error Domain=NSCocoaErrorDomain Code=260 "The file “pa”th.txt” couldn’t be opened because there is no such file." UserInfo={NSFilePath=/non/exis“tent folder/pa”th.txt, NSUnderlyingError=0x60000057da10 {Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"}}
        """.sanitized() == """
        Common/MainMenuActions.swift:686: Fatal error: 'try!' expression unexpectedly raised an error: Error Domain=NSCocoaErrorDomain Code=260 "The file “<removed>” couldn’t be opened because there is no such file." UserInfo={NSFilePath=<removed>, NSUnderlyingError=0x600001a62580 {Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"}}
        Error Domain=NSCocoaErrorDomain Code=260 "The file “<removed>” couldn’t be opened because there is no such file." UserInfo={NSFilePath=<removed>, NSUnderlyingError=0x60000057da10 {Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"}}
        """)

        // library names should stay
        // app bundle URL should be trimmed to the bundle name
        #expect("""
        assertion failed: 23E224: libxpc.dylib + 202836 [C43D5322-9B69-37EE-B51E-45FDE5D81B5B]: 0x10000017
        assertion failed: 23E224: libxpc.dylib + 202836 [C43D5322-9B69-37EE-B51E-45FDE5D81B5B]: 0x10000017
        bundle \(Bundle.main.bundleURL.absoluteString)
        """.sanitized() == """
        assertion failed: 23E224: libxpc.dylib + 202836 [C43D5322-9B69-37EE-B51E-45FDE5D81B5B]: 0x10000017
        assertion failed: 23E224: libxpc.dylib + 202836 [C43D5322-9B69-37EE-B51E-45FDE5D81B5B]: 0x10000017
        bundle file:///DuckDuckGo.app/
        """)

        // source files should be trimmed to the file name
        // user file paths and names should be <removed>
        // email address should be <removed>
        #expect("""
        In file included from /Volumes/some мрé/directoy/3.33A.37.2/something else/dogs.txt,
         from /some/directoy/something else/dogs.txt, from ~/some/directoyr/3.33A.37.2/something else/dogs.txt, from /var/log/xyz/10032008. 10g,
        from /var/log/xyz/test.c: 29:
        Solution: please the file something.h has to be alone without others include, it has to be present in release letter,
        in order to be included in /var/log/xyz/test. automatically parse /the/file/name
        Other Note: send me an email at admin@duckduckgo.com!
        Also u can use these addresses: test-one@example.com
        test_two@example.com, test+three@example.com
        ,test@example-one.com
        test@example_one.com.
        The file something. must contain the somethinge.h and not the ecpfmbsd.h because it doesn't contain C operative c in /var/filename.c.
        """.sanitized() == """
        In file included from <removed>,
         from <removed>, from <removed>, from <removed>. 10g,
        from test.c: 29:
        Solution: please the file <removed> has to be alone without others include, it has to be present in release letter,
        in order to be included in <removed>. automatically parse <removed>
        Other Note: send me an email at <removed>
        Also u can use these addresses: <removed>
        <removed> <removed>
        <removed>
        <removed>
        The file something. must contain the <removed> and not the <removed> because it doesn't contain C operative c in filename.c.
        """)

        // no sensitive data hera
        #expect("""
        Error Domain=OSLogErrorDomain Code=-1 "issue with predicate: no such field: level" UserInfo={NSLocalizedDescription=issue with predicate: no such field: level}
        """.sanitized() == """
        Error Domain=OSLogErrorDomain Code=-1 "issue with predicate: no such field: level" UserInfo={NSLocalizedDescription=issue with predicate: no such field: level}
        """)

        // separate file name looking like a module name detection
        #expect("Could not read myFile.xcodeProj".sanitized() == "Could not read <removed>")
        #expect("ImFile.MyFile not found".sanitized() == "<removed> not found")
        #expect("Error: Any.TypeDocEx not found".sanitized() == "Error: <removed> not found")

        // no sensitive data hera
        #expect("The application has crashed".sanitized() == "The application has crashed")

        // user file path should be <removed>
        #expect("""
        std::filesystem::filesystem_error: /home/user/Documents/Confidential/Report.pdf (No such file or directory)
        """.sanitized() == """
        std::filesystem::filesystem_error: <removed> (No such file or directory)
        """)

        // user file path should be <removed>
        #expect("""
        Unable to read file: /Users/JohnDoe/Documents/Secret/passwords.txt
        """.sanitized() == """
        Unable to read file: <removed>
        """)

        // URL should be <removed>
        #expect("""
        Illegal character in path at index 16: http://example.com/path/to/file?user=johndoe&password=secret
        """.sanitized() == """
        Illegal character in path at index 16: <removed>
        """)

        // URL should be <removed>
        #expect("""
        Read timed out at api.example.com/192.168.1.1
        """.sanitized() == """
        Read timed out at <removed>
        """)

        // user file path should be <removed>
        #expect("""
        terminate called after throwing an instance of 'std::runtime_error'
        what():  failed to open file: /home/user/documents/confidential/report.txt
        """.sanitized() == """
        terminate called after throwing an instance of 'std::runtime_error'
        what():  failed to open file: <removed>
        """)

        #expect("""
        terminate called after throwing an instance of 'std::runtime_error'
        what():  failed to open configfile<conf>
        """.sanitized() == """
        terminate called after throwing an instance of 'std::runtime_error'
        what():  failed to open configfile<<removed>>
        """)

        // user file path should be <removed>
        #expect("""
        std::filesystem::filesystem_error: cannot copy file: Permission denied [/home/user/secret/config.json]
        """.sanitized() == """
        std::filesystem::filesystem_error: cannot copy file: Permission denied [<removed>]
        """)

        #expect("""
        std::filesystem::filesystem_error: cannot copy filepathuri[home]
        """.sanitized() == """
        std::filesystem::filesystem_error: cannot copy filepathuri[<removed>]
        """)

        // no sensitive data hera
        #expect("""
        terminate called after throwing an instance of 'std::out_of_range'
        what():  basic_string::substr: __pos (which is 10) > this->size() (which is 5)
        """.sanitized() == """
        terminate called after throwing an instance of 'std::out_of_range'
        what():  basic_string::substr: __pos (which is 10) > this->size() (which is 5)
        """)

        // user file path should be <removed>
        #expect("""
        *** Terminating app due to uncaught exception 'NSFileHandleOperationException', reason: '*** -[NSConcreteFileHandle readDataOfLength:]: No such file or directory ("/Users/johndoe/Library/Application Support/app/config.plist")'
        """.sanitized() == """
        *** Terminating app due to uncaught exception 'NSFileHandleOperationException', reason: '*** -[NSConcreteFileHandle readDataOfLength:]: No such file or directory ("<removed>")'
        """)

        // no sensitive data hera
        #expect("""
        *** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: '*** -[__NSArrayM objectAtIndex:]: index 10 beyond bounds [0 .. 5]'
        """.sanitized() == """
        *** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: '*** -[__NSArrayM objectAtIndex:]: index 10 beyond bounds [0 .. 5]'
        """)

        // user file path should be <removed>
        #expect("""
        Error Domain=NSCocoaErrorDomain Code=260 "The file “secrets.txt” couldn’t be opened because there is no such file." UserInfo={NSFilePath=/Users/janedoe/Documents/secrets.txt, NSUnderlyingError=0x600000c5e0 {Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"}}
        """.sanitized() == """
        Error Domain=NSCocoaErrorDomain Code=260 "The file “<removed>” couldn’t be opened because there is no such file." UserInfo={NSFilePath=<removed>, NSUnderlyingError=0x600000c5e0 {Error Domain=NSPOSIXErrorDomain Code=2 "No such file or directory"}}
        """)

        // source files should be trimmed to the file name
        #expect("""
        Fatal error: Index out of range: file /Users/johndoe/Projects/Example/Example/ViewController.swift, line 32
        """.sanitized() == """
        Fatal error: Index out of range: file ViewController.swift, line 32
        """)

        // URL should be <removed>
        #expect("""
        Error Domain=WebKitErrorDomain Code=102 "Frame load interrupted" UserInfo={NSErrorFailingURLKey=https://example.com/path/to/file?user=johndoe&password=secret, NSErrorFailingURLStringKey=https://example.com/path/to/file?user=johndoe&password=secret}
        """.sanitized() == """
        Error Domain=WebKitErrorDomain Code=102 "Frame load interrupted" UserInfo={NSErrorFailingURLKey=<removed>, NSErrorFailingURLStringKey=<removed>}
        """)

        // URL should be <removed>
        #expect("""
        Uncaught JavaScript exception: TypeError: null is not an object (evaluating 'document.getElementById('username').value') in https://example.com/login.js at line 23
        """.sanitized() == """
        Uncaught JavaScript exception: TypeError: null is not an object (evaluating 'document.getElementById('username').value') in <removed> at line 23
        """)

        // user file path should be <removed>
        #expect("""
        FileAlreadyExistsException: File '/home/johndoe/backup/archive.zip' already exists. Mentioned in '/home/johndoe/backup/logs.txt'
        """.sanitized() == """
        FileAlreadyExistsException: File '<removed>' already exists. Mentioned in '<removed>'
        """)

        // source files should be trimmed to the file name
        #expect("""
        terminate called after throwing an instance of 'std::invalid_argument'
        what():  stoi: no conversion at /home/user/projects/app/source.cpp:85
        """.sanitized() == """
        terminate called after throwing an instance of 'std::invalid_argument'
        what():  stoi: no conversion at source.cpp:85
        """)

        // path to the app should be trimmed to the bundle name
        #expect("""
        *** Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 'Could not load NIB in bundle: 'NSBundle <\(Bundle.main.bundleURL.path)> (loaded)' with name 'MainStoryboard''
        """.sanitized() == """
        *** Terminating app due to uncaught exception 'NSInternalInconsistencyException', reason: 'Could not load NIB in bundle: 'NSBundle <DuckDuckGo.app> (loaded)' with name 'MainStoryboard''
        """)

        // user file paths should be <removed>
        #expect("""
        *** Terminating app due to uncaught exception 'NSFileReadNoSuchFileError', reason: 'The file “data.json” couldn’t be opened because there is no such file in directory “/Users/janedoe/Library/Application Support/com.company.app”'
        """.sanitized() == """
        *** Terminating app due to uncaught exception 'NSFileReadNoSuchFileError', reason: 'The file “<removed>” couldn’t be opened because there is no such file in directory “<removed>”'
        """)
    }

    @Test("Valid hostnames are correctly identified")
    func validHostnamesAreCorrectlyIdentified() {
        let validHostnames = [
            "example.com",
            "subdomain.example.com",
            "my-host123",
            "localhost",
            "192.168.1.1", // Valid IP address
            "2001:0db8:85a3:0000:0000:8a2e:0370:7334" // Valid IPv6 address
        ]

        for hostname in validHostnames {
            #expect(hostname.isValidHost, "\(hostname) should be a valid host")
        }
    }

    @Test("Invalid hostnames are correctly identified")
    func invalidHostnamesAreCorrectlyIdentified() {
        let invalidHostnames = [
            "invalid_hostname", // Invalid character
            "-example.com", // Starts with a hyphen
            "example-.com", // Ends with a hyphen
            "example..com", // Consecutive dots
            "1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890.com", // Too long
            "example.com.", // Ends with a dot
            "3 + 5 * (2 - 1)", // Mathematical expression
            "16385-12228.72", // Other mathetmatical expression
            "example@domain.com", // Invalid character
            "2001:0db8:85a3:0000:0000:8a2e:0370:7334:1234" // Invalid IPv6 address
        ]

        for hostname in invalidHostnames {
            #expect(!hostname.isValidHost, "\(hostname) should NOT be a valid host")
        }
    }

    @Test("SHA256 hashing works correctly")
    func sha256Hashing() {
        let string = "Hello, World! This is a test string."
        let hash = string.sha256
        let expected = "3c2b805ab0038afb0629e1d598ae73e0caabb69de03e96762977d34e8ba428bf"
        let expectedSHA256 = SHA256.hash(data: Data(string.utf8)).map { String(format: "%02hhx", $0) }.joined()

        #expect(hash == expected)
        #expect(hash == expectedSHA256)
    }
}
