// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/*-
 * Copyright (c) 2017 elementary LLC. (https://elementary.io)
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 *
 * Authored by: Corentin Noël <corentin@elementary.io>
 */

public class Mail.AccountItemModel : Mail.SourceList.ExpandableItem, Mail.SourceListSortable {
    public Mail.Backend.Account account { get; construct; }

    public signal void loaded ();
    public signal void start_edit (Mail.SourceList.Item item);
    public signal void selection_requested (string path);

    private GLib.Cancellable connect_cancellable;
    private Gee.HashMap<string, FolderItemModel> folder_items;
    private AccountSavedState saved_state;
    private uint save_cache_id;
    private bool loading;
    private bool reload_again;
    private uint reload_id;
    private string? pending_selection;
    private Gee.HashMap<Camel.Folder, ulong?> folder_changed_handlers = new Gee.HashMap<Camel.Folder, ulong?> ();
    private unowned Camel.OfflineStore offlinestore;

    public AccountItemModel (Mail.Backend.Account account) {
        Object (account: account);
    }

    construct {
        visible = true;
        connect_cancellable = new GLib.Cancellable ();
        folder_items = new Gee.HashMap<string, FolderItemModel> ();
        saved_state = new AccountSavedState (account);
        saved_state.bind_with_expandable_item (this);

        offlinestore = (Camel.OfflineStore) account.service;
        name = offlinestore.display_name;
        restore_folders (saved_state.cached_folders, "", this);
        offlinestore.folder_created.connect (folder_created);
        offlinestore.folder_deleted.connect (folder_deleted);
        offlinestore.folder_info_stale.connect (reload_folders);
        offlinestore.folder_renamed.connect (folder_renamed);
        offlinestore.folder_opened.connect ((folder) => {
            Idle.add (() => {
                watch_folder (folder);
                return Source.REMOVE;
            });
        });
        foreach (var folder in offlinestore.dup_opened_folders ()) {
            watch_folder (folder);
        }
    }

    ~AccountItemModel () {
        connect_cancellable.cancel ();
        if (reload_id != 0) {
            Source.remove (reload_id);
        }
        foreach (var entry in folder_changed_handlers.entries) {
            entry.key.disconnect (entry.value);
        }
        folder_changed_handlers.clear ();
        if (save_cache_id != 0) {
            Source.remove (save_cache_id);
        }
    }

    private void watch_folder (Camel.Folder folder) {
        if (!folder_changed_handlers.has_key (folder)) {
            folder_changed_handlers[folder] = folder.changed.connect (() => {
                Idle.add (() => {
                    update_folder_counts (folder);
                    return Source.REMOVE;
                });
            });
        }
        update_folder_counts (folder);
    }

    private void update_folder_counts (Camel.Folder folder) {
        var item = folder_items[folder.full_name];
        if (item != null) {
            item.update_counts (folder.get_unread_message_count (), folder.get_message_count ());
            queue_save_folders ();
        }
    }

    private void update_open_folder_counts () {
        foreach (var folder in folder_changed_handlers.keys) {
            update_folder_counts (folder);
        }
    }

    public async void load () {
        if (loading) {
            reload_again = true;
            return;
        }
        loading = true;
        debug ("Folder list load started");
        try {
            try {
                yield account.configure_folders (connect_cancellable);
            } catch (Error e) {
                if (e is IOError.CANCELLED) {
                    throw e;
                }
                warning ("Unable to configure IMAP folders: %s", e.message);
            }
            var folderinfo = yield offlinestore.get_folder_info (null,
                Camel.StoreGetFolderInfoFlags.FAST | Camel.StoreGetFolderInfoFlags.RECURSIVE,
                GLib.Priority.DEFAULT, connect_cancellable);
            if (folderinfo == null) {
                folderinfo = yield offlinestore.get_folder_info (null, Camel.StoreGetFolderInfoFlags.RECURSIVE,
                    GLib.Priority.DEFAULT, connect_cancellable);
            }
            if (folderinfo != null) {
                show_info (folderinfo, this);
                update_open_folder_counts ();
                var current = new Gee.HashSet<string> ();
                collect_folder_names (folderinfo, current);
                foreach (var folder_item in folder_items.values.to_array ()) {
                    if (!current.contains (folder_item.folder_info.full_name)) {
                        folder_deleted (folder_item.folder_info);
                    }
                }
                queue_save_folders ();
            }
            debug ("Folder list ready");
        } catch (Error e) {
            critical (e.message);
        } finally {
            loading = false;
            if (reload_again) {
                reload_again = false;
                queue_reload ();
            } else if (pending_selection != null && folder_items.has_key (pending_selection)) {
                var path = pending_selection;
                pending_selection = null;
                selection_requested (path);
            }
        }
    }

    private void queue_reload () {
        if (reload_id == 0) {
            reload_id = Idle.add (() => {
                reload_id = 0;
                load.begin ();
                return Source.REMOVE;
            });
        }
    }

    private void folder_renamed (string old_name, Camel.FolderInfo folder_info) {
        saved_state.rename_path (old_name, folder_info.full_name);
        var settings = Application.settings;
        string selected_uid, selected_name;
        settings.get ("selected-folder", "(ss)", out selected_uid, out selected_name);
        if (selected_uid == account.service.uid && FolderOperations.is_within (selected_name, old_name)) {
            pending_selection = folder_info.full_name + selected_name.substring (old_name.length);
            settings.set ("selected-folder", "(ss)", selected_uid, pending_selection);
        }
        queue_reload ();
    }

    private void folder_deleted (Camel.FolderInfo folder_info) {
        var item = folder_items[folder_info.full_name];
        if (item != null) {
            if (item.parent != null) {
                item.parent.remove (item);
            }
            folder_items.unset (folder_info.full_name);
            saved_state.forget_folder (folder_info.full_name);
            queue_save_folders ();
            if (!loading) {
                queue_reload ();
            }
        }
    }

    private void folder_created (Camel.FolderInfo folder_info) {
        queue_reload ();
    }

    private async void reload_folders () {
        if (IMAP_FOLDER_SETUP) {
            yield load ();
            return;
        }
        var offlinestore = (Camel.OfflineStore) account.service;
        foreach (var folder_item in folder_items.values.to_array ()) {
            try {
                var folder_info = yield offlinestore.get_folder_info (folder_item.folder_info.full_name, Camel.StoreGetFolderInfoFlags.FAST, GLib.Priority.DEFAULT, connect_cancellable);
                if (folder_info != null) {
                    folder_item.folder_info = folder_info;
                }
            } catch (Error e) {
                // We can cancel the operation
                if (!(e is GLib.IOError.CANCELLED)) {
                    critical (e.message);
                }
            }
        }
        update_open_folder_counts ();
        queue_save_folders ();
    }

    private void restore_folders (Variant cached, string parent_name, Mail.SourceList.ExpandableItem parent, uint depth = 0) {
        if (depth > 64) {
            return;
        }
        var iter = cached.iterator ();
        string full_name, display_name, cached_parent;
        uint flags;
        int unread, total;
        while (iter.next ("(sssuii)", out full_name, out display_name, out cached_parent, out flags, out unread, out total)) {
            if (cached_parent != parent_name || full_name == "" || folder_items.has_key (full_name)) {
                continue;
            }
            var info = new Camel.FolderInfo ();
            info.full_name = full_name;
            info.display_name = display_name;
            info.flags = (Camel.FolderInfoFlags) flags;
            info.unread = unread;
            info.total = total;
            show_info (info, parent);
            restore_folders (cached, full_name, folder_items[full_name], depth + 1);
        }
    }

    private void collect_folder_names (Camel.FolderInfo? info, Gee.Set<string> names) {
        while (info != null) {
            names.add (info.full_name);
            collect_folder_names ((Camel.FolderInfo?) info.child, names);
            info = (Camel.FolderInfo?) info.next;
        }
    }

    private void queue_save_folders () {
        if (save_cache_id != 0) {
            return;
        }
        save_cache_id = Timeout.add (200, () => {
            save_cache_id = 0;
            var cached = new VariantBuilder (new VariantType ("a(sssuii)"));
            foreach (var folder in folder_items.values) {
                var parent = folder.parent as FolderItemModel;
                cached.add ("(sssuii)", folder.folder_info.full_name, folder.folder_info.display_name,
                    parent != null ? parent.folder_info.full_name : "", (uint) folder.folder_info.flags,
                    folder.folder_info.unread, folder.folder_info.total);
            }
            saved_state.cached_folders = cached.end ();
            return Source.REMOVE;
        });
    }

    private void show_info (Camel.FolderInfo? _folderinfo, Mail.SourceList.ExpandableItem item) {
        var folderinfo = _folderinfo;
        while (folderinfo != null) {
            var folder_item = folder_items[folderinfo.full_name];
            if (folder_item == null) {
                folder_item = new FolderItemModel (account, folderinfo);
                saved_state.bind_with_expandable_item (folder_item);
                folder_items[folderinfo.full_name] = folder_item;
                folder_item.start_edit.connect (() => start_edit (folder_item));
                folder_item.new_folder_requested.connect (() => create_folder (folder_item));
                folder_item.trash_requested.connect (() => confirm_trash (folder_item));
            } else {
                folder_item.folder_info = folderinfo;
            }

            var parent = folder_item.is_special_folder ? this : item;
            if (folder_item.parent != parent) {
                if (folder_item.parent != null) {
                    folder_item.parent.remove (folder_item);
                }
                parent.add (folder_item);
            }

            if (folderinfo.child != null) {
                show_info ((Camel.FolderInfo?) folderinfo.child, folder_item);
            }

            folderinfo = (Camel.FolderInfo?) folderinfo.next;
        }
    }

    public bool reorder_folder (FolderItemModel moved, FolderItemModel target, bool after) {
        if (moved == target || moved.parent == null || moved.parent != target.parent
            || moved.account != account || target.account != account || moved.busy || target.busy) {
            return false;
        }
        var siblings = new Gee.ArrayList<FolderItemModel> ();
        foreach (var child in moved.parent.children) {
            if (child is FolderItemModel) {
                siblings.add ((FolderItemModel) child);
            }
        }
        siblings.sort ((a, b) => FolderItemModel.compare_folders (a, b));
        siblings.remove (moved);
        siblings.insert (siblings.index_of (target) + (after ? 1 : 0), moved);
        saved_state.save_order (siblings);
        return true;
    }

    public void create_folder (FolderItemModel? parent = null) {
        var dialog = new FolderDialog (account, parent != null ? parent.folder_info.full_name : null,
            parent != null ? parent.name : null);
        dialog.created.connect ((info) => {
            pending_selection = info.full_name;
            queue_reload ();
        });
        dialog.present ();
    }

    private void confirm_trash (FolderItemModel item) {
        if (item.busy) {
            return;
        }
        var dialog = new Granite.MessageDialog (
            _("Move “%s” to Trash?").printf (item.name),
            _("The folder, its subfolders and all their messages will be moved to this account’s Trash. You have 5 seconds to undo."),
            new ThemedIcon ("user-trash"), Gtk.ButtonsType.NONE
        ) {
            transient_for = ((Gtk.Application) GLib.Application.get_default ()).active_window,
            modal = true
        };
        dialog.add_button (_("Cancel"), Gtk.ResponseType.CANCEL);
        dialog.add_button (_("Move to Trash"), Gtk.ResponseType.ACCEPT).get_style_context ().add_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
        dialog.set_default_response (Gtk.ResponseType.CANCEL);
        dialog.response.connect ((response) => {
            dialog.destroy ();
            if (response == Gtk.ResponseType.ACCEPT && !item.busy) {
                trash_folder.begin (item);
            }
        });
        dialog.present ();
    }

    private async void trash_folder (FolderItemModel item) {
        item.busy = true;
        var path = item.folder_info.full_name;
        try {
            var window = ((Gtk.Application) GLib.Application.get_default ()).active_window as MainWindow;
            if (window == null || !yield window.offer_undo (_("Folder will be moved to Trash"), 5)) {
                return;
            }
            var destination = yield FolderOperations.move_to_trash ((Camel.Store) account.service, path, connect_cancellable);
            pending_selection = destination;
            queue_reload ();
        } catch (Error e) {
            if (!(e is IOError.CANCELLED)) {
                MainWindow.send_error_message (_("Couldn’t move folder to Trash"), e.message, "user-trash");
            }
        } finally {
            item.busy = false;
        }
    }

    public int compare (Mail.SourceList.Item a, Mail.SourceList.Item b) {
        return FolderItemModel.compare_folders (a, b);
    }

    public bool allow_dnd_sorting () {
        return true;
    }

    public override Gtk.Menu? get_context_menu () {
        var menu = new Gtk.Menu ();
        var create = new Gtk.MenuItem.with_label (_("New folder…"));
        create.activate.connect (() => create_folder ());
        menu.add (create);
        var aliases = new Gtk.MenuItem.with_label (_("Edit Aliases…")) {
            action_name = FolderList.ACTION_PREFIX + FolderList.ACTION_EDIT_ALIASES,
            action_target = new Variant.string (account.service.uid)
        };
        menu.add (aliases);
        menu.show_all ();
        return menu;
    }
}
