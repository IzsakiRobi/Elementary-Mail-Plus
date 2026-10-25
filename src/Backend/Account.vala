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

public class Mail.Backend.Account : GLib.Object {
    public Camel.Service service { get; construct; }

    private bool folders_configured;

    public Account (Camel.Service service) {
        Object (service: service);
    }

    construct {
        unowned var network_monitor = GLib.NetworkMonitor.get_default ();
        network_monitor.network_changed.connect (manage_connection);
    }

    public async void configure_folders (Cancellable? cancellable = null) throws Error {
        if (!IMAP_FOLDER_SETUP || folders_configured) {
            return;
        }

        var settings = service.ref_settings ();
        var settings_class = (ObjectClass) settings.get_type ().class_ref ();
        if (settings_class.find_property ("real-trash-path") == null
            || settings_class.find_property ("real-junk-path") == null) {
            folders_configured = true;
            return;
        }

        string? trash_path, junk_path;
        settings.get ("real-trash-path", out trash_path, "real-junk-path", out junk_path);
        if (trash_path != null && trash_path != "" && junk_path != null && junk_path != "") {
            folders_configured = true;
            return;
        }

        HashTable<weak string, weak string>? setup;
        var store = (Camel.Store) service;
        if (!yield store.initial_setup (Priority.DEFAULT, cancellable, out setup)) {
            return;
        }
        if (setup != null) {
            foreach (var kind in new string[] {"trash", "junk"}) {
                var property = "real-%s-path".printf (kind);
                string? current_path;
                settings.get (property, out current_path);
                var path = setup.lookup ("Backend:Imapx Backend:%s:s".printf (property));
                if ((current_path == null || current_path == "") && path != null && path != "") {
                    settings.set (property, path, "use-real-%s-path".printf (kind), true);
                }
            }
        }
        folders_configured = service.connection_status == Camel.ServiceConnectionStatus.CONNECTED;
    }

    public async void manage_connection (bool online) {
        var offlinestore = (Camel.OfflineStore)service;

        if (online) {
            try {
                yield offlinestore.set_online (true, GLib.Priority.DEFAULT, null);
                yield offlinestore.synchronize (false, GLib.Priority.DEFAULT, null);
                debug ("Account '%s' connected to remote server.", service.display_name);
            } catch (Error e) {
                /* Don't show an error when the network is unavailable as it can be thrown when trying to connect
                   although the internet connection isn't fully available yet or on a rapid change of the connection */
                if (e is Camel.ServiceError.UNAVAILABLE || e is GLib.IOError.CANCELLED) {
                    debug (e.message);
                } else {
                    var error_dialog = new Granite.MessageDialog.with_image_from_icon_name (
                        _("Unable to connect"),
                        _("There was an unexpected error while trying to connect to the server."),
                        "network-error"
                    );
                    error_dialog.show_error_details (e.message);
                    error_dialog.response.connect (() => error_dialog.destroy ());
                    unowned var application = (Gtk.Application) GLib.Application.get_default ();
                    foreach (unowned var window in application.get_windows ()) {
                        if (window is MainWindow) {
                            error_dialog.transient_for = window;
                            break;
                        }
                    }
                    error_dialog.present ();
                }
            }
            return;
        }

        try {
            yield offlinestore.set_online (false, GLib.Priority.DEFAULT, null);
            debug ("Account '%s' disconnected from remote server.", service.display_name);
        } catch (Error e) {
            if (e is Camel.ServiceError.UNAVAILABLE || e is GLib.IOError.CANCELLED) {
                debug (e.message);
            } else {
                critical (e.message);
            }
        }
    }

    public static uint hash (Mail.Backend.Account account) {
        return GLib.str_hash (account.service.uid);
    }
    public bool equal (Mail.Backend.Account account2) {
        return hash (this) == hash (account2);
    }
}
