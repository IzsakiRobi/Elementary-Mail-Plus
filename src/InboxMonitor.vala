/*
* Copyright 2021 elementary, Inc. (https://elementary.io)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 3 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*/

public class Mail.InboxMonitor : GLib.Object {

    private Gee.HashMap<Mail.Backend.Account, Cancellable> pending_accounts = new Gee.HashMap<Mail.Backend.Account, Cancellable> ();
    private Gee.HashMap<Mail.Backend.Account, ulong?> inbox_change_handlers = new Gee.HashMap<Mail.Backend.Account, ulong?> ();
    private uint badge_update_id;
    private bool badge_updating;
    private bool badge_dirty;
    private NetworkMonitor network_monitor;
    private Mail.Backend.Session session;
    private HashTable<Mail.Backend.Account, Camel.Folder> inbox_folders;
    private HashTable<Mail.Backend.Account, uint> synchronize_timeout_ids;

    construct {
        inbox_folders = new HashTable<Mail.Backend.Account, Camel.Folder> (Mail.Backend.Account.hash, Mail.Backend.Account.equal);
        synchronize_timeout_ids = new HashTable<Mail.Backend.Account, uint> (Mail.Backend.Account.hash, Mail.Backend.Account.equal);

        network_monitor = GLib.NetworkMonitor.get_default ();
        session = Mail.Backend.Session.get_default ();
    }

    public async void start () {
        yield session.start ();

        session.get_accounts ().foreach ((account) => {
            add_account (account);
            return true;
        });

        session.account_added.connect (add_account);
        session.account_removed.connect (remove_account);
        queue_badge_update ();
    }

    private void remove_account (Mail.Backend.Account account) {
        var pending = pending_accounts[account];
        if (pending != null) {
            pending.cancel ();
            pending_accounts.unset (account);
        }
        lock (inbox_folders) {
            var folder = inbox_folders[account];
            if (folder != null && inbox_change_handlers.has_key (account)) {
                SignalHandler.disconnect (folder, inbox_change_handlers[account]);
                inbox_change_handlers.unset (account);
            }
            inbox_folders.remove (account);
        }

        queue_badge_update ();

        lock (synchronize_timeout_ids) {
            if (synchronize_timeout_ids.contains (account)) {
                GLib.Source.remove (synchronize_timeout_ids.get (account));
            }

            synchronize_timeout_ids.remove (account);
        }
    }

    private void add_account (Mail.Backend.Account account) {
        if (pending_accounts.has_key (account) || inbox_folders.contains (account)) {
            return;
        }
        var cancellable = new Cancellable ();
        pending_accounts[account] = cancellable;
        open_inbox.begin (account, cancellable);
    }

    private async void open_inbox (Mail.Backend.Account account, Cancellable cancellable) {
        var store = account.service as Camel.Store;
        try {
            if (store == null) {
                return;
            }
            var inbox = yield store.get_inbox_folder (Priority.DEFAULT, cancellable);
            if (inbox == null || cancellable.is_cancelled ()) {
                return;
            }

            var folder = yield store.get_folder (inbox.full_name, Camel.StoreGetFolderFlags.NONE,
                Priority.DEFAULT, cancellable);
            if (folder == null || cancellable.is_cancelled ()) {
                return;
            }
            inbox_change_handlers[account] = folder.changed.connect ((change_info) => {
                var changes = change_info.copy ();
                Idle.add (() => {
                    inbox_folder_changed (account, changes);
                    return Source.REMOVE;
                });
            });
            lock (inbox_folders) {
                inbox_folders.insert (account, folder);
            }
            var timeout_id = Timeout.add_seconds (15 * 60, () => {
                inbox_folder_synchronize_sync.begin (account);
                return Source.CONTINUE;
            });
            lock (synchronize_timeout_ids) {
                synchronize_timeout_ids.insert (account, timeout_id);
            }
            var summary = folder.get_folder_summary ();
            debug ("Monitoring inbox %s at %p (%u messages, %d unread)", folder.full_name, folder,
                summary != null ? summary.get_saved_count () : 0, folder.get_unread_message_count ());
            queue_badge_update ();
            inbox_folder_synchronize_sync.begin (account);
        } catch (Error e) {
            if (!(e is IOError.CANCELLED)) {
                debug ("Error getting inbox folder: %s", e.message);
            }
        } finally {
            if (pending_accounts[account] == cancellable) {
                pending_accounts.unset (account);
            }
        }
    }

