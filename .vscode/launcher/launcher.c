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
// Runs the browser from the `DuckDuckGoBrowserDynamic` library built by `swift build`:
// DDG_BROWSER_DYLIB if set, otherwise the swift build output next to the host app in macOS/.build.

#include <dlfcn.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// From macOS/.build/vscode-host/DuckDuckGo.app/Contents/MacOS.
static const char *defaultBrowserDylib = "../../../../DuckDuckGo/out/Products/Debug/libDuckDuckGoBrowserDynamic.dylib";

int main(void) {
    char defaultPath[PATH_MAX];
    const char *path = getenv("DDG_BROWSER_DYLIB");
    if (path == NULL || path[0] == '\0') {
        char executable[PATH_MAX];
        uint32_t size = sizeof(executable);
        if (_NSGetExecutablePath(executable, &size) != 0) {
            fprintf(stderr, "Executable path is too long\n");
            return 1;
        }
        char *lastSlash = strrchr(executable, '/');
        *lastSlash = '\0';
        snprintf(defaultPath, sizeof(defaultPath), "%s/%s", executable, defaultBrowserDylib);
        path = defaultPath;
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
