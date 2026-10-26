# Development handoff — 2026-10-26

## Current state

Repository: https://github.com/IzsakiRobi/Elementary-Mail-Plus
Local checkout: `~/Projects/Elementary-Mail-Plus`. Work on `main`.
The user communicates in Hungarian. Source, identifiers and documentation are English.

There are two supported release assets: one native `.deb` and one cross-distribution `.flatpak`.
The current approved release is `v0.2` on `main`. Debian version is `0.2`. The user authorized publishing both new packages and deleting the old v0.1 release after the new release is uploaded.
The user approved folder management, standard multi-selection, message drag/drop and the final visual polish as version 0.2. Keep the release description empty. No README, standalone changelog or release notes.

The user verified the current Flatpak on Fedora 45 and elementary OS 8.1: folders and message rendering work, and HiDPI text is sharp without the separate Mutter patch. The native `.deb` has worked on elementary OS 8.1 and 9. The retired elementary runtime 8.2 and 9 manifests are no longer needed.

## Workflow

- Keep checks minimal: compilation/static code checks and only strictly necessary diagnostics. The user reiterated that functional/UI automation consumes too much of their usage budget; leave functional and visual testing to them. Do not run further synthetic UI suites by default.
- Preserve the original organization and formatting. Avoid explanatory comments. A short English section label such as `/* ----- Avatars ----- */` is enough when useful. Keep existing license headers.
- No README and no release descriptions or generated release notes.
- Install required tools when necessary. Use graphical Polkit (`pkexec`) for administrator authentication, never a terminal password prompt. Wait for the user if they are away.
- GitHub CLI web/device authentication is available. After reinstalling, authenticate again with `gh auth login --hostname github.com --git-protocol https --web`, then `gh auth setup-git`. Never request passwords, tokens or API keys in chat.
- Do not publish future experiments before the user's functional approval. Publishing version 0.2 on `main` is explicitly authorized; future work needs its own authorization.
- Closing Mail can leave it running. Stop the actual process before testing a replacement build. Check `flatpak ps` or `/proc/<pid>/root/.flatpak-info` to distinguish Flatpak from native processes.
- Do not erase accounts, keyring entries, contact photos or application data as a routine fix.

## Application

Based on elementary Mail 8.0.1: Vala, GTK 3, Granite 6, libhandy, Camel/Evolution Data Server, WebKitGTK 4.1, libsoup 3 and libsecret.

Application ID and executable: `io.github.IzsakiRobi.Elementary-Mail-Plus`.
Separate desktop files, icons, schema, gettext domain, AppArmor profile and backend paths allow coexistence with stock `io.elementary.mail`. Accounts come from the system EDS registry; credentials remain in the system keyring.

Implemented additions:

- Unread dock badge and new-mail notifications.
- Empty Trash with confirmation and five-second Undo; corrected permanent deletion from Trash.
- Conversation avatars, initials, star overlay and bounded avatar caches.
- Preferences for images, avatars, Logo.dev key management, background operation/autostart, read delay and send/delete Undo.
- Hidden-window reuse, persistent folder metadata, warm conversation lists and bounded in-memory message views.
- Live folder unread counts, elementary icons and GNOME account-settings integration outside Pantheon.

### Important invariants

`InboxMonitor` deliberately calls `get_inbox_folder()` and then `get_folder(inbox.full_name, ...)` to obtain the canonical folder from Camel's object bag. Keep the second call and the application's strong monitor reference; they are required for shared change tracking, notifications and badges.

Do not restore the abandoned `MessageDiskCache`, MHTML persistence, `MessagePrefetcher` or notification persistence experiments. Approved rollback baseline: `6072670`. The user explicitly authorized fresh notification-withdrawal research/code on 2026-10-25; the new in-memory implementation below does not restore the abandoned persistent designs.

`MessageViewCache` retains only document-ready views while the application remains alive. Keys use account/folder/UID and rebind to current message objects. Limits are 64 rows, 64 MiB estimated source cost and 8 MiB per message; these are not hard limits on WebKit's total memory. No custom persistent message archive exists across full shutdown. Camel's ordinary cache is unchanged.

