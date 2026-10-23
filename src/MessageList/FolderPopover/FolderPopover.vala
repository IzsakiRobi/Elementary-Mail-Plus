/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2017-2023 elementary, Inc. (https://elementary.io)
 *
 * Authored by: Leonhard Kargl <leo.kargl@proton.me>
 */

public class Mail.FolderPopover : Gtk.Popover {
    private Gtk.SearchEntry search_entry;
    private ListStore folder_list;
    private Camel.Store? current_store;
    private Cancellable? folder_request;
    private ulong created_handler;
    private ulong deleted_handler;
    private ulong renamed_handler;
    private ulong stale_handler;
    private bool folders_dirty = true;

    construct {
        show.connect (() => load_folders.begin ());
        destroy.connect (() => set_store (null));
        search_entry = new Gtk.SearchEntry () {
            margin_top = 12,
            margin_bottom = 9,
            margin_start = 12,
            margin_end = 12
        };

        var placeholder_image = new Gtk.Image.from_icon_name ("edit-find-symbolic", DND);

        var placeholder_title = new Gtk.Label (_("No mailboxes found")) {
            xalign = 0
        };

        var placeholder_subtitle = new Gtk.Label (_("Try changing search terms")) {
            xalign = 0
        };
        placeholder_subtitle.get_style_context ().add_class (Gtk.STYLE_CLASS_DIM_LABEL);
        placeholder_subtitle.get_style_context ().add_class (Granite.STYLE_CLASS_SMALL_LABEL);

        var placeholder = new Gtk.Grid () {
            column_spacing = 6,
            margin_top = 6,
            margin_start = 12,
            margin_bottom = 12,
            margin_end = 12
        };
        placeholder.attach (placeholder_image, 0, 0, 1, 2);
        placeholder.attach (placeholder_title, 1, 0);
        placeholder.attach (placeholder_subtitle, 1, 1);
        placeholder.show_all ();

        folder_list = new ListStore (typeof (FolderRow));

        var list_box = new Gtk.ListBox () {
            activate_on_single_click = true
        };
        list_box.bind_model (folder_list, (obj) => (FolderRow) obj);
        list_box.set_filter_func (filter_func);
        list_box.set_placeholder (placeholder);

        var scrolled_window = new Gtk.ScrolledWindow (null, null) {
            child = list_box,
            hexpand = true,
            vexpand = true,
            margin_bottom = 3,
            max_content_height = 350,
            propagate_natural_height = true,
            hscrollbar_policy = NEVER
        };

        var box = new Gtk.Box (VERTICAL, 0);
        box.add (search_entry);
        box.add (scrolled_window);
        box.show_all ();

        width_request = 250;
        child = box;

        search_entry.search_changed.connect (list_box.invalidate_filter);

        list_box.row_activated.connect ((row) => {
            if (row is FolderRow) {
                var folder_row = (FolderRow)row;

                popdown ();
                ((MainWindow)get_toplevel ()).activate_action (MainWindow.ACTION_MOVE, row.folder_info.full_name);
            }
        });
    }

    public void set_store (Camel.Store? store) {
        if (current_store == store) {
            return;
        }
        if (folder_request != null) {
            folder_request.cancel ();
        }
        if (current_store != null) {
            SignalHandler.disconnect (current_store, created_handler);
            SignalHandler.disconnect (current_store, deleted_handler);
            SignalHandler.disconnect (current_store, renamed_handler);
            SignalHandler.disconnect (current_store, stale_handler);
        }
        current_store = store;
        folder_list.remove_all ();
        folders_dirty = true;
        if (store != null) {
            created_handler = store.folder_created.connect (() => folders_dirty = true);
            deleted_handler = store.folder_deleted.connect (() => folders_dirty = true);
            renamed_handler = store.folder_renamed.connect (() => folders_dirty = true);
            stale_handler = store.folder_info_stale.connect (() => folders_dirty = true);
        }
    }

    private async void load_folders () {
        var store = current_store;
        if (store == null || !folders_dirty) {
            return;
        }
        folders_dirty = false;
        if (folder_request != null) {
            folder_request.cancel ();
        }
        var request = new Cancellable ();
        folder_request = request;
        try {
            var info = yield store.get_folder_info (null, Camel.StoreGetFolderInfoFlags.RECURSIVE,
                Priority.DEFAULT, request);
            if (!request.is_cancelled () && current_store == store) {
                folder_list.remove_all ();
                if (info != null) {
                    update (info, store);
                }
            }
        } catch (Error e) {
            if (!request.is_cancelled ()) {
                folders_dirty = true;
                warning ("Could not load destination folders: %s", e.message);
            }
        }
    }

    private void update (Camel.FolderInfo top, Camel.Store store) {
        var folder_info = top;
        while (folder_info != null) {
            folder_list.insert_sorted (new FolderRow (folder_info, store), sort_func);

            if (folder_info.child != null) {
                update (folder_info.child, store);
            }
            folder_info = folder_info.next;
        }
    }

    private int sort_func (Object row1, Object row2) {
        var folder_row1 = (FolderRow) row1;
        var folder_row2 = (FolderRow) row2;

        return folder_row1.pos - folder_row2.pos;
    }

    private bool filter_func (Gtk.ListBoxRow row) {
        if (row is FolderRow) {
            var folder_row = (FolderRow)row;
            return search_entry.text.down ().strip () in folder_row.folder_info.display_name.down ();
        }

        return true;
    }
}
