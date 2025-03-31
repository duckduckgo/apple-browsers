//
//  CxaThrowSwapper.swift
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
//
// Inspired by kstenerud/KSCrash
// https://github.com/kstenerud/KSCrash
//
//  Copyright (c) 2019 YANDEX LLC. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//
//
// Inspired by facebook/fishhook
// https://github.com/facebook/fishhook
//
// Copyright (c) 2013, Facebook, Inc.
// All rights reserved.
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//   * Redistributions of source code must retain the above copyright notice,
//     this list of conditions and the following disclaimer.
//   * Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//   * Neither the name Facebook nor the names of its contributors may be used to
//     endorse or promote products derived from this software without specific
//     prior written permission.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
// FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
// DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
// SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
// CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
// OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Foundation
import Common
import MachO
import os.log

public typealias CxaThrowType = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, (@convention(c) (UnsafeMutableRawPointer?) -> Void)?) -> Void

public struct CxaThrowSwapper {

    fileprivate static var cxaThrowHandler: CxaThrowType?
    /// Swap `__cxa_throw` (the method called when C++ `throw MyCppException();` is executed) to collect the stack trace when the throw occurs.
    /// The original exception stack trace is stored in the current NSThread dictionary and used later in the `std::terminate` handler if the exception
    /// is not caught.
    public static func swapCxaThrow(with handler: CxaThrowType) {
        dispatchPrecondition(condition: .onQueue(.main))
        if cxaThrowHandler == nil {
            // iterate through mach headers loaded in memory and hook `__cxa_throw` method by overwriting its address.
            // When this function is first registered, it is called once for each image that is currently part of the process.
            _dyld_register_func_for_add_image(processMachHeader)
        }
        cxaThrowHandler = handler
    }

}

private enum ProcessingError: LocalizedError {
    case zeroSlide
    case imageMap

    var errorDescription: String? {
        switch self  {
        case .zeroSlide: "zero slide"
        case .imageMap: "could not load image map"
        }
    }
}

// _dyld_register_func_for_add_image callback
private func processMachHeader(_ header: UnsafePointer<mach_header>?, slide: Int) {
    do {
        try _processMachHeader(header.map(UnsafeRawPointer.init)?.assumingMemoryBound(to: mach_header_64.self), slide: slide)
    } catch {
        Logger.general.error("mach header \(header.debugDescription) processing error: \(error.localizedDescription)")
    }
}

private var cxxOriginalThrowFunctions = [UnsafeRawPointer: UnsafeRawPointer]()
private let indicesToSkip = [UInt32(INDIRECT_SYMBOL_ABS), INDIRECT_SYMBOL_LOCAL, INDIRECT_SYMBOL_LOCAL | UInt32(INDIRECT_SYMBOL_ABS)]

private func _processMachHeader(_ header: UnsafePointer<mach_header_64>?, slide: Int) throws {
    guard let header, slide != 0 else { throw ProcessingError.zeroSlide }
    let headerInfo = try Dl_info(header)
    Logger.general.debug("processing image \(String(cString: headerInfo.dli_fname)) (\(header.debugDescription), slide: \(slide)")

    // Lookup for the needed Mach-O loader commands and segments.
    guard let imageMap = ImageMap(header: header, slide: slide) else { throw ProcessingError.imageMap }

    try processSegment(imageMap.dataSegment)
    try processSegment(imageMap.dataConstSegment)

    func processSegment(_ segment: UnsafePointer<segment_command_64>?) throws {
        guard let segment else { return }
        let sections = segment.sections
        for section in sections.baseAddress!..<sections.baseAddress!.advanced(by: sections.count)
        where [S_LAZY_SYMBOL_POINTERS, S_NON_LAZY_SYMBOL_POINTERS].contains(section.pointee.type) {

            try section.pointee.indirectSymbolBindings(slide: slide)?.withTemporaryUnprotectedMemory { indirectSymbolBindings in
                guard let indirectSymbolIndices = section.pointee.indirectSymbolIndices(indirectSymtab: imageMap.indirectSymtab) else { return }
                // Iterate symbols in the section of the __DATA or __DATA_CONST segments.
                for i in 0..<section.pointee.count where indirectSymbolIndices.indices.contains(i) && indirectSymbolBindings.indices.contains(i) {
                    let symtabIndex = indirectSymbolIndices[i]
                    guard !indicesToSkip.contains(symtabIndex),
                          let symbolName = imageMap.symbolName(at: Int(symtabIndex)),
                          // There were crashes when the String(cString:) constructor was used for some C string pointers,
                          // which was probably caused by the `0`-terminating character lookup getting out of the `strtab` buffer bounds.
                          // This implementation matches the original KSCrash code using strcmp (bytewise compare); it doesn’t copy
                          // the original C String buffer and stops at the first non-matching byte.
                          // - First, we make sure the string is not empty and is longer than 1 byte.
                          symbolName[0] != 0, symbolName[1] != 0,
                          // Then we skip the first "_" character and compare.
                          strcmp(symbolName.advanced(by: 1), "__cxa_throw") == 0 else { continue }

                    let sectionInfo = try Dl_info(section)
                    Logger.general.debug("found \(String(cString: symbolName)): \(indirectSymbolBindings[i].debugDescription)")

                    // Now that the `__cxa_throw` symbol index is found, the magique begins:
                    // - We store the original function pointer from the section’s indirect symbol bindings table in the
                    //   `cxxOriginalThrowFunctions` dictionary by the base address of the section.
                    // - Since the `__cxa_throw` method is compiler-generated, it is present in each Mach-O binary loaded by the app.
                    //   That’s why we may need to hook it several times.
                    cxxOriginalThrowFunctions[UnsafeRawPointer(sectionInfo.dli_fbase)] = indirectSymbolBindings[i]
                    // - Now we overwrite the function pointer directly in the section memory with our custom handler,
                    //   so the next time `throw Exception();` is called, it will call our handler first. Then
                    //   we will find the original `__cxa_throw` method using the base address of the section that is
                    //   passed as the `tinfo` parameter into our custom handler.
                    indirectSymbolBindings[i] = unsafeBitCast(cxaThrowHandler as CxaThrowType, to: UnsafeRawPointer.self)

                    break
                }
            }
        }
    }
}

// `std::__cxa_throw` hook
private func cxaThrowHandler(thrownException: UnsafeMutableRawPointer?, tinfo: UnsafeMutableRawPointer?, dest: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?) {
    let kRequiredFrames = 2

    Logger.general.debug("handling __cxa_throw")
    CxaThrowSwapper.cxaThrowHandler?(thrownException, tinfo, dest)

    var backtraceArr = [UnsafeMutableRawPointer?](repeating: nil, count: kRequiredFrames)
    let count = backtrace(&backtraceArr, Int32(kRequiredFrames))

    if count >= kRequiredFrames {
        var info = Dl_info()
        if dladdr(backtraceArr[kRequiredFrames - 1], &info) != 0 {
            if let function = cxxOriginalThrowFunctions[info.dli_fbase] {
                Logger.general.debug("calling original __cxa_throw function at \(function.debugDescription)")
                let original = unsafeBitCast(function, to: CxaThrowType.self)
                original(thrownException, tinfo, dest)
            }
        }
    }
}
