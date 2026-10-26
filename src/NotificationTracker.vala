/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class Mail.NotificationTracker : Object {
    public signal void withdrawal_requested (string id);

    private Gee.HashMap<string, Gee.HashMap<string, Gee.HashSet<string>>> groups =
        new Gee.HashMap<string, Gee.HashMap<string, Gee.HashSet<string>>> ();

    public string track (string scope, string[] uids) requires (uids.length > 0) {
        var id = "new-mail-" + Checksum.compute_for_string (
            ChecksumType.SHA256, new Variant ("(ss)", scope, uids[0]).print (false)
        );
        if (!groups.has_key (scope)) {
            groups[scope] = new Gee.HashMap<string, Gee.HashSet<string>> ();
        }
        var messages = new Gee.HashSet<string> ();
        foreach (var uid in uids) {
            messages.add (uid);
        }
        groups[scope][id] = messages;
        return id;
    }

    public void resolve (string scope, Gee.Collection<string> uids) {
        var notifications = groups[scope];
        if (notifications == null || uids.size == 0) {
            return;
        }
        foreach (var id in notifications.keys.to_array ()) {
            var messages = notifications[id];
            messages.remove_all (uids);
            if (messages.size == 0) {
                notifications.unset (id);
                withdrawal_requested (id);
            }
        }
        if (notifications.size == 0) {
            groups.unset (scope);
        }
    }

    public void clear (string scope) {
        Gee.HashMap<string, Gee.HashSet<string>>? notifications;
        if (groups.unset (scope, out notifications)) {
            foreach (var id in notifications.keys) {
                withdrawal_requested (id);
            }
        }
    }
}
