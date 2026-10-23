/* SPDX-License-Identifier: GPL-3.0-or-later */
public class Mail.UndoBanner : Gtk.Revealer {
    public signal void completed (bool commit);
    private uint timer;
    private bool done;
    private bool committed;

    public UndoBanner (string message, uint seconds) {
        Object (halign: Gtk.Align.CENTER, valign: Gtk.Align.END, margin: 12,
            transition_type: Gtk.RevealerTransitionType.SLIDE_UP);
        var undo = new Gtk.Button.with_label (_("Undo"));
        var box = new Gtk.Box (HORIZONTAL, 12) { margin = 12 };
        box.add (new Gtk.Label (message) { wrap = true, max_width_chars = 40 });
        box.add (undo);
        var frame = new Gtk.Frame (null) { child = box };
        frame.get_style_context ().add_class ("app-notification");
        add (frame);
        undo.clicked.connect (cancel);
        destroy.connect (() => {
            if (timer != 0) {
                Source.remove (timer);
                timer = 0;
            }
            if (!done) {
                done = true;
                completed (false);
            }
        });
        show_all ();
        reveal_child = true;
        timer = Timeout.add (seconds * 1000, () => {
            timer = 0;
            finish (true);
            return Source.REMOVE;
        });
    }

    public void cancel () {
        finish (false);
    }

    private void finish (bool commit) {
        if (done) {
            return;
        }
        done = true;
        committed = commit;
        if (timer != 0) {
            Source.remove (timer);
            timer = 0;
        }
        completed (commit);
        destroy ();
    }

    public async bool wait () {
        if (!done) {
            ulong handler = 0;
            handler = completed.connect (() => {
                disconnect (handler);
                wait.callback ();
            });
            yield;
        }
        return committed;
    }
}
