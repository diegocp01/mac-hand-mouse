# Source updates

Hand Mouse is distributed as source, so **Hand Mouse → Check for Updates…**
updates the Git checkout used by the installer. The installer records that checkout
in `~/Library/Application Support/Hand Mouse/source-checkout`; this local path is
never committed or sent anywhere.

The check runs `git fetch origin main` and compares the installed commit, checkout
commit, and `origin/main`. An update is offered only when the checkout:

- uses the official `diegocp01/mac-hand-mouse` GitHub remote;
- is on `main` with no tracked or untracked changes; and
- can fast-forward to `origin/main` without discarding commits.

After confirmation, the signed app pauses and starts its bundled helper. The helper
waits for the app to quit, runs `git pull --ff-only origin main`, invokes the normal
installer for the same destination, and reopens the app. The normal installer keeps
its rollback and signing-identity checks, so updates use the same certificate-backed
identity and retain Accessibility approval. The next launch reports success or a
local log path when an update failed.

The helper has a 30-second Git network timeout, disables interactive Git credential
prompts, and validates the checkout again after the app quits. It never resets,
stashes, deletes, or merges local work. If source was already pulled but installation
failed, the installed commit remains older than `origin/main`, so another check still
offers the installation.

Release archives do not include a mutable Git checkout. Install once from a clone to
enable this menu. Developers working on another branch should update manually after
committing their work.
