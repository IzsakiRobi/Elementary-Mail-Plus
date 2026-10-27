# GTK 4 / libadwaita port handoff — 2026-10-27

## Purpose and agreed scope

Continue Elementary Mail Plus on Fedora with a GTK 4 / libadwaita interface. The user approved a full port rather than a GTK 3 theme refresh. Keep Vala unless a concrete blocker justifies discussing another language.

**UI first, functionality second.** The user explicitly clarified that the first phase is the interface; migration of the existing mail features follows afterward. Start with representative local sample data and working UI navigation. Do not make IMAP integration, authentication or a working composer prerequisites for the initial UI milestone.

The stable GTK 3 application remains the reference and usable fallback. An intermediate version may have incomplete features. GTK 3 and GTK 4 widgets cannot be mixed in the same process; reuse backend logic gradually, rather than embedding old GTK 3 screens in the new application.

No GTK 4 implementation or port branch exists yet as of this document. This commit only adds the handoff. Do not mistake the current main branch for a partly working GTK 4 port.

## Repository and starting point

- Repository: https://github.com/IzsakiRobi/Elementary-Mail-Plus
- Suggested checkout: `~/Projects/Elementary-Mail-Plus`.
- Stable implementation baseline: commit `8931c25`, approved and published as `v0.3` before this documentation commit.
- Stable application ID: `io.github.IzsakiRobi.Elementary-Mail-Plus`.
- Stable source: GTK 3, Granite 6, libhandy, WebKitGTK 4.1, Camel/Evolution Data Server, libsoup 3, libsecret, folks.
- Read `HANDOFF.md` for the stable application's behavior and previous fixes. Its main-branch publishing instructions concern the stable release; the port should use a separate development branch.
- The user has another experimental mail project with an unsuitable starting point. Its repository and implementation have not been supplied here. No dependency on that project is assumed; port this application.

On Fedora, inspect the actual OS, session, available SDKs and library versions. The user described Fedora 45 / GNOME 51 as the intended environment; installed versions still need verification. This handoff was written on the elementary OS development installation, not on the future Fedora environment.

## First actions after cloning

```sh
mkdir -p ~/Projects
cd ~/Projects
git clone https://github.com/IzsakiRobi/Elementary-Mail-Plus.git
cd Elementary-Mail-Plus
cat HANDOFF-GTK4.md
cat HANDOFF.md
git status --short
git branch --all
```

If the checkout already exists, inspect and preserve its changes instead of cloning over it. Create a dedicated port branch after checking existing branches; `gtk4-libadwaita` is a suggested name. Do not reset main or move the stable release tag for port experiments.

Inventory Fedora's GTK 4, libadwaita, Vala, Meson, Ninja and gettext tooling. Later inventory WebKitGTK 6.0, EDS GTK 4 UI bindings, Camel, libportal GTK 4, folks and libsecret. Verify development-package names with Fedora's package manager rather than copying Ubuntu package names from `debian/control`.

Use an external build directory such as `~/Projects/Elementary-Mail-Plus-builds/gtk4-dev` and a separate local prefix. Native local development is enough initially: no RPM, Debian package or Flatpak release is required to review the UI.

The existing Meson configuration builds GTK 3. Its build commands will not produce a GTK 4 application until the port build configuration is implemented. Select a coherent GTK 4 source set; unported GTK 3 files may remain in Git without being linked into the port executable.

Give the experimental executable a separate development application ID, desktop entry and schema identity before running beside stable Mail Plus. The existing `application-id` option is a starting point, but inspect hardcoded paths and generated resources too. Keep settings/data separate; do not copy real credentials or silently migrate mail state during UI work.

## Milestone 1: UI prototype

Build a running GTK 4 / libadwaita application using local sample models. Treat this as a real interface prototype that will later receive backend data, not a screenshot mockup.

Preserve the recognizable three-column workflow while adopting native GNOME controls and spacing:

1. Account/folder sidebar, including nested folders and representative unread counts.
2. Conversation list with avatars, sender, subject/preview, time and unread state.
3. Conversation/message area with headers, expanded/collapsed message cards and an empty-selection state.

Use `Adw.Application`, `Adw.ApplicationWindow`, `Adw.HeaderBar` and suitable toolbar/split-view containers available in the selected libadwaita version. Evaluate `Adw.OverlaySplitView` / `Adw.NavigationSplitView` composition for narrower widths; do not lock in a complicated adaptive design before reviewing the desktop layout.

Use standard GNOME symbolic icons, system light/dark preferences and libadwaita styling. Remove the port's forced elementary stylesheet and MailPlus icon-theme selection. Preserve the app identity/icon where appropriate. Keep custom CSS small and scoped; do not reproduce the elementary stylesheet inside libadwaita.