### Avatars

Lookup order: system address book, Logo.dev with a libsecret-stored publishable key, Gravatar, initials. Do not restore Hunter automatically.

The image switch gates contact, cached and remote images; Show avatars separately hides the whole avatar. Clear removes/verifies the Logo.dev secret, clears RAM and `avatars-v3` PNGs, then refreshes avatars. A generation counter rejects late cache writes. Preferences refreshes the keyring lookup and masks an existing key. Normal GTK focus behavior is intentional.

Contact photos and Gravatar remain available after Clear. Apple/OpenAI logos were previously found in actual synced address-book PHOTO entries. Do not delete contacts as an avatar-cache fix. Tooltips identify the image source. Keyring entries can survive uninstall independently of Flatpak data.

### IMAP folders

The Flatpak enables the `imap-folder-setup` Meson option; native builds keep its default `false` and retain existing configured-folder behavior.

`Backend.Account.configure_folders()` uses Camel's initial-setup suggestions to fill missing real Trash/Junk paths in the application's cloned service settings. Existing nonempty paths are preserved. System EDS sources are not written. Camel prioritizes server SPECIAL-USE attributes and provides its own conventional-name fallback.

Real-folder configuration controls virtual-folder availability, folder flags, deletion destinations and Empty Trash. Do not infer destructive operations merely from a displayed folder name. Modern folder-info invalidation reloads the full tree and removes stale virtual rows from the sidebar/cache. Server folder names remain unchanged; the Flatpak adds no `(Virtual)` suffix. Virtual views remain available if no real destination is established.

The user needed to remove old local installations/data before their folder test succeeded; this does not establish that caches were the only cause. Do not automate that cleanup.

## Flatpak build and distribution

The single manifest is `io.github.IzsakiRobi.Elementary-Mail-Plus.json`:

- Runtime / SDK: `org.gnome.Platform` / `org.gnome.Sdk`, branch **49**, from Flathub.
- Application branch: `stable`.
- Freedesktop graphics base: **25.08**.
- Bundled components include EDS 3.56.2, Granite 6.2.0, GTK 3 elementary stylesheet 8.2.2 with all 11 accent variants, libportal 0.9.1, folks, libhandy and the private MailPlus icon theme. Sass tools are build-only and cleaned from the result.

```sh
flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak install --user flathub org.gnome.Sdk//49
flatpak-builder --user --force-clean --repo=../Elementary-Mail-Plus-builds/repo ../Elementary-Mail-Plus-builds/flatpak io.github.IzsakiRobi.Elementary-Mail-Plus.json
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo ../Elementary-Mail-Plus-builds/repo elementary-mail-plus_v0.2_amd64.flatpak io.github.IzsakiRobi.Elementary-Mail-Plus stable
```

Keep build directories outside the source tree. On this machine the reusable builder state is `~/Projects/Elementary-Mail-Plus-builds/state`. SDKs are build-time dependencies, not end-user requirements.

Distribute one ordinary `.flatpak`, without an installation/repair script or tar wrapper. Its runtime-repo must point to Flathub. Runtime and graphics dependencies then come from the same remote.

### Graphics finding

The old elementary runtime 9 required GL.default 25.08 from Flathub, while AppCenter did not provide it. Runtime 8.2 had the same issue with branch 24.08. Flatpak 1.18.4's remote related-ref lookup searches the runtime's origin remote, explaining the missed graphics dependency.

Without the matching GL extension, a minimal independent WebKit view reproduced `EGL_BAD_PARAMETER` and WebProcess termination. Installing the correct extension fixed both the probe and the user's Fedora rendering. DMA-BUF/compositing overrides did not fix missing drivers and are not shipped. Do not disable WebKit's sandbox or force X11.

