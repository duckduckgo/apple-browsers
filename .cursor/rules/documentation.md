---
title: Documentation Principles
description: Core principles for organizing documentation by abstraction level and maintaining quality
keywords: [documentation, principles, best practices, abstraction levels, evergreen]
alwaysApply: false
---

# Documentation Principles

## Overview

This guide establishes core principles for creating and maintaining project documentation. It covers when to document, where documentation should live based on abstraction level, and how to write valuable documentation.

For DocC syntax and features, see [Apple's DocC Documentation](https://www.swift.org/documentation/docc/).

## When to Document

Document when introducing or changing:
- **Public APIs** - New protocols, methods, or significant behavior changes
- **Integration patterns** - How features connect or how to use packages
- **Complex modules** - Non-obvious architecture or usage patterns

## Where Documentation Lives

Documentation should live at the same abstraction level as the code it documents:

**Package Documentation** = Public protocol/API definitions, package architecture, reusable patterns
**App Documentation** = How the app integrates those packages, platform-specific patterns, app-specific protocols

## Good Documentation Practices

**Security and Privacy**: Document architectural concepts, flows, and how systems work. Never document actual secrets, API keys, endpoints, credentials, or any sensitive implementation details that could pose security risks.

✅ **Respect abstraction levels** - Package docs explain APIs, app docs explain integration
✅ **Link, don't duplicate** - App docs reference package APIs instead of copying them
✅ **Document stable interfaces** - Avoid ephemeral details (line numbers, paths, folder structures)
✅ **Provide code snippets for non-trivial API usage** - Show how to use complex APIs
✅ **Document for understanding, not existence** - Explain how it works and how to use it, not just that it exists

## Bad Documentation Practices

**Security and Privacy**: Never include actual API endpoints, authentication tokens, encryption keys, internal URLs, credentials, or any information that could compromise security or user privacy.

❌ **Mixing abstraction levels** - See: Respect abstraction levels
❌ **Duplicating content across documentation** - See: Link, don't duplicate
❌ **Documenting ephemeral details** - See: Document stable interfaces
❌ **Including trivial code snippets** - See: Provide code snippets for non-trivial API usage
❌ **Documenting just for existence sake** - See: Document for understanding, not existence
