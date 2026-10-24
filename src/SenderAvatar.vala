/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class Mail.SenderAvatar : Gtk.Bin {
    public int size { get; construct; }
    private Hdy.Avatar avatar;
    private static Soup.Session session;
    private static Gee.HashMap<string, BytesIcon> cache;
    private static Gee.HashSet<string> missing;
    private static uint cache_generation;
    private Cancellable? loading;
    private string? email;
    private ulong settings_handler;
    private ulong visibility_handler;
    private ulong contacts_handler;
    private ulong credentials_handler;
    private ContactManager contacts;
    private LogoCredentials credentials;

    static construct {
        session = (Soup.Session) Object.new (typeof (Soup.Session),
            "timeout", 10,
            "max-conns", 4,
            "max-conns-per-host", 4,
            "user-agent", "elementary-Mail/8.0"
        );
        cache = new Gee.HashMap<string, BytesIcon> ();
        missing = new Gee.HashSet<string> ();
    }

    public SenderAvatar (int avatar_size) {
        Object (size: avatar_size);
    }

    construct {
        avatar = new Hdy.Avatar (size, null, true) {
            margin = 4
        };
        add (avatar);
        avatar.show ();
        settings_handler = Application.settings.changed["load-remote-avatars"].connect (() => {
            set_icon (null);
            reload ();
        });
        contacts = ContactManager.get_default ();
        credentials = LogoCredentials.get_default ();
        contacts_handler = contacts.avatars_changed.connect (reload);
        credentials_handler = credentials.changed.connect (() => {
            set_icon (null);
            reload ();
        });
        no_show_all = true;
        visible = Application.settings.get_boolean ("show-avatars");
        visibility_handler = Application.settings.changed["show-avatars"].connect (() => {
            visible = Application.settings.get_boolean ("show-avatars");
            reload ();
        });
        destroy.connect (() => {
            if (loading != null) {
                loading.cancel ();
            }
            if (settings_handler != 0) {
                Application.settings.disconnect (settings_handler);
                settings_handler = 0;
            }
            Application.settings.disconnect (visibility_handler);
            contacts.disconnect (contacts_handler);
            credentials.disconnect (credentials_handler);
        });
    }

    public void bind_sender (string? name, string? address) {
        var normalized = address != null ? address.strip ().down () : null;
        var text = name ?? address ?? _("Unknown");
        if (avatar.text != text) {
            avatar.text = text;
            tooltip_text = text;
        }
        if (email == normalized) {
            return;
        }
        email = normalized;
        set_icon (null);
        reload ();
    }

    private void set_icon (LoadableIcon? icon) {
        if (icon != null && !Application.settings.get_boolean ("load-remote-avatars")) {
            return;
        }
        var current = avatar.get_loadable_icon ();
        if (current == null && icon == null) {
            return;
        }
        if (current != null && icon != null && current.equal (icon)) {
            return;
        }
        avatar.set_loadable_icon (icon);
    }

    private void reload () {
        if (loading != null) {
            loading.cancel ();
        }
        if (!Application.settings.get_boolean ("load-remote-avatars")) {
            set_icon (null);
            return;
        }
        if (!visible || email == null || !email.contains ("@")) {
            return;
        }
        loading = new Cancellable ();
        load_avatar.begin (email.strip ().down (), loading);
    }

    private async void load_avatar (string address, Cancellable cancellable) {
        if (cancellable.is_cancelled () || !Application.settings.get_boolean ("load-remote-avatars")) {
            return;
        }
        var contact_icon = yield contacts.lookup_avatar (address);
        if (contact_icon != null && !cancellable.is_cancelled ()) {
            try {
                var stream = yield contact_icon.load_async (512, cancellable);
                try {
                    var image = yield new Gdk.Pixbuf.from_stream_at_scale_async (stream, 1024, 1024, true, cancellable);
                    if (!cancellable.is_cancelled ()) {
                        set_icon (fill_icon (image));
                    }
                    return;
                } finally {
                    close_response (stream);
                }
            } catch (Error e) {
            }
        }
        if (cancellable.is_cancelled () || !Application.settings.get_boolean ("load-remote-avatars")) {
            return;
        }

        yield credentials.ensure_ready ();
        if (cancellable.is_cancelled ()) {
            return;
        }

        BytesIcon? icon = null;
        var domain = company_domain (address);
        if (domain != null) {
            var key = credentials.key;
            if (key != null && key != "") {
                var uri = "https://img.logo.dev/%s?token=%s&size=512&format=png&fallback=404".printf (
                    domain, Uri.escape_string (key, null, false)
                );
                icon = yield fetch_icon (uri, cancellable);
            }
        }
        if (icon == null && !cancellable.is_cancelled ()) {
            var hash = Checksum.compute_for_string (ChecksumType.SHA256, address);
            icon = yield fetch_icon ("https://www.gravatar.com/avatar/%s?d=404&s=512&r=g".printf (hash), cancellable);
        }
        if (!cancellable.is_cancelled ()) {
            set_icon (icon);
        }
    }

    private static string? company_domain (string address) {
        var parts = address.split ("@");
        if (parts.length != 2) {
            return null;
        }
        var domain = Hostname.to_ascii (parts[1]);
        if (domain == null || !Regex.match_simple ("^[a-z0-9-]+(\\.[a-z0-9-]+)+$", domain)) {
            return null;
        }
        try {
            domain = Soup.tld_get_base_domain (domain);
        } catch (Error e) {
            return null;
        }
        string[] personal = {
            "gmail.com", "googlemail.com", "outlook.com", "hotmail.com",
            "live.com", "msn.com", "yahoo.com", "yahoo.co.uk", "ymail.com",
            "icloud.com", "me.com", "mac.com", "aol.com", "proton.me",
            "protonmail.com", "pm.me", "tuta.com", "tutanota.com", "gmx.com",
            "gmx.de", "mail.com", "freemail.hu", "citromail.hu", "vipmail.hu"
        };
        return domain in personal ? null : domain;
    }

    private async BytesIcon? fetch_icon (string uri, Cancellable cancellable) {
        var generation = cache_generation;
        if (cancellable.is_cancelled ()) {
            return null;
        }
        if (cache.has_key (uri)) {
            return cache[uri];
        }

        var message = new Soup.Message ("GET", uri);
        var cache_dir = Path.build_filename (Environment.get_user_cache_dir (), APPLICATION_ID, "avatars-v3");
        var cache_file = File.new_for_path (Path.build_filename (cache_dir,
            Checksum.compute_for_string (ChecksumType.SHA256, uri) + ".png"));
        try {
            var info = yield cache_file.query_info_async (
                FileAttribute.TIME_MODIFIED + "," + FileAttribute.STANDARD_SIZE,
                FileQueryInfoFlags.NONE, Priority.DEFAULT, cancellable
            );
            var age = new DateTime.now_utc ().to_unix () - (int64) info.get_attribute_uint64 (FileAttribute.TIME_MODIFIED);
            if (age >= 0 && age < 7 * 24 * 60 * 60 && info.get_size () <= 1024 * 1024) {
                uint8[] data;
                yield cache_file.load_contents_async (cancellable, out data, null);
                var image_stream = new MemoryInputStream.from_bytes (new Bytes (data));
                yield new Gdk.Pixbuf.from_stream_at_scale_async (image_stream, 512, 512, true, cancellable);
                if (cancellable.is_cancelled () || generation != cache_generation) {
                    return null;
                }
                var icon = new BytesIcon (new Bytes (data));
                remember_icon (uri, icon);
                return icon;
            }
        } catch (Error e) {
        }

        if (cancellable.is_cancelled ()) {
            return null;
        }
        if (missing.contains (uri) || !NetworkMonitor.get_default ().network_available) {
            return null;
        }
        try {
            var stream = yield session.send_async (message, Priority.DEFAULT, cancellable);
            Bytes? bytes = null;
            try {
                if (message.status_code != Soup.Status.OK) {
                    if (message.status_code == Soup.Status.NOT_FOUND) {
                        if (missing.size >= 512) {
                            missing.clear ();
                        }
                        missing.add (uri);
                    }
                    return null;
                }
                var output = new MemoryOutputStream.resizable ();
                while (true) {
                    var chunk = yield stream.read_bytes_async (8192, Priority.DEFAULT, cancellable);
                    if (chunk.length == 0) {
                        break;
                    }
                    if (output.data_size + chunk.length > 1024 * 1024) {
                        return null;
                    }
                    output.write_bytes (chunk, cancellable);
                }
                output.close ();
                bytes = output.steal_as_bytes ();
            } finally {
                close_response (stream);
            }

            if (bytes == null) {
                return null;
            }
            var image_stream = new MemoryInputStream.from_bytes (bytes);
            var decoded = yield new Gdk.Pixbuf.from_stream_at_scale_async (
                image_stream, 1024, 1024, true, cancellable
            );
            var icon = fill_icon (decoded);
            var png = icon.bytes.get_data ();
            if (cancellable.is_cancelled () || generation != cache_generation) {
                return null;
            }
            remember_icon (uri, icon);
            try {
                DirUtils.create_with_parents (cache_dir, 0700);
                yield cache_file.replace_contents_async (png, null, false, FileCreateFlags.PRIVATE, cancellable, null);
                if (generation != cache_generation) {
                    yield cache_file.delete_async (Priority.DEFAULT, null);
                    return null;
                }
            } catch (Error e) {
            }
            return icon;
        } catch (Error e) {
            if (!(e is IOError.CANCELLED)) {
                debug ("Unable to load sender avatar");
            }
            return null;
        }
    }

    public static async void clear_cache () throws Error {
        cache_generation++;
        cache.clear ();
        missing.clear ();
        var directory = File.new_for_path (Path.build_filename (
            Environment.get_user_cache_dir (), APPLICATION_ID, "avatars-v3"
        ));
        FileEnumerator enumerator;
        try {
            enumerator = yield directory.enumerate_children_async (
                FileAttribute.STANDARD_NAME, FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, null
            );
        } catch (IOError.NOT_FOUND e) {
            return;
        }
        try {
            while (true) {
                var files = yield enumerator.next_files_async (32, Priority.DEFAULT, null);
                if (files == null) {
                    break;
                }
                foreach (var info in files) {
                    if (Regex.match_simple ("^[a-f0-9]{64}\\.png$", info.get_name ())) {
                        try {
                            yield directory.get_child (info.get_name ()).delete_async (Priority.DEFAULT, null);
                        } catch (IOError.NOT_FOUND e) {
                        }
                    }
                }
            }
        } finally {
            try {
                enumerator.close (null);
            } catch (Error e) {
                debug ("Unable to close avatar cache directory");
            }
        }
    }

    private static BytesIcon fill_icon (Gdk.Pixbuf image) throws Error {
        int edge = int.min (image.width, image.height);
        var crop = new Gdk.Pixbuf.subpixbuf (image, (image.width - edge) / 2,
            (image.height - edge) / 2, edge, edge);
        var square = crop.scale_simple (512, 512, Gdk.InterpType.BILINEAR);
        uint8[] png;
        square.save_to_buffer (out png, "png");
        return new BytesIcon (new Bytes (png));
    }

    private static void close_response (InputStream stream) {
        stream.close_async.begin (Priority.DEFAULT, null, (obj, res) => {
            try {
                stream.close_async.end (res);
            } catch (Error e) {
                debug ("Unable to close avatar response: %s", e.message);
            }
        });
    }

    private static void remember_icon (string uri, BytesIcon icon) {
        if (cache.size >= 256) {
            cache.clear ();
        }
        cache[uri] = icon;
    }
}
