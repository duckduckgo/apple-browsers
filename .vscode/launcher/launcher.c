//
//  launcher.c
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

// Main executable of the VSCode/Cursor host app (see make-host-app.sh).
// The host app is a copy of the Xcode-built app (Info.plist, entitlements, resources, embedded
// frameworks and login items); this launcher replaces its executable and runs the browser from
// the `DuckDuckGoBrowserDynamic` library built by `swift build`.

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

#ifndef DDG_DEFAULT_BROWSER_DYLIB
#define DDG_DEFAULT_BROWSER_DYLIB ""
#endif

int main(void) {
    const char *path = getenv("DDG_BROWSER_DYLIB");
    if (path == NULL || path[0] == '\0') {
        path = DDG_DEFAULT_BROWSER_DYLIB;
    }
    if (path[0] == '\0') {
        fprintf(stderr, "DDG_BROWSER_DYLIB is not set\n");
        return 1;
    }

    void *handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
    if (handle == NULL) {
        fprintf(stderr, "Failed to load %s: %s\n", path, dlerror());
        return 1;
    }

    void (*browserMain)(void) = (void (*)(void))dlsym(handle, "DuckDuckGoBrowserMain");
    if (browserMain == NULL) {
        fprintf(stderr, "DuckDuckGoBrowserMain not found in %s: %s\n", path, dlerror());
        return 1;
    }

    browserMain();
    return 0;
}
