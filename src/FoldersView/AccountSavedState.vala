// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/*-
 * Copyright (c) 2017 elementary LLC. (https://elementary.io)
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authored by: Corentin Noël <corentin@elementary.io>
 */

public class Mail.AccountSavedState : GLib.Object {
    public unowned Mail.Backend.Account account { get; construct; }

    private GLib.Settings settings;
    private Gee.HashMap<string, FolderItemModel> items;

    public Variant cached_folders {
        owned get {
            return settings.get_value ("cached-folders");
        }
        set {
            settings.set_value ("cached-folders", value);
        }
    }

    public AccountSavedState (Mail.Backend.Account account) {
        Object (account: account);
    }

    construct {
        settings = new GLib.Settings.with_path (APPLICATION_ID + ".accounts", ("/" + APPLICATION_ID.replace (".", "/") + "/accounts/%s/").printf (account.service.uid));
        items = new Gee.HashMap<string, FolderItemModel> ();
    }

    public void save_order (Gee.List<FolderItemModel> siblings) {
        var paths = new Gee.HashSet<string> ();
        foreach (var item in siblings) {
            paths.add (item.folder_info.full_name);
        }
        string[] order = {};
        foreach (var path in settings.get_strv ("folder-order")) {
            if (!paths.contains (path)) {
                order += path;
            }
        }
        foreach (var item in siblings) {
            order += item.folder_info.full_name;
        }
        settings.set_strv ("folder-order", order);
        foreach (var item in items.values) {
            apply_order (item);
        }
    }

    public void rename_path (string old_path, string new_path) {
        foreach (var key in new string[] {"folder-order", "expanded-folders"}) {
            var paths = settings.get_strv (key);
            for (int i = 0; i < paths.length; i++) {
                if (FolderOperations.is_within (paths[i], old_path)) {
                    paths[i] = new_path + paths[i].substring (old_path.length);
                }
            }
            settings.set_strv (key, paths);
        }
    }

    public void forget_folder (string path) {
        items.unset (path);
    }

    private void apply_order (FolderItemModel item) {
        var order = settings.get_strv ("folder-order");
        item.sort_index = int.MAX;
        for (int i = 0; i < order.length; i++) {
            if (order[i] == item.folder_info.full_name) {
                item.sort_index = i;
                break;
            }
        }
    }

    public void bind_with_expandable_item (Mail.SourceList.ExpandableItem item) {
        if (item is AccountItemModel) {
            settings.bind ("expanded", item, "expanded", SettingsBindFlags.DEFAULT | SettingsBindFlags.GET_NO_CHANGES);
        } else if (item is FolderItemModel) {
            var folder_item = (FolderItemModel) item;
            items[folder_item.folder_info.full_name] = folder_item;
            apply_order (folder_item);
            if (folder_item.folder_info.full_name in settings.get_strv ("expanded-folders")) {
                item.expanded = true;
            }

            item.notify["expanded"].connect (() => {
                var folders = settings.get_strv ("expanded-folders");
                if (item.expanded) {
                    folders += folder_item.folder_info.full_name;
                } else {
                    string[] new_folders = {};
                    foreach (var folder in folders) {
                        if (folder != folder_item.folder_info.full_name) {
                            new_folders += folder;
                        }
                    }

                    folders = new_folders;
                }

                settings.set_strv ("expanded-folders", folders);
            });
        }
    }
}
