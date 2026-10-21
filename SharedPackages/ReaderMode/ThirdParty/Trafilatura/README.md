# Trafilatura packaging

Run `./prepare.sh` before opening Xcode or resolving Swift packages. CI must run it before dependency resolution as well. Pass a local copy of the release ZIP as the first argument to prepare offline. The script verifies the same SHA-256 checksum in either case.

The Swift bindings are copied without modification from https://github.com/nchapman/trafilatura-swift at revision `2720048a7b71ea91efcc025fc3f6ed50da6a6d35`. The Apache 2.0 license is included. `Placeholder.swift` is omitted because it contains no declarations.

The generated binary comes from https://github.com/nchapman/trafilatura-rs/releases/tag/v0.5.0. Its pinned archive SHA-256 is `9f7830a54a45699d26e5293de5af0195296369ec55c0e2edd324f17b7ee147dd`.

Upstream places `module.modulemap` directly under every static XCFramework slice's `Headers` directory. Xcode copies this to `Products/include/module.modulemap`, colliding with DDGSyncCrypto's Clibsodium binary. Preparation moves both header files into `Headers/TrafilaturaFFI/`. The static libraries and XCFramework manifest remain byte-for-byte unchanged. Clang finds the namespaced module with its normal header search path.

`Vendor` is generated and ignored by Git. Remove this wrapper and return to the upstream package when upstream ships headers in a module-specific directory.
