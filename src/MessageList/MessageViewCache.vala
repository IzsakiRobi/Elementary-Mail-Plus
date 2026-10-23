/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2026 elementary Mail contributors
 */

public class Mail.MessageViewCache : Object {
    private Gee.HashMap<string, Gtk.ListBoxRow> rows = new Gee.HashMap<string, Gtk.ListBoxRow> ();
    private Gee.HashMap<string, uint64?> costs = new Gee.HashMap<string, uint64?> ();
    private Gee.LinkedList<string> order = new Gee.LinkedList<string> ();
    private uint64 bytes;
    private uint max_rows;
    private uint64 max_bytes;

    public uint count {
        get {
            return rows.size;
        }
    }

    public MessageViewCache (uint max_rows = 64, uint64 max_bytes = 64 * 1024 * 1024) {
        this.max_rows = max_rows;
        this.max_bytes = max_bytes;
    }

    public Gtk.ListBoxRow? take (string key) {
        Gtk.ListBoxRow? row;
        if (!rows.unset (key, out row)) {
            return null;
        }
        bytes -= costs[key];
        costs.unset (key);
        order.remove (key);
        return row;
    }

    public void put (string key, Gtk.ListBoxRow row, uint64 cost) {
        assert (row.get_parent () == null);
        var previous = take (key);
        if (previous != null && previous != row) {
            previous.destroy ();
        }
        if (max_rows == 0 || cost > max_bytes || cost > 8 * 1024 * 1024) {
            row.destroy ();
            return;
        }
        while (rows.size >= max_rows || bytes + cost > max_bytes) {
            var oldest = take (order[0]);
            oldest.destroy ();
        }
        rows[key] = row;
        costs[key] = cost;
        order.add (key);
        bytes += cost;
    }

    public void clear () {
        while (!order.is_empty) {
            var row = take (order[0]);
            row.destroy ();
        }
    }
}
