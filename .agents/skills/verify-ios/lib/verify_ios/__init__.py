"""verify-ios library: drive the DuckDuckGo iOS app built from this worktree on its own simulator and prove behavior.

Layers: proof (throwaway, in the evidence folder) → steps / Proof context → Device → driver (XCUITest runner) + web
channel (the app's AutomationServer). See ../../SKILL.md.
"""
from .env import Busy, Failed, Unsupported  # noqa: F401
