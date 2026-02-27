//
//  PFMoveApplicationDummy.m
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
//  Dummy/stub implementation for App Store builds where moving to Applications folder is not needed
//  (App Store apps are already installed in /Applications).

#import "../../LetsMove/include/PFMoveApplication.h"

#import <Foundation/Foundation.h>

// Dummy implementation that does nothing for App Store builds
void PFMoveToApplicationsFolderIfNecessary(BOOL allowAlertSilencing) {
    // No-op for App Store builds - apps from the App Store are already in /Applications
    (void)allowAlertSilencing;
}

// Dummy implementation that always returns NO
BOOL PFMoveIsInProgress(void) {
    return NO;
}
