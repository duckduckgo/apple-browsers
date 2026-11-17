//
//  CLlama.c
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

#include "CLlama.h"
#include <dlfcn.h>
#include <stdio.h>

const char *cllama_load(const char *path, cllama_api *api) {
    static char message[512];

    // RTLD_LOCAL keeps ggml's symbols out of the global namespace, where they could clash with
    // another copy of ggml in the process.
    void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        const char *reason = dlerror();
        snprintf(message, sizeof message, "dlopen failed: %s", reason ? reason : "unknown");
        return message;
    }

#define CLLAMA_LOAD(name) \
    api->name = (__typeof__(api->name))dlsym(handle, #name); \
    if (!api->name) { \
        snprintf(message, sizeof message, "missing symbol: %s", #name); \
        return message; \
    }
    CLLAMA_FUNCTIONS(CLLAMA_LOAD)
#undef CLLAMA_LOAD

    return NULL;
}
