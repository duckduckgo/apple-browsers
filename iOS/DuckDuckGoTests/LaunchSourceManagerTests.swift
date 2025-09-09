//
//  LaunchSourceManagerTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Testing
@testable import DuckDuckGo

final class LaunchSourceManagerTests {
    
    @Test("LaunchSourceManager initializes with standard launch source")
    func initializesWithStandardLaunchSource() {
        let manager = LaunchSourceManager()
        
        #expect(manager.source == .standard)
    }
    
    @Test("LaunchSourceManager sets source to URL")
    func setsSourceToURL() {
        let manager = LaunchSourceManager()
        
        manager.setSource(.URL)
        
        #expect(manager.source == .URL)
    }
    
    @Test("LaunchSourceManager sets source to shortcut")
    func setsSourceToShortcut() {
        let manager = LaunchSourceManager()
        
        manager.setSource(.shortcut)
        
        #expect(manager.source == .shortcut)
    }
    
    @Test("LaunchSourceManager sets source to notification")
    func setsSourceToNotification() {
        let manager = LaunchSourceManager()
        
        manager.setSource(.notification)
        
        #expect(manager.source == .notification)
    }
    
    @Test("LaunchSourceManager sets source to standard")
    func setsSourceToStandard() {
        let manager = LaunchSourceManager()
        manager.setSource(.URL)
        
        manager.setSource(.standard)
        
        #expect(manager.source == .standard)
    }
    
    @Test("LaunchSourceManager source can be changed multiple times")
    func sourceCanBeChangedMultipleTimes() {
        let manager = LaunchSourceManager()
        
        manager.setSource(.URL)
        #expect(manager.source == .URL)
        
        manager.setSource(.shortcut)
        #expect(manager.source == .shortcut)
        
        manager.setSource(.notification)
        #expect(manager.source == .notification)
        
        manager.setSource(.standard)
        #expect(manager.source == .standard)
    }
}
