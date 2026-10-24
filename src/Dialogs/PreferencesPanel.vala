/* SPDX-License-Identifier: GPL-3.0-or-later */
public class Mail.PreferencesPanel : Granite.Dialog {
    private Gtk.Switch remote_images;
    private Gtk.Switch remote_logos;
    private Gtk.Switch show_avatars;
    private Gtk.Switch undo_send;
    private Gtk.Switch undo_delete;
    private Gtk.Switch background;
    private Gtk.Scale read_delay;
    private Gtk.Scale undo_time;
    private Gtk.ScrolledWindow scroller;
    private Gtk.Entry key_entry;
    private Gtk.Button key_save;
    private Gtk.Button key_clear;
    private Gtk.Label status;
    private Gtk.Grid form;
    private LogoCredentials credentials;
    private bool key_dirty;
    private bool busy;
    private bool filling_key;
    private ulong credentials_handler;

    public PreferencesPanel (Gtk.Window parent) {
        Object (title: _("Mail Preferences"), transient_for: parent, modal: true,
            application: (Gtk.Application) GLib.Application.get_default (),
            destroy_with_parent: true, resizable: false,
            window_position: Gtk.WindowPosition.CENTER_ON_PARENT);
        scroller.max_content_height = int.max (300, int.min (580, parent.get_allocated_height () - 140));
    }

