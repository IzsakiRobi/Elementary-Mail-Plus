/*
 * SPDX-License-Identifier: LGPL-3.0-or-later
 * SPDX-FileCopyrightText: 2017-2026 elementary, Inc. (https://elementary.io)
 *
 * Authored by: Corentin Noël <corentin@elementary.io>
 */

public class Mail.FolderList : Gtk.Box {
    public signal void folder_selected (Gee.Map<Backend.Account, Camel.FolderInfo?> folder_info_per_account);

    public signal bool messages_drop_possible (Gtk.Widget source, FolderItemModel folder);
    public signal bool messages_dropped (Gtk.Widget source, FolderItemModel folder);

    public const string ACTION_GROUP_PREFIX = "folder-list";
    public const string ACTION_PREFIX = ACTION_GROUP_PREFIX + ".";
    public const string ACTION_EDIT_ALIASES = "edit-alises";

    public Hdy.HeaderBar header_bar { get; private set; }

    private Mail.SourceList source_list;
    private Mail.SessionItemModel session_source_item;
    private static GLib.Settings settings;

    static construct {
        settings = new GLib.Settings (APPLICATION_ID);
    }

    construct {
        var application_instance = (Gtk.Application) GLib.Application.get_default ();

        var compose_button = new Gtk.Button.from_icon_name ("mail-message-new", Gtk.IconSize.LARGE_TOOLBAR) {
            action_name = MainWindow.ACTION_PREFIX + MainWindow.ACTION_COMPOSE_MESSAGE,
            halign = START
        };
        compose_button.tooltip_markup = Granite.markup_accel_tooltip (
            application_instance.get_accels_for_action (compose_button.action_name),
            _("Compose new message")
        );

        header_bar = new Hdy.HeaderBar () {
            show_close_button = true
        };
        header_bar.pack_end (compose_button);
        header_bar.get_style_context ().add_class (Gtk.STYLE_CLASS_FLAT);

        var session = Mail.Backend.Session.get_default ();

        session_source_item = new Mail.SessionItemModel (session);

        source_list = new Mail.SourceList ();
        source_list.root.add (session_source_item);
        source_list.reorder_requested.connect ((moved, target, after) => {
            var folder = moved as FolderItemModel;
            var destination = target as FolderItemModel;
            if (folder == null || destination == null) {
                return false;
            }
            var account = account_item_for (folder);
            return account != null && account.reorder_folder (folder, destination, after);
        });

        source_list.messages_drop_possible.connect ((source, target) => {
            var folder = target as FolderItemModel;
            return folder != null && messages_drop_possible (source, folder);
        });
        source_list.messages_dropped.connect ((source, target) => {
            var folder = target as FolderItemModel;
            return folder != null && messages_dropped (source, folder);
        });

        var scrolled_window = new Gtk.ScrolledWindow (null, null) {
            child = source_list,
            hscrollbar_policy = NEVER
        };

        var app_menu = new Gtk.Button.from_icon_name ("open-menu-symbolic", Gtk.IconSize.SMALL_TOOLBAR) {
            tooltip_text = _("Preferences"),
            action_name = "app.preferences"
        };

        var action_bar = new Gtk.ActionBar ();
        action_bar.get_style_context ().add_class (Gtk.STYLE_CLASS_FLAT);
        action_bar.pack_end (app_menu);
        var new_folder = new Gtk.Button.from_icon_name ("folder-new-symbolic", Gtk.IconSize.SMALL_TOOLBAR) {
            tooltip_text = _("New folder…")
        };
        new_folder.clicked.connect (() => {
            var account = account_item_for (source_list.selected);
            if (account != null) {
                account.create_folder ();
                return;
            }
            var menu = new Gtk.Menu ();
            foreach (var item in source_list.root.children) {
                if (item is AccountItemModel) {
                    var account_item = (AccountItemModel) item;
                    var choice = new Gtk.MenuItem.with_label (account_item.name);
                    choice.activate.connect (() => account_item.create_folder ());
                    menu.add (choice);
                }
            }
            menu.show_all ();
            menu.popup_at_widget (new_folder, Gdk.Gravity.NORTH_WEST, Gdk.Gravity.SOUTH_WEST, null);
        });
        action_bar.pack_start (new_folder);

        orientation = VERTICAL;
        width_request = 100;
        get_style_context ().add_class (Gtk.STYLE_CLASS_SIDEBAR);
        add (header_bar);
        add (scrolled_window);
        add (action_bar);

        session.get_accounts ().foreach ((account) => {
            add_account (account);
            return true;
        });

        session.account_added.connect (add_account);

        source_list.item_selected.connect ((item) => {
            if (item == null) {
                return;
            }

            if (item is FolderItemModel) {
                var folder_info_per_account = new Gee.HashMap<Mail.Backend.Account, Camel.FolderInfo?> ();
                folder_info_per_account.set (item.account, item.folder_info);
                folder_selected (folder_info_per_account.read_only_view);

                settings.set ("selected-folder", "(ss)", item.account.service.uid, item.folder_info.full_name);
                settings.set_uint ("selected-folder-flags", item.folder_info.flags);

            } else if (item is GroupedFolderItemModel) {
                folder_selected (item.get_folder_info_per_account ());

                settings.set ("selected-folder", "(ss)", "GROUPED", item.name);
            }
        });

        var edit_aliases_action = new SimpleAction (ACTION_EDIT_ALIASES, VariantType.STRING);
        edit_aliases_action.activate.connect ((param) => {
            new AliasDialog (param.get_string ()) {
                transient_for = (Gtk.Window) get_toplevel ()
            }.present ();
        });

        var action_group = new SimpleActionGroup ();
        action_group.add_action (edit_aliases_action);

        insert_action_group (ACTION_GROUP_PREFIX, action_group);
    }