Sample data should cover multiple accounts, nested folders, unread messages, a multi-message conversation, long subjects and empty states. Folder/conversation selection, navigation and basic expand/collapse should work with the sample data. Clearly distinguish sample content from a connected mailbox. Disable or omit server actions until implemented; do not pretend that a sample-data send/delete changes real mail.

For the first visual review, no network, EDS account access or real messages are necessary. A local HTML sample in WebKitGTK 6.0 may be introduced once the shell is reviewable; a placeholder is acceptable before that. Do not let the WebKit extension or composer migration block the first UI review.

Review the desktop layout, spacing, selection colors, dark mode and HiDPI with the user. A composer shell and preferences layout can follow within the UI phase, using native widgets and without sending or saving mail. Obtain the user's direction on the UI before migrating functionality.

## Milestone 2: connect read-only mail functionality

After UI approval, connect the existing mail models/backend incrementally: account discovery and authentication, folder loading, conversation loading, message rendering, unread state and avatars. Replace sample data through model boundaries rather than rewriting the UI around direct server calls.

The backend is reusable in substantial part, but is not entirely toolkit-independent:

- `Backend/Session.vala` uses `E.CredentialsPrompter` through the GTK 3 EDS UI library. Assess `libedataserverui4-1.0` and its installed Vala bindings; do not link both UI variants.
- `Backend/Account.vala` creates Granite error dialogs and accesses Gtk.Application. Move error presentation to the new UI boundary.
- `Backend/ContactManager.vala` owns Gtk.ListStore/EntryCompletion and Granite history checks. Separate address-book lookup from the GTK 3 completion UI.
- `Backend/MoveOperation.vala` binds a Gtk.Spinner. Replace this coupling with an appropriate GTK 4 UI binding or operation state.
- `InboxMonitor.vala` uses Granite dock-badge services. Preserve notification logic; adapt optional desktop badge integration separately without blocking the GNOME UI.

Start with read-only integration. Do not automatically send, move, expunge or delete real mail as a port test.

## Milestone 3: port interactions and composing

Restore approved behavior in small steps:

- Plain/Ctrl/Shift/Ctrl+Shift selection, keyboard navigation and bulk-action state.
- Folder ordering with a visible insertion line; order is local and restricted to siblings.
- Single/group message moves with a highlighted valid target and Undo.
- Folder creation, subtree-to-Trash and Empty Trash with the existing safeguards.
- Reply/forward, inline resources, attachments, editing and sending.
- Background send/draft save/delete, close confirmation, preferences and background startup.

Prefer GTK 4 model/view facilities (`Gio.ListStore`, selection models, `Gtk.ListView`, factories, and `Gtk.TreeListModel` where appropriate). Evaluate the existing model layer for reuse; do not mechanically carry the custom GTK 3 container and cell-renderer code into GTK 4.

GTK 4 event controllers, gestures, drag/drop and snapshot rendering replace several APIs used here. Preserve interaction semantics, but do not assume the current implementation can be copied unchanged.

## WebKit and dependency migration

This is later technical work, not a blocker for the first sample-data UI shell:

| Stable dependency / implementation | Port direction |
| --- | --- |
| GTK 3 + Granite 6 + libhandy | GTK 4 + libadwaita; remove Granite 6 and libhandy from the port process |
| `webkit2gtk-4.1` | `webkitgtk-6.0`, retaining libsoup 3 |
| `webkit2gtk-web-extension-4.1` | GTK 4-compatible web-process extension API and entry point; verify installed pkg-config/Vala bindings |
| `libedataserverui-1.2` | `libedataserverui4-1.0` where credentials UI is required |
| `libportal-gtk3` | `libportal-gtk4` |
| GtkContainer/custom virtualizing list, cell renderers | GTK 4 widgets/layout and model/view APIs |
| GtkMenu/GtkMenuItem | Menu models, actions and popovers |
| Legacy pointer events / GTK 3 drag targets | Event controllers, GtkDragSource/GtkDropTarget and content providers |

Inspect `src/WebView.vala` and `webkit-extension/{Main,MailPage}.vala` together. WebKitGTK 6.0 changes network-session ownership, extension names/initialization and removes deprecated APIs, including the old DOM API. Audit DOM use and migrate to JavaScript/JavaScriptCore as needed. Preserve the quote-export/clean-cloned-DOM behavior; do not assume a package-name substitution is sufficient.

The existing `main()` forces `WEBKIT_DISABLE_COMPOSITING_MODE=1`. Reassess that legacy choice on the new GTK 4/Fedora stack rather than copying it blindly. Keep WebKit sandboxing enabled and investigate actual graphics failures before adding driver or backend overrides.

## Stable behaviors to retain during migration

These are requirements for functional parity, not tasks to implement before the UI review:

