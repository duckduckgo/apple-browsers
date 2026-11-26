//
//  CLlama.h
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

#ifndef CLLAMA_H
#define CLLAMA_H

#include "llama.h"

// The app never links llama.cpp. A linked framework loads at launch, and llama.cpp's needs a newer
// macOS than the app supports, so it is opened at runtime only where it can run. Calling the
// functions declared in llama.h directly would link them: go through `cllama_api` instead.
//
// Temporary, for the internal release and evals: the headers next to this file are copied by hand
// from the llama.cpp release, and the library is opened with dlopen. Both will be refactored before
// an external release.
//
// Every llama.cpp function the runtime uses. Their types come from llama.h, so a release that
// changes a signature fails to compile here rather than crashing at runtime.
#define CLLAMA_FUNCTIONS(X) \
    X(llama_backend_init) \
    X(llama_log_set) \
    X(llama_model_default_params) \
    X(llama_model_load_from_file) \
    X(llama_model_free) \
    X(llama_model_get_vocab) \
    X(llama_model_chat_template) \
    X(llama_context_default_params) \
    X(llama_init_from_model) \
    X(llama_free) \
    X(llama_n_ctx) \
    X(llama_n_batch) \
    X(llama_get_memory) \
    X(llama_memory_clear) \
    X(llama_memory_seq_pos_max) \
    X(llama_chat_apply_template) \
    X(llama_tokenize) \
    X(llama_token_to_piece) \
    X(llama_vocab_is_eog) \
    X(llama_vocab_n_tokens) \
    X(llama_batch_get_one) \
    X(llama_decode) \
    X(llama_sampler_chain_default_params) \
    X(llama_sampler_chain_init) \
    X(llama_sampler_chain_add) \
    X(llama_sampler_init_greedy) \
    X(llama_sampler_init_penalties) \
    X(llama_sampler_sample) \
    X(llama_sampler_free)

#define CLLAMA_FIELD(name) __typeof__(&name) _Nullable name;
typedef struct cllama_api {
    CLLAMA_FUNCTIONS(CLLAMA_FIELD)
} cllama_api;
#undef CLLAMA_FIELD

/// Opens the llama.cpp library at `path` and fills `api`. Returns NULL on success, or a message
/// naming what failed. The library stays open for the life of the process.
const char * _Nullable cllama_load(const char * _Nonnull path, cllama_api * _Nonnull api);

#endif