The earlier elementary 9.1 / WebKit 2.54.0 stall is historical, not a blanket prohibition on newer WebKit. The approved GNOME build uses WebKit 2.54.1 and passed the independent HTML/Mail-extension probe and the user's Fedora/elementary tests.

An empty isolated Flatpak installation resolved the finished bundle and automatically scheduled GL.default 25.08 / 25.08-extra, VAAPI, codecs, locale and GNOME Platform 49, all from Flathub. The final transaction was declined before installing. Real-mail and appearance testing belongs to the user.

The separate Mutter cursor patch is a host compositor change, not part of Mail. The current Flatpak was confirmed sharp without it; do not reinstall that patch for this application.

## Native Debian build

Build against Ubuntu 24.04 Noble libraries for elementary OS 8.1 compatibility, even when developing on a newer OS. The current development host is elementary OS 8.1 / Noble, so a container is unnecessary here. Use a Noble container when the host is newer; do not package binaries linked against newer Ubuntu libraries for Noble.

Dependencies are in `debian/control`; also install `build-essential`. Package: `elementary-mail-plus`, version `0.2`.

```sh
DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -us -uc
```

`debian/rules` disables automatic functional tests and activates the app-specific AppArmor profile through `dh_apparmor`. Native dependencies include system EDS/GTK and `io.elementary.portals` from elementary's Noble repository. The package is rebuilt from the same approved source as the Flatpak, using native dependency versions and default Meson options.

## Publishing

Publish approved corrections to `main`, move the mutable `v0.2` tag to the approved commit and replace these two assets on the existing release, preserving an empty body:

- `elementary-mail-plus_v0.2_amd64.deb`
- `elementary-mail-plus_v0.2_amd64.flatpak`

Upload and verify the v0.2 assets before deleting the previous v0.1 release. Do not generate notes. Verify the final asset list and tag/main revisions. GitHub's automatically generated source archives remain available. The user also authorized updating the installed native application from the finished 0.2 Debian package, using graphical Polkit authentication.

## Version 0.2 functionality

- Folder drag ordering is local, persistent and restricted to siblings within one account. It uses a private drag target and a visible accent insertion line with a hollow end marker. It never reparents server folders.
- Account/sidebar controls create root folders; folder menus create subfolders. Names are validated, folders subscribed and leaf-only EDS child paths normalized.
- Folder deletion moves the complete folder, descendants and messages into the real server Trash via rename, after confirmation and five-second Undo. The user confirmed server support. System/read-only/virtual folders, recursive moves and unsupported hierarchy are protected; collisions receive numeric suffixes. Empty Trash validates descendants, empties/deletes child-first and retains the root.
- Tree reloads preserve selection/expansion/order and coalesce server changes. FolderPopover filters its source model and creates fresh view rows; do not apply GtkListBox filters to a bound model.
- Conversation selection supports plain click, Ctrl toggles, Shift ranges and Ctrl+Shift addition, including offscreen items. Selected rows keep the same accent-tinted CSS background regardless of focus. Multiple selection shows a count and enables existing bulk operations; reply and cross-account folder moves are disabled. A context click preserves an already selected group.
- Message drag/drop moves the dragged row or its selected group into a same-account physical writable folder. It rejects stale items, the current source, virtual/read-only/NOSELECT/busy targets and account headings. Captured model items use the existing asynchronous MoveOperation/error display/five-second Undo. No cross-account transfers.
- Mouse drag is reserved for moving messages; touch carousel swipes remain. Valid message targets use a light accent row fill without a border. Folder ordering has its own insertion indicator.
- Drag image: transparent HiDPI Cairo envelope, gray rounded outline, subtle paper/flap gradients and fold lines, independent of theme icon availability. User approved the final appearance.
- User verified folder ordering, selection, single/group message moves and the final visuals. Compile/static checks are sufficient for packaging; do not repeat functional/UI test suites.
- Camel failure-without-GError and GDK non-topmost-popup warnings were reported. Their runtime cause is unconfirmed. Folder loading already retries null FAST results without FAST. No warning suppression or speculative unrelated fix.

## Local development