    construct {
        credentials = LogoCredentials.get_default ();
        remote_images = new Gtk.Switch () {
            active = Application.settings.get_boolean ("always-load-remote-images"),
            valign = CENTER, halign = END, hexpand = false
        };
        remote_logos = new Gtk.Switch () {
            active = Application.settings.get_boolean ("load-remote-avatars"),
            valign = CENTER, halign = END, hexpand = false
        };
        form = new Gtk.Grid () { margin = 24, row_spacing = 12, column_spacing = 18 };
        var title = new Granite.HeaderLabel (_("Remote Content"));
        form.attach (title, 0, 0, 2, 1);
        form.attach (new Gtk.Label (_("Always load remote images")) { xalign = 0, hexpand = true }, 0, 1);
        form.attach (remote_images, 1, 1);
        form.attach (new Gtk.Label (_("Load avatars and company logos")) { xalign = 0 }, 0, 2);
        form.attach (remote_logos, 1, 2);
        form.attach (new Gtk.Separator (Gtk.Orientation.HORIZONTAL), 0, 3, 2, 1);
        form.attach (new Granite.HeaderLabel (_("Logo.dev API Key")), 0, 4, 2, 1);

        key_entry = new Gtk.Entry () {
            placeholder_text = _("Enter your pk_ publishable key"),
            visibility = false, input_purpose = PASSWORD,
            hexpand = true, width_chars = 30,
            secondary_icon_name = "view-reveal-symbolic",
            secondary_icon_tooltip_text = _("Show or hide the API key")
        };
        key_entry.icon_release.connect ((position) => {
            if (position == Gtk.EntryIconPosition.SECONDARY) {
                key_entry.visibility = !key_entry.visibility;
            }
        });
        key_save = new Gtk.Button.with_label (_("Save")) { sensitive = false };
        key_save.get_style_context ().add_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
        key_save.clicked.connect (() => save.begin (false));
        key_clear = new Gtk.Button.with_label (_("Clear")) {
            sensitive = false,
            tooltip_text = _("Remove the API key and clear cached avatars and logos")
        };
        key_clear.clicked.connect (() => {
            key_entry.text = "";
            key_dirty = true;
            save.begin (false, true);
        });
        var key_row = new Gtk.Box (HORIZONTAL, 0);
        key_row.get_style_context ().add_class (Gtk.STYLE_CLASS_LINKED);
        key_row.add (key_entry);
        key_row.add (key_save);
        key_row.add (key_clear);
        form.attach (key_row, 0, 5, 2, 1);

        var hint = new Gtk.Label (_("Stored in the system keyring. Clear the field and save to remove the key.")) {
            wrap = true, max_width_chars = 48, xalign = 0
        };
        hint.get_style_context ().add_class (Gtk.STYLE_CLASS_DIM_LABEL);
        hint.get_style_context ().add_class (Granite.STYLE_CLASS_SMALL_LABEL);
        form.attach (hint, 0, 6, 2, 1);
        status = new Gtk.Label ("") { wrap = true, max_width_chars = 48, xalign = 0 };
        form.attach (status, 0, 7, 2, 1);

        var logo_hint = new Gtk.Label (_("Create a free <a href=\"https://logo.dev\">Logo.dev</a> account for high-resolution company logos.")) {
            use_markup = true, wrap = true, max_width_chars = 48, xalign = 0
        };
        logo_hint.get_style_context ().add_class (Gtk.STYLE_CLASS_DIM_LABEL);
        logo_hint.get_style_context ().add_class (Granite.STYLE_CLASS_SMALL_LABEL);
        form.attach (logo_hint, 0, 8, 2, 1);
        form.attach (new Gtk.Separator (Gtk.Orientation.HORIZONTAL), 0, 9, 2, 1);
        var signatures = new Gtk.Button.with_label (_("Edit Signatures…")) {
            action_name = Application.ACTION_PREFIX + Application.ACTION_MANAGE_SIGNATURES
        };
        var accounts = new Gtk.Button.with_label (_("Account Settings…")) {
            action_name = Application.ACTION_PREFIX + Application.ACTION_ACCOUNT_SETTINGS
        };
        var account_row = new Gtk.Box (HORIZONTAL, 12);
        account_row.add (signatures);
        account_row.add (accounts);
        form.attach (account_row, 0, 10, 2, 1);
        show_avatars = new Gtk.Switch () {
            active = Application.settings.get_boolean ("show-avatars"), valign = CENTER, halign = END, hexpand = false
        };
        form.insert_row (2);
        form.attach (new Gtk.Label (_("Show avatars")) { xalign = 0 }, 0, 2);
        form.attach (show_avatars, 1, 2);
        remote_logos.sensitive = show_avatars.active;
        show_avatars.notify["active"].connect (() => remote_logos.sensitive = show_avatars.active);

        for (int i = 0; i < 5; i++) {
            form.insert_row (10);
        }
        form.attach (new Granite.HeaderLabel (_("Reading & Undo")), 0, 10, 2, 1);
        read_delay = delay_scale (Application.settings.get_int ("mark-read-delay"));
        undo_time = delay_scale (Application.settings.get_int ("undo-time"));
        undo_send = new Gtk.Switch () {
            active = Application.settings.get_boolean ("undo-send"), valign = CENTER, halign = END, hexpand = false
        };
        undo_delete = new Gtk.Switch () {
            active = Application.settings.get_boolean ("undo-delete"), valign = CENTER, halign = END, hexpand = false
        };
        form.attach (new Gtk.Label (_("Mark as read after")) { xalign = 0 }, 0, 11);
        form.attach (delay_control (read_delay), 1, 11);
        form.attach (new Gtk.Label (_("Undo time")) { xalign = 0 }, 0, 12);
        form.attach (delay_control (undo_time), 1, 12);
        form.attach (new Gtk.Label (_("Undo for send")) { xalign = 0 }, 0, 13);
        form.attach (undo_send, 1, 13);
        form.attach (new Gtk.Label (_("Undo for delete")) { xalign = 0 }, 0, 14);
        form.attach (undo_delete, 1, 14);
        form.insert_row (15);
        form.insert_row (15);
        background = new Gtk.Switch () {
            active = Application.settings.get_boolean ("run-in-background"), valign = CENTER, halign = END, hexpand = false
        };
        form.attach (new Gtk.Label (_("Run in background")) { xalign = 0 }, 0, 15);
        form.attach (background, 1, 15);
        var background_hint = new Gtk.Label (_("Start at login and notify about new mail when the window is closed.")) {
            xalign = 0, wrap = true, max_width_chars = 48
        };
        background_hint.get_style_context ().add_class (Gtk.STYLE_CLASS_DIM_LABEL);
        background_hint.get_style_context ().add_class (Granite.STYLE_CLASS_SMALL_LABEL);
        form.attach (background_hint, 0, 16, 2, 1);
        scroller = new Gtk.ScrolledWindow (null, null) {
            hscrollbar_policy = NEVER, vscrollbar_policy = AUTOMATIC,
            propagate_natural_height = true, max_content_height = 580,
            min_content_width = 460
        };
        scroller.add (form);
        get_content_area ().add (scroller);
        add_button (_("Cancel"), Gtk.ResponseType.CANCEL);
        add_button (_("Save"), Gtk.ResponseType.ACCEPT).get_style_context ().add_class (Gtk.STYLE_CLASS_DESTRUCTIVE_ACTION);
        set_default_response (Gtk.ResponseType.ACCEPT);

        key_entry.changed.connect (() => {
            if (!filling_key) {
                key_dirty = true;
                key_save.sensitive = credentials.ready && !busy;
                status.label = "";
            }
        });
        credentials_handler = credentials.notify["ready"].connect (fill_key);
        credentials.refresh.begin ();
        fill_key ();
        destroy.connect (() => credentials.disconnect (credentials_handler));
        delete_event.connect (() => busy);
        response.connect ((response_id) => {
            if (busy) {
                return;
            }
            if (response_id == Gtk.ResponseType.ACCEPT) {
                save.begin (true);
            } else {
                destroy ();
            }
        });
        get_content_area ().show_all ();
        get_action_area ().show_all ();
    }

