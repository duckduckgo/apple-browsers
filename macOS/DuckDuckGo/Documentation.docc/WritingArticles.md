# Writing Articles

Where an article belongs, and how articles in this catalog are structured.

## Overview

This catalog documents how the macOS app integrates its packages, and what is specific to macOS: the tab system, system extensions, menus and other app-level architecture. A package's own API belongs in that package's documentation catalog, such as the one in the VPN package, and articles here link to it rather than repeating it.

Write an article when a feature's architecture or integration isn't apparent from its code. Explain how the parts fit together and why; leave out what the code already shows.

## Structure

Follow the shape of <doc:TabManagement> and <doc:VPNNetworkProtection>:

- **Overview**: what the feature does in the macOS app, with a link to any package API it builds on.
- **Architecture**: how its components are organized, any process boundaries, and where it integrates with the rest of the app.
- **Key Components**: symbol links such as ``TabExtension``, or bare file names, rather than folder paths, which go stale as code moves.
- **Common Tasks**: short procedures, with file references instead of code blocks.

Keep code blocks rare; the whole catalog has only a handful. Never include secrets, credentials, internal URLs or endpoints.