Reusable native build: `~/Projects/Elementary-Mail-Plus-builds/native-check`; prefix: `~/Projects/Elementary-Mail-Plus-builds/local`. Chat-output launcher sets local schema/data paths and refuses to start while another Mail Plus instance is running.

The local WebKit executable needs its generated `.local` AppArmor profile loaded with graphical `pkexec apparmor_parser -r`; it is separate from the installed application's profile and lasts until reboot. Stop only the developer executable before replacing its build; `/proc/<pid>/exe` may have a ` (deleted)` suffix after installation.

Build packages outside the source tree. Native packaging uses a clean source copy in `~/Projects/Elementary-Mail-Plus-builds/deb-source-0.2`. Flatpak cache/state: `~/Projects/Elementary-Mail-Plus-builds/state`; GNOME build/repository: `flatpak-gnome` / `repo-gnome` in that same builds directory.

## Conversation card appearance fix — included in v0.2

- User reported gray/translucent expanded messages and overlapping headers after repeated collapse/expand. The elementary theme's `list row:focus` rule replaces the card background with translucent gray, allowing intentionally stacked collapsed cards to show through.
- MessageListItem now has a scoped message-list-item CSS class. Its card background stays opaque theme_base_color in focused/selected/backdrop states, preserving dark-theme adaptation and the existing collapsed stacking. No expansion logic, opacity animations on child controls or global list styling is changed.
- User verified the fix and authorized rebuilding both packages, replacing the existing v0.2 assets/tag on main and reinstalling the resulting Debian package locally. Keep the release body empty and the existing filenames; do not create another release. Compile/package integrity checks only.

## Notification withdrawal — included in v0.2

- On 2026-10-26 the user tested real mail in the local developer build and confirmed that reading immediately removes the notification from the elementary notification center. They approved publishing this implementation on main and replacing the existing v0.2 Flatpak/Debian assets under the same filenames, with no new release, README or release notes.
- InboxMonitor previously sent notifications but never withdrew them. Raw UID-only notification IDs could also collide across accounts. The new NotificationTracker records notified UID batches by account/inbox scope, generates scoped hashed IDs, and requests GIO withdrawal when all members become SEEN/DELETED or are explicitly removed. Account removal clears its tracked groups. Unknown/unread UIDs do not trigger withdrawal; marking unread again does not re-notify.
- Grouped notifications remain until their last relevant UID is resolved, without reposting partial summaries. Existing badge logic and the canonical Camel inbox object are unchanged. No persistent notification/mail database, panel-cache edit, desktop-specific dependency or extra Flatpak permission.
- Native compile, diff check and the actual tracker logic check passed. A synthetic notification on this elementary 8.1 system remained in the center after popup expiry and disappeared on same-process GIO withdrawal. A separate sender-exit/restart test confirmed that fresh-process GIO withdrawal does not remove the old FDO notification here; synthetic entries were cleaned afterward. No real email data was modified.
- Installed components: io.elementary.notifications 8.1.2+r539+pkg15~ubuntu8.1, indicator 7.1.1+r986+pkg37~ubuntu8.1, GLib 2.80.0-6ubuntu3.10. Exact installed indicator source was downloaded without installation and confirms CloseNotification removes the stored entry. Actual session exposes org.freedesktop.Notifications, not org.gtk.Notifications.
- Important limit: tracking and the native FDO string-to-server-ID mapping are in memory. This patch does not clean notifications from earlier app executions/reboots. Old UID-only notifications cannot reliably be mapped retroactively; manual one-time cleanup is appropriate. Do not claim the generic GIO restart guarantee works on this backend. Fedora/GNOME and Flatpak notification behavior still require user testing.
- Detailed Hungarian report, source links and synthetic probe scripts/logs are in this chat's outputs/notification-research.md and work/notification-research/. Keep the published package version 0.2 and names elementary-mail-plus_v0.2_amd64.deb / elementary-mail-plus_v0.2_amd64.flatpak. Real-mail tests need not be repeated during packaging.
