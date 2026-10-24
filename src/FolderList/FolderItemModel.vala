/*
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * SPDX-FileCopyrightText: 2017-2026 elementary, Inc. (https://elementary.io)
 *
 * Authored by: Corentin Noël <corentin@elementary.io>
 */

public class Mail.FolderItemModel : Mail.SourceList.ExpandableItem {
    public signal void start_edit ();

    public Backend.Account account { get; construct; }

    private Camel.FolderInfo _folder_info;
    public Camel.FolderInfo folder_info {
        get {
            return _folder_info;
        }
        construct set {
            _folder_info = value;
            update_infos ();
        }
    }

    public bool is_special_folder { get; private set; default = true; }
    public int pos { get; private set; }

    private Cancellable cancellable;
    private string old_name;
    private bool emptying_trash;

    public FolderItemModel (Backend.Account account, Camel.FolderInfo folder_info) {
        Object (
            account: account,
            folder_info: folder_info
        );
    }

    construct {
        cancellable = new GLib.Cancellable ();
    }

    ~FolderItemModel () {
        cancellable.cancel ();
    }

    public override Gtk.Menu? get_context_menu () {
        var menu = new Gtk.Menu ();

        var refresh_item = new Gtk.MenuItem.with_label (_("Refresh folder"));
        refresh_item.activate.connect (() => refresh.begin ());
        menu.add (refresh_item);

        if ((Utils.get_full_folder_info_flags (account.service, folder_info) & Camel.FOLDER_TYPE_MASK) == Camel.FolderInfoFlags.TYPE_TRASH) {
            var empty_item = new Gtk.MenuItem.with_label (_("Empty Trash…")) {
                sensitive = !emptying_trash
            };
            empty_item.activate.connect (confirm_empty_trash);
            menu.add (new Gtk.SeparatorMenuItem ());
            menu.add (empty_item);
        }

        if (!is_special_folder) {
            var rename_item = new Gtk.MenuItem.with_label (_("Rename folder"));
            rename_item.activate.connect (() => start_edit ());
            menu.add (new Gtk.SeparatorMenuItem ());
            menu.add (rename_item);
        }

        menu.show_all ();

        return menu;
    }

    private void confirm_empty_trash () {
        if (emptying_trash) {
            return;
        }

        var dialog = new Granite.MessageDialog (
            _("Empty Trash for “%s”?").printf (account.service.display_name),
            _("All messages in this account’s Trash will be permanently deleted. You have 5 seconds to undo."),
            new ThemedIcon ("user-trash-full"),
            Gtk.ButtonsType.NONE
        ) {
            transient_for = ((Gtk.Application) GLib.Application.get_default ()).active_window,
            modal = true
        };
        dialog.add_button (_("Cancel"), Gtk.ResponseType.CANCEL);
        dialog.add_button (_("Empty Trash"), Gtk.ResponseType.ACCEPT).get_style_context ().add_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
        dialog.set_default_response (Gtk.ResponseType.CANCEL);
        dialog.response.connect ((response) => {
            dialog.destroy ();
            if (response == Gtk.ResponseType.ACCEPT && !emptying_trash) {
                empty_trash.begin ();
            }
        });
        dialog.present ();
    }

    private async void empty_trash () {
        emptying_trash = true;
        try {
            MainWindow? parent = null;
            foreach (var window in ((Gtk.Application) GLib.Application.get_default ()).get_windows ()) {
                if (window is MainWindow) {
                    parent = (MainWindow) window;
                    break;
                }
            }
            if (parent == null || !yield parent.offer_undo (_("Trash will be emptied"), 5)) {
                return;
            }
            var store = (Camel.Store) account.service;
            var folder = yield store.get_folder (folder_info.full_name, Camel.StoreGetFolderFlags.NONE, Priority.DEFAULT, cancellable);
            yield folder.refresh_info (Priority.DEFAULT, cancellable);
            yield TrashOperations.empty (folder, cancellable);
        } catch (Error e) {
            if (!(e is IOError.CANCELLED)) {
                MainWindow.send_error_message (_("Couldn’t empty Trash"), e.message, "user-trash-full");
            }
        } finally {
            emptying_trash = false;
        }
    }

    public void update_counts (int unread, int total) {
        if (unread < 0) {
            unread = folder_info.unread;
        }
        if (total < 0) {
            total = folder_info.total;
        }
        if (folder_info.unread == unread && folder_info.total == total) {
            return;
        }
        folder_info.unread = unread;
        folder_info.total = total;
        update_infos ();
    }

