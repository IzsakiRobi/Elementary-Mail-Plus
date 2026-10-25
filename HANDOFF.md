# Development handoff — 2026-10-25

## Current state

Repository: https://github.com/IzsakiRobi/Elementary-Mail-Plus
Local checkout: `~/Projects/Elementary-Mail-Plus`. Work on `main`.
The user communicates in Hungarian. Source, identifiers and documentation are English.

There are two supported release assets: one native `.deb` and one cross-distribution `.flatpak`.
The mutable `v0.1` tag/release follows the approved source on `main`. Debian version remains `0.1-9`.
The user explicitly approved publishing the current source, replacing both assets and the tag, removing the old elementary 8 Flatpak, and leaving the release description empty. No README or release notes.

The user verified the current Flatpak on Fedora 45 and elementary OS 8.1: folders and message rendering work, and HiDPI text is sharp without the separate Mutter patch. The native `.deb` has worked on elementary OS 8.1 and 9. The retired elementary runtime 8.2 and 9 manifests are no longer needed.

## Workflow

- Keep checks minimal: compilation, package integrity and one focused diagnostic when needed. The user performs real-mail, notification and visual tests. Do not add screenshot sweeps or extensive functional tests.
- Preserve the original organization and formatting. Avoid explanatory comments. A short English section label such as `/* ----- Avatars ----- */` is enough when useful. Keep existing license headers.
- No README and no release descriptions or generated release notes.
- Install required tools when necessary. Use graphical Polkit (`pkexec`) for administrator authentication, never a terminal password prompt. Wait for the user if they are away.
- GitHub CLI web/device authentication is available. After reinstalling, authenticate again with `gh auth login --hostname github.com --git-protocol https --web`, then `gh auth setup-git`. Never request passwords, tokens or API keys in chat.
- Do not publish future experiments before the user's functional approval. The current replacement of `main` and `v0.1` was explicitly authorized; future work needs its own authorization.
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

Do not restore the abandoned `MessageDiskCache`, MHTML persistence, `MessagePrefetcher`, notification persistence or notification-center withdrawal experiments. Approved rollback baseline: `6072670`.

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
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo ../Elementary-Mail-Plus-builds/repo elementary-mail-plus_v0.1_amd64.flatpak io.github.IzsakiRobi.Elementary-Mail-Plus stable
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

Dependencies are in `debian/control`; also install `build-essential`. Package: `elementary-mail-plus`, version `0.1-9`.

```sh
DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -us -uc
```

`debian/rules` disables automatic functional tests and activates the app-specific AppArmor profile through `dh_apparmor`. Native dependencies include system EDS/GTK and `io.elementary.portals` from elementary's Noble repository. The package is rebuilt from the same approved source as the Flatpak, using native dependency versions and default Meson options.

## Publishing

Publish the approved commit to `main`, move mutable tag `v0.1` to that commit and update the existing GitHub release. Keep only:

- `elementary-mail-plus_0.1-9_amd64.deb`
- `elementary-mail-plus_v0.1_amd64.flatpak`

Remove the retired elementary8 and elementary9-named Flatpak assets. Clear the release body; do not generate notes. Upload the replacements before removing obsolete assets, and verify the resulting asset list and tag/main revisions. GitHub's automatically generated source archives remain available.
