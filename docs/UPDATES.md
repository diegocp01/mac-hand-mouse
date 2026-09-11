# Source updates

Hand Mouse is distributed as source, so **Hand Mouse → Check for Updates…**
installs the latest `origin/main` from the Git checkout used by the installer. The
installer records that checkout
in `~/Library/Application Support/Hand Mouse/source-checkout`; this local path is
never committed or sent anywhere.

The check runs `git fetch origin main` and compares the installed commit with
`origin/main`. The saved checkout must:

- use the official `diegocp01/mac-hand-mouse` GitHub remote; and
- remain available while the update runs.

After confirmation, the signed app pauses and starts its bundled helper. The helper
waits for the app to quit, fetches `origin/main`, and creates a temporary detached
worktree at that exact commit. It invokes the normal installer from that worktree,
removes it, and reopens the app. The normal installer keeps
its rollback and signing-identity checks, so updates use the same certificate-backed
identity and retain Accessibility approval. The next launch reports success or a
local log path when an update failed.

The helper has a 30-second Git network timeout, disables interactive Git credential
prompts, and validates the remote again after the app quits. It never checks out,
resets, stashes, deletes, or merges the developer's branch or local files. If installation
fails, the installed commit remains older than `origin/main`, so another check still offers it.

Release archives do not include a Git checkout. Install once from a clone to enable
this menu. Updates work while that clone is on another branch or has local changes.