    private void update_infos () {
        name = old_name = folder_info.display_name;
        badge = folder_info.unread > 0 ? "%d".printf (folder_info.unread) : null;
        is_special_folder = true;

        var full_folder_info_flags = Utils.get_folder_display_flags (account.service, folder_info);
        switch (full_folder_info_flags & Camel.FOLDER_TYPE_MASK) {
            case Camel.FolderInfoFlags.TYPE_INBOX:
                icon = new ThemedIcon ("mail-inbox");
                pos = 1;
                break;
            case Camel.FolderInfoFlags.TYPE_DRAFTS:
                icon = new ThemedIcon ("mail-drafts");
                pos = 2;
                break;
            case Camel.FolderInfoFlags.TYPE_OUTBOX:
                icon = new ThemedIcon ("mail-outbox");
                pos = 3;
                break;
            case Camel.FolderInfoFlags.TYPE_SENT:
                icon = new ThemedIcon ("mail-sent");
                pos = 4;
                break;
            case Camel.FolderInfoFlags.TYPE_ARCHIVE:
                icon = new ThemedIcon ("mail-archive");
                pos = 5;
                badge = null;
                break;
            case Camel.FolderInfoFlags.TYPE_TRASH:
                icon = new ThemedIcon (folder_info.total == 0 ? "user-trash" : "user-trash-full");
                pos = 6;
                badge = null;
                break;
            case Camel.FolderInfoFlags.TYPE_JUNK:
                icon = new ThemedIcon ("edit-flag");
                pos = 7;
                break;
            default:
                icon = new ThemedIcon ("folder");
                pos = 8;
                is_special_folder = false;
                break;
        }

        tooltip = null;
        if ((folder_info.flags & Camel.FolderInfoFlags.VIRTUAL) != 0) {
            var folder_type = full_folder_info_flags & Camel.FOLDER_TYPE_MASK;
            if (folder_type == Camel.FolderInfoFlags.TYPE_TRASH || folder_type == Camel.FolderInfoFlags.TYPE_JUNK) {
                name = _("%s (Virtual)").printf (folder_info.display_name);
                tooltip = _("A virtual view of flagged messages, separate from the server folder.");
            }
        }

        if (!is_special_folder && editable != true) {
            editable = true;
            edited.connect (rename);
        } else if (is_special_folder) {
            editable = false;
            edited.disconnect (rename);
        }
    }

    private async void refresh () {
        var offlinestore = (Camel.Store)account.service;
        try {
            var folder = yield offlinestore.get_folder (folder_info.full_name, 0, GLib.Priority.DEFAULT, cancellable);
            yield folder.refresh_info (GLib.Priority.DEFAULT, cancellable);
        } catch (Error e) {
            critical (e.message);
        }
    }

    private void cancel_rename () {
        name = old_name;
        notify["name"].disconnect (cancel_rename);
    }

    private async void rename (string new_name) {
        if (new_name == old_name) {
            return;
        }

        if ("/" in new_name) {
            if (name == old_name) {
                notify["name"].connect (cancel_rename);
            } else {
                cancel_rename ();
            }

            MainWindow.send_error_message (
                _("Couldn't rename “%s”").printf (name),
                _("Folder names cannot contain “/”"),
                "folder"
            );

            return;
        }

        string[] split_full_name = folder_info.full_name.split_set ("/");
        split_full_name[split_full_name.length - 1] = new_name;
        var new_full_name = string.joinv ("/", split_full_name);

        var offlinestore = (Camel.Store)account.service;

        Camel.FolderInfo? new_folder_info = null;
        try {
            new_folder_info = yield offlinestore.get_folder_info (new_full_name, FAST, GLib.Priority.DEFAULT, cancellable);
        } catch (Error e) {
            warning (e.message);
        }

        if (new_folder_info != null) {
            if (name == old_name) {
                notify["name"].connect (cancel_rename);
            } else {
                cancel_rename ();
            }

            MainWindow.send_error_message (
                _("Couldn't rename “%s”").printf (name),
                _("A folder named “%s” already exists").printf (new_name),
                "folder"
            );

            return;
        }

        try {
            yield offlinestore.rename_folder (folder_info.full_name, new_full_name, GLib.Priority.DEFAULT, cancellable);
        } catch (Error e) {
            if (name == old_name) {
                notify["name"].connect (cancel_rename);
            } else {
                cancel_rename ();
            }

            MainWindow.send_error_message (
                _("Couldn't rename “%s”").printf (name),
                e.message,
                "folder"
            );
        }
    }
}