    private async void inbox_folder_synchronize_sync (Mail.Backend.Account account) {
        if (!network_monitor.network_available) {
            debug ("[%s] Network is not avaible. Skipping…", account.service.display_name);
            return;
        }

        var inbox_folder = inbox_folders.get (account);
        if (inbox_folder != null) {
            debug ("[%s] Refreshing…", account.service.display_name);

            try {
                yield inbox_folder.refresh_info (GLib.Priority.DEFAULT, null);
                queue_badge_update ();
            } catch (Error e) {
                debug ("[%s] Error refreshing: %s", account.service.display_name, e.message);
            }
        }
    }

    private void inbox_folder_changed (Mail.Backend.Account account, Camel.FolderChangeInfo changes) {
        var inbox_folder = inbox_folders.get (account);
        if (inbox_folder == null) {
            return;
        }

        debug ("Inbox changed: %u added, %u changed, %u removed",
            changes.get_added_uids ().length, changes.get_changed_uids ().length, changes.get_removed_uids ().length);
        queue_badge_update ();

        unowned var added_uids = changes.get_added_uids ();
        if (added_uids != null) {
            var sender_names = new GenericSet<string> (str_hash, str_equal);
            var unseen_message_infos = new SList<Camel.MessageInfo> ();

            added_uids.foreach ((added_uid) => {
                var message_info = inbox_folder.get_message_info (added_uid);
                if (message_info == null) {
                    return;
                }

                if (!(Camel.MessageFlags.SEEN in message_info.flags)) {
                    unowned string? sender_address;
                    unowned string? sender_name;

                    var camel_address = new Camel.InternetAddress ();
                    camel_address.unformat (message_info.from);
                    camel_address.get (0, out sender_name, out sender_address);

                    if (sender_name == null) {
                        sender_name = sender_address;
                    }

                    sender_names.add (sender_name);
                    unseen_message_infos.append (message_info);
                }
            });

            var unseen_message_infos_length = unseen_message_infos.length ();
            if (unseen_message_infos_length == 1) {
                var unseen_message_info = unseen_message_infos.nth_data (0);

                var notification = new GLib.Notification (_("%s to %s").printf (sender_names.iterator ().next_value (), inbox_folder.parent_store.display_name));
                notification.set_body (unseen_message_info.subject);
                GLib.Application.get_default ().send_notification (unseen_message_info.uid, notification);
            } else if (unseen_message_infos_length > 1) {
                GLib.Notification notification;

                ///TRANSLATORS: The %s represents the number of new messages translated in your language, e.g. "2 new messages"
                string messages_count = ngettext ("%u new message", "%u new messages", unseen_message_infos_length).printf (unseen_message_infos_length);

                if (sender_names.length == 1) {
                    var sender_name = sender_names.iterator ().next_value ();

                    notification = new GLib.Notification (_("%s to %s").printf (sender_name, inbox_folder.parent_store.display_name));
                    notification.set_body (messages_count);
                } else {
                    notification = new GLib.Notification (inbox_folder.parent_store.display_name);

                    ///TRANSLATORS: The first %s represents the number of new messages translated in your language, e.g. "2 new messages"
                    ///The next %s represents the number of senders
                    notification.set_body (ngettext ("%s from %u sender", "%s from %u senders", sender_names.length).printf (messages_count, sender_names.length));
                }

                GLib.Application.get_default ().send_notification (unseen_message_infos.nth_data (0).uid, notification);
            }
        }
    }

    private void queue_badge_update () {
        lock (badge_update_id) {
            if (badge_update_id != 0) {
                return;
            }

            badge_update_id = Idle.add (() => {
                lock (badge_update_id) {
                    badge_update_id = 0;
                }
                update_dock_badge.begin ();
                return Source.REMOVE;
            });
        }
    }

    private async void update_dock_badge () {
        badge_dirty = true;
        if (badge_updating) {
            return;
        }
        badge_updating = true;
        do {
            badge_dirty = false;
            uint total_unread = 0;
            lock (inbox_folders) {
                inbox_folders.foreach ((account, folder) => {
                    var summary = folder.get_folder_summary ();
                    total_unread += summary != null ? summary.get_unread_count () : 0;
                });
            }

            debug ("Dock badge: %u unread", total_unread);
            try {
                yield Granite.Services.Application.set_badge (total_unread);
                yield Granite.Services.Application.set_badge_visible (total_unread > 0);
            } catch (Error e) {
                debug ("Unable to update dock badge: %s", e.message);
            }
        } while (badge_dirty);
        badge_updating = false;
    }

}
