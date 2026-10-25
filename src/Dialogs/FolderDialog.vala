/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class Mail.FolderDialog : Granite.Dialog {
    public signal void created (Camel.FolderInfo info);

    private Gtk.Entry entry;
    private Gtk.Label error_label;
    private Gtk.Widget create_button;
    private Backend.Account account;
    private string? parent_folder;
    private Cancellable cancellable = new Cancellable ();
    private bool busy;

    public FolderDialog (Backend.Account account, string? parent_folder = null, string? parent_label = null) {
        Object (
            title: parent_folder == null ? _("New Folder") : _("New Subfolder"),
            transient_for: ((Gtk.Application) GLib.Application.get_default ()).active_window,
            modal: true,
            resizable: false
        );
        this.account = account;
        this.parent_folder = parent_folder;

        entry = new Gtk.Entry () {
            placeholder_text = _("Folder name"),
            activates_default = true,
            width_chars = 30,
            hexpand = true
        };
        var location = new Gtk.Label (parent_label ?? account.service.display_name) {
            xalign = 0,
            ellipsize = Pango.EllipsizeMode.MIDDLE,
            max_width_chars = 45
        };
        location.get_style_context ().add_class (Gtk.STYLE_CLASS_DIM_LABEL);
        error_label = new Gtk.Label (null) {
            wrap = true,
            xalign = 0,
            max_width_chars = 45,
            no_show_all = true
        };
        error_label.get_style_context ().add_class (Gtk.STYLE_CLASS_ERROR);
        var content = new Gtk.Box (Gtk.Orientation.VERTICAL, 8) {
            margin = 12
        };
        content.add (location);
        content.add (entry);
        content.add (error_label);
        get_content_area ().add (content);
        add_button (_("Cancel"), Gtk.ResponseType.CANCEL);
        create_button = add_button (_("Create"), Gtk.ResponseType.ACCEPT);
        create_button.get_style_context ().add_class (Gtk.STYLE_CLASS_SUGGESTED_ACTION);
        create_button.sensitive = false;
        set_default_response (Gtk.ResponseType.ACCEPT);
        entry.changed.connect (() => {
            create_button.sensitive = !busy && FolderOperations.valid_name (entry.text);
            error_label.hide ();
        });
        response.connect ((response) => {
            if (response == Gtk.ResponseType.ACCEPT) {
                if (!busy && FolderOperations.valid_name (entry.text)) {
                    create.begin ();
                }
            } else {
                destroy ();
            }
        });
        destroy.connect (() => cancellable.cancel ());
        show_all ();
        entry.grab_focus ();
    }

    private async void create () {
        busy = true;
        entry.sensitive = false;
        create_button.sensitive = false;
        try {
            var info = yield FolderOperations.create ((Camel.Store) account.service, parent_folder, entry.text, cancellable);
            created (info);
            destroy ();
        } catch (Error e) {
            if (!cancellable.is_cancelled () && !(e is IOError.CANCELLED)) {
                error_label.label = e.message;
                error_label.show ();
                entry.sensitive = true;
                entry.grab_focus ();
            }
        } finally {
            busy = false;
            if (!cancellable.is_cancelled ()) {
                create_button.sensitive = FolderOperations.valid_name (entry.text);
            }
        }
    }
}