    private void add_account (Mail.Backend.Account account) {
        var account_item = new Mail.AccountItemModel (account);
        account_item.start_edit.connect ((item) => source_list.start_editing_item (item));
        account_item.selection_requested.connect ((path) => select_saved_folder (account_item, path));
        source_list.root.add (account_item);
        string saved_uid, saved_name;
        settings.get ("selected-folder", "(ss)", out saved_uid, out saved_name);
        if (saved_uid == account.service.uid && saved_name != "") {
            var saved_info = new Camel.FolderInfo ();
            saved_info.full_name = saved_name;
            saved_info.display_name = saved_name;
            saved_info.flags = (Camel.FolderInfoFlags) settings.get_uint ("selected-folder-flags");
            if (saved_name.ascii_casecmp ("INBOX") == 0) {
                saved_info.flags = Camel.FolderInfoFlags.TYPE_INBOX;
            }
            var saved_selection = new Gee.HashMap<Mail.Backend.Account, Camel.FolderInfo?> ();
            saved_selection[account] = saved_info;
            Idle.add (() => {
                if (!select_saved_folder (account_item, saved_name)) {
                    folder_selected (saved_selection.read_only_view);
                }
                return Source.REMOVE;
            });
        }

        account_item.load.begin ((obj, res) => {
            account_item.load.end (res);

            string selected_folder_uid, selected_folder_name;
            settings.get ("selected-folder", "(ss)", out selected_folder_uid, out selected_folder_name);

            if (account.service.uid == selected_folder_uid) {
                select_saved_folder (account_item, selected_folder_name);
            } else if (selected_folder_uid == "GROUPED") {
                select_saved_folder (session_source_item, selected_folder_name);
            }
        });
    }

    private AccountItemModel? account_item_for (Mail.SourceList.Item? item) {
        while (item != null) {
            if (item is AccountItemModel) {
                return (AccountItemModel) item;
            }
            item = item.parent;
        }
        return null;
    }

    private bool select_saved_folder (Mail.SourceList.ExpandableItem item, string selected_folder_name) {
        foreach (var child in item.children) {
            if (child is FolderItemModel) {
                if (select_saved_folder ((Mail.SourceList.ExpandableItem) child, selected_folder_name)) {
                    return true;
                }

                unowned FolderItemModel folder_item = (FolderItemModel) child;
                if (folder_item.folder_info.full_name == selected_folder_name) {
                    source_list.selected = child;

                    return true;
                }
            } else if (child is GroupedFolderItemModel) {
                unowned GroupedFolderItemModel grouped_folder_item = (GroupedFolderItemModel) child;
                if (grouped_folder_item.name == selected_folder_name) {
                    source_list.selected = child;
                    return true;
                }
            }
        }

        return false;
    }
}
