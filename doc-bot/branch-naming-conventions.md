---
alwaysApply: false
title: "Branch Naming Conventions & GitHub Flow"
description: "Branch naming conventions and GitHub Flow workflow guidelines for DuckDuckGo browser development including single-developer, multi-developer, hotfix, and release branch patterns"
keywords: ["GitHub Flow", "branch naming", "git workflow", "feature branches", "hotfix", "release branches", "version control", "collaboration"]
---

# Branch Naming Conventions & GitHub Flow

## Overview

DuckDuckGo browser development follows **GitHub Flow**, a streamlined branching strategy that maintains a single main branch with feature branches for development work.

**Reference**: [GitHub Flow Documentation](https://docs.github.com/en/get-started/using-github/github-flow)

## Core Principles

### Main Branch Strategy
- **Single source of truth**: All development branches from `main`
- **Always deployable**: `main` branch should always be in a deployable state
- **Merge via PR**: All changes merged back through Pull Requests (except releases)

### Branch Lifecycle
1. Create branch from `main`
2. Develop feature/fix on branch
3. Open Pull Request to `main`
4. Code review and testing
5. Merge to `main`
6. **Delete branch** immediately after merge

## Branch Naming Conventions

### Single Developer Features & Bugfixes

For work by a single developer:

```
Format:  <developer-name>/<feature-or-fix-name>
```

**Examples:**
- `alice/bookmark-sync`
- `alice/fix-bookmark-sync`
- `bob/credit-card-autofill`
- `charlie/fix-crash-on-startup`

**Guidelines:**
- Use kebab-case (lowercase with hyphens)
- Be descriptive but concise
- Include "fix-" prefix for bugfixes when helpful

### Multi-Developer Features

For collaborative features, use a two-stage approach:

#### 1. Base Feature Branch
```
Format:  <feature-name>
Example: autofill
```

#### 2. Individual Developer Branches
```
Format:  <feature-name>/<developer-name>/<sub-feature-name>
Example: autofill/alice/settings-list-changes
```

**Workflow:**
1. Create base feature branch from `main`
2. Developers create individual branches from base feature branch
3. Individual branches merge into base feature branch
4. Base feature branch merges into `main`

### Release Branches

Release branches follow semantic versioning:

```
Format:  release/<version>
Example: release/0.18.5
```

**Special Notes:**
- No developer name prefix
- Use semantic versioning format
- **Exception**: Release branches merge to `main` via local merge (not PR)
- Delete immediately after merge

### Hotfix Branches

Critical fixes for production issues:

```
Format:  hotfix/<version>
Example: hotfix/5.50.1
```

**Critical Requirements:**
- Use hotfix version number
- **MUST delete immediately after merge**
- Some tooling blocks subsequent hotfixes if previous hotfix branch exists
- Higher priority than regular releases

## Branch Management Best Practices

### ✅ DO

```bash
# Create feature branch from main
git checkout main
git pull origin main
git checkout -b alice/new-feature

# Meaningful commit messages
git commit -m "Add user authentication for secure vault"

# Keep branches up to date
git rebase main  # or git merge main

# Delete branch after merge
git branch -d alice/new-feature
git push origin --delete alice/new-feature
```

### ❌ DON'T

```bash
# Don't use unclear names
git checkout -b temp
git checkout -b fix
git checkout -b test-branch

# Don't leave merged branches
# (Clutters repository and can cause tooling issues)

# Don't work directly on main
git checkout main
# Edit files directly... ❌

# Don't use inconsistent naming
git checkout -b Alice/NewFeature  # Mixed case
git checkout -b alice_new_feature  # Underscore instead of hyphen
```

## Example Workflows

### Single Developer Feature

```bash
# Start new feature
git checkout main
git pull origin main
git checkout -b alice/password-manager

# Work on feature
# ... make changes ...
git add .
git commit -m "Implement password storage encryption"

# Push and create PR
git push origin alice/password-manager
# Create PR via GitHub UI

# After PR is merged, cleanup
git checkout main
git pull origin main
git branch -d alice/password-manager
git push origin --delete alice/password-manager
```

### Multi-Developer Feature

```bash
# Team lead creates base branch
git checkout main
git pull origin main
git checkout -b autofill
git push origin autofill

# Developer creates individual branch
git checkout autofill
git pull origin autofill
git checkout -b autofill/alice/credential-storage

# Work and merge to base feature branch
# ... development work ...
git push origin autofill/alice/credential-storage
# Create PR to merge into 'autofill' branch

# Eventually merge base feature to main
# Create PR from 'autofill' to 'main'
```

### Hotfix Workflow

```bash
# Create hotfix from main
git checkout main
git pull origin main
git checkout -b hotfix/5.50.1

# Fix critical issue
# ... emergency fixes ...
git commit -m "Fix critical security vulnerability"

# Merge and IMMEDIATELY delete
git push origin hotfix/5.50.1
# Create PR and merge immediately
git branch -d hotfix/5.50.1
git push origin --delete hotfix/5.50.1
```

## Common Patterns

### Feature Names

| Type | Good Examples | Bad Examples |
|------|---------------|--------------|
| **New Features** | `user-authentication`<br>`bookmark-sync`<br>`credit-card-autofill` | `feature`<br>`new-stuff`<br>`implementation` |
| **Bug Fixes** | `fix-memory-leak`<br>`fix-crash-on-startup`<br>`fix-bookmark-deletion` | `bug`<br>`fix`<br>`temp-fix` |
| **Improvements** | `improve-performance`<br>`optimize-database`<br>`refactor-networking` | `better`<br>`update`<br>`changes` |

### Developer Names

| Format | Example |
|--------|---------|
| **First name** | `alice/new-feature` |
| **GitHub username** | `alice-dev/new-feature` |
| **Consistent choice** | Pick one format and stick to it |

## Branch Protection & CI

### Main Branch Protection
- **Required status checks**: All CI must pass
- **Required reviews**: At least one approval required
- **No force pushes**: Maintain history integrity
- **Delete head branches**: Automatic cleanup after merge

### Feature Branch CI
- Shellcheck validation for script changes
- Unit tests must pass
- Build verification for iOS and macOS
- Code style validation

## Git Configuration Tips

### Helpful Git Settings

```bash
# Auto-delete tracking branches for deleted remotes
git config --global fetch.prune true

# Auto-setup upstream when pushing new branches
git config --global push.autoSetupRemote true

# Use more descriptive default branch names
git config --global init.defaultBranch main
```

### Useful Aliases

```bash
# Quick branch switching
git config --global alias.co checkout
git config --global alias.br branch

# Clean up merged branches
git config --global alias.cleanup "!git branch --merged | grep -v '\\*\\|main\\|develop' | xargs -n 1 git branch -d"

# Show branch with tracking info
git config --global alias.branches "branch -vv"
```

## Troubleshooting

### Branch Already Exists
```bash
# If remote branch exists but you don't have it locally
git fetch origin
git checkout -b alice/feature-name origin/alice/feature-name
```

### Hotfix Branch Blocked
```bash
# If hotfix creation is blocked, check for existing hotfix branches
git branch -r | grep hotfix
# Delete any remaining hotfix branches
git push origin --delete hotfix/previous-version
```

### Sync with Main
```bash
# Keep feature branch updated with main
git checkout alice/feature-name
git rebase main  # or: git merge main
git push origin alice/feature-name --force-with-lease  # if rebased
```

## Integration with Development Tools

### Xcode Integration
- Branch names appear in Xcode source control
- Use descriptive names for better identification
- Avoid special characters that might cause Xcode issues

### CI/CD Pipeline
- Branch names used in build artifacts
- Feature branches trigger full test suites
- Release branches trigger deployment pipelines

### Issue Tracking
- Reference GitHub issues in branch names when helpful:
  - `alice/fix-issue-1234-memory-leak`
  - `bob/feature-567-dark-mode`

---

Following these conventions ensures consistent, organized development workflow across the DuckDuckGo browser codebase and facilitates collaboration between team members. 