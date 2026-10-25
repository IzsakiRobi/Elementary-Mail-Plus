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

    private GLib.Cancellable connect_cancellable;
    private Gee.HashMap<string, FolderItemModel> folder_items;
    private AccountSavedState saved_state;
    private uint save_cache_id;
    private bool loading;
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
        }
    }

    private void folder_renamed (string old_name, Camel.FolderInfo folder_info) {
        FolderItemModel item;
        folder_items.unset (old_name, out item);
        item.folder_info = folder_info;
        folder_items[folder_info.full_name] = item;
        queue_save_folders ();
    }

    private void folder_deleted (Camel.FolderInfo folder_info) {
        Mail.FolderItemModel? item = folder_items[folder_info.full_name];
        if (item != null) {
            item.parent.remove (item);
            folder_items.unset (folder_info.full_name);
            queue_save_folders ();
        }
    }

    private void folder_created (Camel.FolderInfo folder_info) {
        if (folder_info.parent == null) {
            show_info (folder_info, this);
        } else {
            unowned Camel.FolderInfo parent_info = (Camel.FolderInfo) folder_info.parent;
            var parent_item = folder_items[parent_info.full_name];
            if (parent_item == null) {
                // Create the parent, then retry to create the children.
                folder_created (parent_info);
                folder_created (folder_info);
            } else {
                show_info (folder_info, parent_item);
            }
        }
        queue_save_folders ();
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

    public int compare (Mail.SourceList.Item a, Mail.SourceList.Item b) {
        if (a is Mail.FolderItemModel && b is Mail.FolderItemModel) {
            var folder_a = (Mail.FolderItemModel) a;
            var folder_b = (Mail.FolderItemModel) b;

            return folder_a.pos - folder_b.pos;
        }

        return 0;
    }

    public bool allow_dnd_sorting () {
        return false;
    }

    public override Gtk.Menu? get_context_menu () {
        var menu = new Menu ();
        menu.append (
            _("Edit Aliases…"),
            Action.print_detailed_name (FolderList.ACTION_PREFIX + FolderList.ACTION_EDIT_ALIASES, account.service.uid)
        );

        return new Gtk.Menu.from_model (menu);
    }
}