- InboxMonitor keeps a strong reference and obtains Camel's canonical inbox with the second `get_folder(inbox.full_name, ...)` call. This is required for shared change signals, badges and notification withdrawal.
- NotificationTracker uses account/folder-scoped batches and withdraws notifications when their messages are read/deleted. Native elementary restart cleanup is not guaranteed; GNOME/Flatpak behavior needs user verification. Do not restore abandoned notification persistence experiments.
- IMAP real Trash/Junk configuration, virtual folder filtering and server folder names must remain correct. The stable Flatpak enables `imap-folder-setup`; the stable native build defaults to false. Decide the Fedora development setting deliberately.
- Folder deletion moves the entire hierarchy into real Trash. Message moves remain same-account and reject virtual/read-only/NOSELECT/current-source targets.
- All selected conversations remain visibly selected, even without focus. Mouse dragging moves mail; it must not unintentionally trigger swipe actions.
- Message cards stay opaque in expanded/focused states. Intentional collapsed-card stacking must not cause header bleed-through.
- Reply/forward preserves rendered formatting and CID resources, allows remote pictures, and adds no outer quote indent/bar. Remote pictures remain references, not a promise of complete offline embedding.
- Sending and draft sync hide the composer and hold the application while showing a readable activity status. Errors restore editable content. Keep Undo behavior and application hold/release balanced.
- Closing a changed composer offers Delete Draft / Edit / Save. Delete Draft removes an existing saved IMAP draft; Edit keeps editing; Save stores asynchronously. Escape keeps editing. The current delete helper uses Camel folder-expunge semantics for already DELETED messages; do not weaken its validation.
- Background startup must remain silent, including repeated `--background` / `-b` invocations. Read forwarded flags from `ApplicationCommandLine.get_options_dict()`. Ordinary activation opens the window.
- Keep bounded in-memory ready-view caching; do not restore MessageDiskCache, MHTML persistence or MessagePrefetcher.

## Packaging comes last

Keep the published v0.3 GTK 3 `.deb` and `.flatpak` intact while the port is experimental. Do not overwrite release assets or tags with the UI prototype.

The stable Flatpak uses GNOME Platform/SDK 49 from Flathub and bundles elementary GTK 3 components. Do not merely swap the app dependency while leaving that whole GTK 3 UI stack linked. Select an available GNOME SDK/runtime that supplies the chosen GTK 4/libadwaita/WebKit versions when packaging the port, and trim obsolete elementary UI modules.

Keep runtime and graphics dependencies on Flathub: the former elementary-origin runtime failed to resolve the needed graphics extension, producing blank WebKit views. Do not reintroduce that distribution problem.

Fedora-native development does not produce an elementary-compatible Debian binary. If a future GTK 4 Debian release is requested, establish its actual minimum OS/library support and build against that target. An RPM was discussed only as an optional future task; none is currently requested.

## Collaboration and verification

- Speak Hungarian with the user; keep source, identifiers and handoff documentation in English.
- Clean, organized code with minimal comments; short section comments are enough. Preserve license headers.
- The user does functional and visual testing. Keep agent checks to compilation, static checks and strictly necessary targeted diagnostics. No broad synthetic UI suites or real-mail mutation tests by default.
- Tools may be installed when needed. Administrator authentication must use graphical Polkit (`pkexec`), never a terminal sudo password. If the user takes time to respond, wait.
- Preserve accounts, keyring entries, contacts, cache and user settings. Never erase application data as a routine migration fix.
- No README, standalone changelog or release notes requested. Do not create them.
- Publish implementation or packages only with the user's authorization. This request authorizes publishing this handoff to main, not publishing unfinished port packages.

## Official references

Consult the documentation matching the actual installed SDK; online latest docs may describe newer APIs.

- [GTK 3 to GTK 4 migration](https://docs.gtk.org/gtk4/migrating-3to4.html)
- [Libhandy to libadwaita migration](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1.0/migrating-libhandy-1-4-to-libadwaita.html)
- [WebKitGTK GTK 4 migration guide source](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/gtk/migrating-to-webkitgtk-6.0.md)
- [Evolution Data Server library references](https://gnome.pages.gitlab.gnome.org/evolution-data-server/)
- [EDS GTK 4 UI reference](https://gnome.pages.gitlab.gnome.org/evolution-data-server/libedataserverui4/index.html)

## Suggested opening instruction for the Fedora chat

> Read HANDOFF-GTK4.md and HANDOFF.md in this checkout. We are starting the GTK 4/libadwaita port of Elementary Mail Plus on Fedora. Preserve stable main/v0.3, use a separate development branch and an isolated development app identity. First build the three-column GNOME UI with local sample data and working navigation; I will review its appearance before we migrate mail functionality. Keep automated checks minimal, use graphical Polkit for installation authentication, and do not build or publish release packages yet.
