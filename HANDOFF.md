# Development handoff — 2026-10-24

## Start here

Repository: https://github.com/IzsakiRobi/Elementary-Mail-Plus
Work on `main`. Read this file before changing code. The user communicates in Hungarian.
The approved application code is commit `6072670`; this handoff is a documentation-only follow-up.
The mutable `v0.1` tag/release currently contains the approved rollback: Debian package `0.1-6` and two Flatpak bundles. Do not infer the current implementation from older Debian changelog entries.

After reinstalling the computer:

```sh
git clone https://github.com/IzsakiRobi/Elementary-Mail-Plus.git ~/Projects/Elementary-Mail-Plus
cd ~/Projects/Elementary-Mail-Plus
```

GitHub authentication, installed dependencies, accounts, API keys and local caches are not part of the repository. Authenticate again using GitHub CLI web/device authentication if needed. Never request passwords or API keys in chat.

## User preferences and workflow

- Only perform necessary basic checks. The user repeatedly requested no extensive tests, videos, screenshot sweeps or repeated functional testing because these consume their budget. They test real mail, notifications and appearance themselves.
- Preserve the original code organization and formatting. Keep comments minimal; avoid explanatory comment blocks where none existed.
- No README. Keep release descriptions short and in English, describing additions over upstream elementary Mail.
- Install required tools when necessary. For administrator authentication, use a graphical Polkit prompt (`pkexec`), not a terminal password prompt. Wait patiently if the user is away.
- Closing the window can leave Mail running. Stop the actual application process before interpreting a restart or retesting a new build. `killall` can also kill a Flatpak process: its executable name alone does not prove it is native. Check `flatpak ps` and `/proc/<pid>/root/.flatpak-info` when necessary.
- Do not publish experimental changes before the user's functional approval. They authorized replacing the existing `v0.1` release/tag on `main`; do not assume that authorization applies to future experiments. A later `v0.2` was discussed for genuinely resolved future work.

## Current application

Based on elementary Mail 8.0.1, using Vala, GTK 3, Granite 6, libhandy, Camel/Evolution Data Server, WebKitGTK 4.1, libsoup 3 and libsecret.

Application ID / executable: `io.github.IzsakiRobi.Elementary-Mail-Plus`.
It has separate desktop files, icons, schema, gettext domain, AppArmor profile and backend data paths so it can coexist with distribution Mail (`io.elementary.mail`). It uses the system EDS mail accounts. Credentials remain in the system keyring; do not put them in source or release assets.

Implemented additions:

- Unread dock badge and new-mail notifications.
- Empty Trash with confirmation and fixed five-second Undo; correct permanent deletion from Trash.
- Avatars in the conversation list, initials fallback, star overlay, proper shadow padding and logo sizing.
- Avatar lookup: system address book, Logo.dev, Gravatar, initials. Hunter was removed because of image quality. Logo.dev publishable `pk_` key is stored with libsecret.
- Native preferences panel: remote images, showing avatars, remote logos, key entry, background operation/autostart, read delay and send/delete Undo controls. Signature editor remains focused above the preferences panel.
- Hidden MainWindow reuse when background operation is enabled; persistent folder-list metadata, warm conversation list and in-memory message views. Tooltip flicker and duplicate folders were fixed.
- Folder unread counters follow live Camel folder changes, including already opened folders.
- A small private `MailPlus` elementary icon theme is bundled with attribution/license. The original custom resource path `/io/elementary/mail/icons` is explicitly registered. GNOME/Adwaita/MoreWaita experiments were temporary previews, not the intended appearance.

Important notification detail: InboxMonitor deliberately calls `get_inbox_folder()` and then `get_folder(inbox.full_name, ...)`. The second call retrieves the canonical folder from the store's object bag. Removing it previously broke shared change tracking, notifications and badges. Application retains the monitor strongly. Keep this behavior.

## Approved rollback: do not reintroduce automatically

The latest user request was to remove the unsuccessful persistent/offline message-cache experiments. The user confirmed that the rollback fixed disappearing message content and restored normal behavior.

Removed from current source:

- `MessageDiskCache`, MHTML saving/restoring and all associated WebView/extension paths.
- `MessagePrefetcher`, body prefetch and timing instrumentation.
- Persistent notification tracking and attempts to withdraw notifications from elementary's notification center. The desktop-panel withdrawal attempt did not work in the user's test.