    private Gtk.Scale delay_scale (int value) {
        var scale = new Gtk.Scale.with_range (Gtk.Orientation.HORIZONTAL, 0, 5, 1) {
            digits = 0, round_digits = 0, draw_value = false, width_request = 120,
            hexpand = true
        };
        scale.set_value (value);
        for (int i = 0; i <= 5; i++) {
            scale.add_mark (i, Gtk.PositionType.BOTTOM, null);
        }
        return scale;
    }

    private Gtk.Widget delay_control (Gtk.Scale scale) {
        var value = new Gtk.Label (_("%d s").printf ((int) Math.round (scale.get_value ()))) {
            width_chars = 3, xalign = 1, valign = CENTER
        };
        scale.value_changed.connect (() => {
            value.label = _("%d s").printf ((int) Math.round (scale.get_value ()));
        });
        var row = new Gtk.Box (HORIZONTAL, 1);
        row.pack_start (scale, true, true);
        row.pack_end (value, false, false);
        return row;
    }

    private void fill_key () {
        key_entry.sensitive = credentials.ready;
        key_clear.sensitive = credentials.ready && !busy;
        key_entry.placeholder_text = credentials.ready
            ? _("Enter your pk_ publishable key") : _("Checking system keyring…");
        if (credentials.ready && !key_dirty) {
            filling_key = true;
            key_entry.text = credentials.key ?? "";
            filling_key = false;
        }
    }

    private async void save (bool close_after, bool clear_cache = false) {
        if (busy) {
            return;
        }
        busy = true;
        form.sensitive = false;
        set_response_sensitive (Gtk.ResponseType.ACCEPT, false);
        set_response_sensitive (Gtk.ResponseType.CANCEL, false);
        deletable = false;
        bool succeeded = false;
        try {
            if (key_dirty) {
                yield credentials.save (key_entry.text);
                key_dirty = false;
                if (clear_cache) {
                    yield SenderAvatar.clear_cache ();
                    credentials.changed ();
                }
                status.label = credentials.key == null
                    ? (clear_cache ? _("API key and cached avatars cleared.") : _("API key removed from the system keyring."))
                    : _("API key saved in the system keyring.");
            }
            if (close_after) {
                if (background.active != Application.settings.get_boolean ("run-in-background")) {
                    yield ((Application) GLib.Application.get_default ()).set_background_enabled (background.active);
                }
                Application.settings.set_boolean ("always-load-remote-images", remote_images.active);
                Application.settings.set_boolean ("load-remote-avatars", remote_logos.active);
                Application.settings.set_boolean ("show-avatars", show_avatars.active);
                Application.settings.set_int ("mark-read-delay", (int) Math.round (read_delay.get_value ()));
                Application.settings.set_int ("undo-time", (int) Math.round (undo_time.get_value ()));
                Application.settings.set_boolean ("undo-send", undo_send.active);
                Application.settings.set_boolean ("undo-delete", undo_delete.active);
            }
            succeeded = true;
        } catch (IOError.INVALID_ARGUMENT e) {
            status.label = e.message;
        } catch (Error e) {
            status.label = _("Could not save preferences: %s").printf (e.message);
        }
        busy = false;
        form.sensitive = true;
        deletable = true;
        set_response_sensitive (Gtk.ResponseType.ACCEPT, true);
        set_response_sensitive (Gtk.ResponseType.CANCEL, true);
        key_save.sensitive = key_dirty && credentials.ready;
        key_clear.sensitive = credentials.ready;
        if (succeeded && close_after) {
            destroy ();
        }
    }
}