Retained:

- Avatar PNG disk cache (`avatars-v3`) and avatar RAM cache. Disk lookup now happens before checking network availability.
- `MessageViewCache` for already displayed messages while the application process remains alive. It retains only views whose document became ready, not unfinished requests. Keys use account/folder/UID and rebind to current MessageInfo objects.
- Window/list reuse and persistent folder-tree metadata. Camel's ordinary internal cache is untouched.

The view cache defaults to 64 rows / 64 MiB estimated source cost, with an 8 MiB per-message admission limit. This is not a hard cap on WebKit's total process memory.
There is intentionally no custom persistent message archive across full process shutdown. Do not advertise cold-start offline message/image caching as implemented. Old `messages-v1` files, if present on a previous machine, are unused. Purging packages does not necessarily remove user data; Flatpak `--delete-data` does.

The earlier measured Flatpak loads took about 0.53–0.78 seconds after expansion: roughly 0.42–0.64 seconds for MIME availability and 0.11–0.25 seconds for WebKit. These were a few user-triggered samples, not a benchmark or speed guarantee.

## Build and package

Use Ubuntu 24.04 (Noble) for compatible `.deb` artifacts, even when developing on elementary OS 9 Preview / Ubuntu 26.04. A rootless Podman Noble container was used previously. Do not just package a binary linked against 26.04 libraries for 24.04.
Build dependencies are declared in `debian/control`; install them plus `build-essential`. Typical commands inside a suitable build environment:

```sh
meson setup build --prefix=/usr
meson compile -C build
DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -us -uc
```

`debian/rules` disables automatic functional tests. It also uses `dh_apparmor` to activate the application-specific profile. The Debian package name is `elementary-mail-plus`. Its EDS/GTK dependencies come from Noble; `io.elementary.portals` comes from elementary's stable Noble repository. Build/dependency resolution was checked, but fresh elementary 8.1 end-to-end testing belongs to the user.

For Flatpak install `flatpak-builder`, the AppCenter remote, and the matching SDK. Keep these manifests distinct:

| Manifest | Runtime / SDK branch | Application branch |
| --- | --- | --- |
| `io.github.IzsakiRobi.Elementary-Mail-Plus.elementary8.json` | `io.elementary.Platform` / `io.elementary.Sdk` **8.2** | `elementary8` |
| `io.github.IzsakiRobi.Elementary-Mail-Plus.json` | same IDs, **9** | `stable` |

```sh
flatpak-builder --user --force-clean --repo=repo build-flatpak io.github.IzsakiRobi.Elementary-Mail-Plus.json
flatpak build-bundle --runtime-repo=https://flatpak.elementary.io/repo.flatpakrepo repo elementary-mail-plus.flatpak io.github.IzsakiRobi.Elementary-Mail-Plus stable
```

Keep build directories outside the source tree, or exclude them from directory sources when adapting this example. For the 8.2 variant use its manifest and the `elementary8` branch in the bundle command. SDKs are build-time tools, not end-user requirements.

### Critical Flatpak compatibility finding

Do not casually update branch **9** to **9.1**. On the user's EOS 9 Preview system, runtime 9.1 / WebKit 2.54.0 stalled even a minimal independent HTML view. The same test binary worked with runtime 9 / WebKit 2.52.5. Runtime selection fixed the missing entire mail body. This is a finding for that environment, not a universal claim about all WebKit 2.54 systems.
Both manifests need `--device=dri`; do not disable WebKit's sandbox or force X11 as a workaround.
The 8.2 runtime also needed `org.freedesktop.Platform.GL.default//24.08` installed from Flathub on the development machine. That graphics branch reported EOL; 8.2 was retained at the user's request for compatibility. Prefer branch 9 where appropriate. Runtime versions are distribution-independent, not Ubuntu 24.04/26.04 platforms.

The user's separate Mutter cursor-shape backport for EOS 8.1 is a host compositor patch. It is not part of this Mail repository and was not installed or bundled here. Do not assume it survives an OS reinstall.

## Next work

Start from the approved rollback and wait for the user's next request. Do not resume the abandoned disk-cache or notification-center withdrawal implementation just because older commits/changelogs mention it. If those are requested again, first isolate the actual failure with one targeted measurement; retain stable avatar and warm-view behavior. Build only the package formats the user asks for, and let them perform functional tests before publishing.
