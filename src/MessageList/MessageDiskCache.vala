/* SPDX-License-Identifier: GPL-3.0-or-later */
public class Mail.MessageDiskCache : Object {
    public const uint64 MAX_ENTRY_BYTES = 32 * 1024 * 1024;
    public const uint64 MAX_SOURCE_BYTES = 8 * 1024 * 1024;

    public class Entry : Object {
        public Bytes source;
        public Bytes archive;

        public Entry (Bytes source, Bytes archive) {
            this.source = source;
            this.archive = archive;
        }
    }

    private class CachedFile : Object {
        public File file;
        public uint64 size;
        public uint64 used;
    }

    private static MessageDiskCache? instance;
    private File directory;
    private uint max_entries;
    private uint64 max_bytes;
    private bool pruning;
    private bool prune_again;
    private Gee.HashSet<string> saving = new Gee.HashSet<string> ();
    private Gee.HashSet<string> removed_accounts = new Gee.HashSet<string> ();

    public static MessageDiskCache get_default () {
        if (instance == null) {
            instance = new MessageDiskCache (Path.build_filename (
                Environment.get_user_cache_dir (), "io.elementary.mail", "messages-v1"));
        }
        return instance;
    }

    public MessageDiskCache (string path, uint max_entries = 50, uint64 max_bytes = 256 * 1024 * 1024) {
        directory = File.new_for_path (path);
        this.max_entries = max_entries;
        this.max_bytes = max_bytes;
        DirUtils.create_with_parents (path, 0700);
        prune.begin ();
    }

    public static string key_for (Camel.MessageInfo info) {
        var folder = info.summary.folder;
        var identity = new Variant ("(ss)", folder.full_name, info.uid);
        return account_prefix (folder.parent_store.uid) +
            Checksum.compute_for_string (ChecksumType.SHA256, identity.print (true)) + ".cache";
    }

    private static string legacy_key_for (Camel.MessageInfo info) {
        var folder = info.summary.folder;
        var identity = new Variant ("(sstxxuss)", folder.full_name, info.uid,
            info.message_id, info.date_sent, info.date_received, info.size,
            info.from ?? "", info.subject ?? "");
        return account_prefix (folder.parent_store.uid) +
            Checksum.compute_for_string (ChecksumType.SHA256, identity.print (true)) + ".cache";
    }

    public static bool matches_message (Camel.MessageInfo info, Camel.MimeMessage message) {
        string? id = message.get_message_id ();
        if (info.message_id != 0 && (id == null ||
            Camel.FolderSearch.util_hash_message_id (id, false) != info.message_id)) {
            return false;
        }
        int offset;
        var date = message.get_date (out offset);
        return info.date_sent <= 0 || date <= 0 || info.date_sent == date;
    }

    public async Entry? load_message (Camel.MessageInfo info, bool images_allowed, Cancellable? cancellable = null) {
        string key = key_for (info);
        var entry = yield load (key, images_allowed, cancellable);
        if (entry == null && (cancellable == null || !cancellable.is_cancelled ())) {
            string legacy = legacy_key_for (info);
            entry = yield load (legacy, images_allowed, cancellable);
            if (entry != null) {
                try {
                    yield store (key, images_allowed, entry.source, entry.archive, cancellable);
                    yield discard (legacy);
                } catch (Error e) {
                    debug ("Could not migrate message cache: code %d", e.code);
                }
            }
        }
        return entry;
    }

    private static string account_prefix (string uid) {
        return Checksum.compute_for_string (ChecksumType.SHA256, uid) + "-";
    }

    private bool account_removed (string key) {
        return removed_accounts.contains (key.substring (0, 65));
    }

    public bool begin_save (string key) {
        if (saving.size >= 2 || saving.contains (key) || account_removed (key)) {
            return false;
        }
        saving.add (key);
        return true;
    }

    public void end_save (string key) {
        saving.remove (key);
    }

    public bool should_retry_save (string key) {
        return !saving.contains (key) && !account_removed (key);
    }

    public async Entry? load (string key, bool images_allowed, Cancellable? cancellable = null) {
        if (account_removed (key)) {
            return null;
        }
        var file = directory.get_child (key);
        try {
            var info = yield file.query_info_async (FileAttribute.STANDARD_SIZE + "," + FileAttribute.STANDARD_TYPE,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.DEFAULT, cancellable);
            if (info.get_file_type () != FileType.REGULAR || info.get_size () > MAX_ENTRY_BYTES) {
                return null;
            }
            var bytes = yield file.load_bytes_async (cancellable, null);
            if (bytes.get_size () > MAX_ENTRY_BYTES) {
                return null;
            }
            var value = new Variant.from_bytes (new VariantType ("(bayays)"), bytes, false);
            if (!value.is_normal_form () || value.get_child_value (0).get_boolean () != images_allowed) {
                debug ("Disk cache rejected: format or image policy");
                return null;
            }
            var source = value.get_child_value (1).get_data_as_bytes ();
            var archive = value.get_child_value (2).get_data_as_bytes ();
            if (source.get_size () == 0 || source.get_size () > MAX_SOURCE_BYTES || archive.get_size () == 0) {
                return null;
            }
            if (value.get_child_value (3).get_string () != digest (source, archive)) {
                debug ("Disk cache rejected: checksum");
                return null;
            }
            var touched = new FileInfo ();
            var now = get_real_time ();
            touched.set_attribute_uint64 (FileAttribute.TIME_MODIFIED, (uint64) (now / 1000000));
            touched.set_attribute_uint32 (FileAttribute.TIME_MODIFIED_USEC, (uint32) (now % 1000000));
            try {
                yield file.set_attributes_async (touched, FileQueryInfoFlags.NONE, Priority.LOW, cancellable, null);
            } catch (Error e) {
                if (e is IOError.CANCELLED) {
                    return null;
                }
            }
            return new Entry (source, archive);
        } catch (Error e) {
            if (!(e is IOError.NOT_FOUND) && !(e is IOError.CANCELLED)) {
                debug ("Message disk cache miss: %s", e.message);
            }
            return null;
        }
    }

    private static string digest (Bytes source, Bytes archive) {
        var checksum = new Checksum (ChecksumType.SHA256);
        checksum.update (source.get_data (), source.get_size ());
        checksum.update (archive.get_data (), archive.get_size ());
        return checksum.get_string ();
    }

    public async void store (string key, bool images_allowed, Bytes source, Bytes archive, Cancellable? cancellable = null) throws Error {
        if (source.get_size () == 0 || source.get_size () > MAX_SOURCE_BYTES || archive.get_size () == 0 ||
            source.get_size () + archive.get_size () > MAX_ENTRY_BYTES - 128 || account_removed (key)) {
            return;
        }
        var value = new Variant.tuple ({
            new Variant.boolean (images_allowed),
            new Variant.from_bytes (new VariantType ("ay"), source, true),
            new Variant.from_bytes (new VariantType ("ay"), archive, true),
            new Variant.string (digest (source, archive))
        });
        yield directory.get_child (key).replace_contents_bytes_async (value.get_data_as_bytes (), null,
            false, FileCreateFlags.PRIVATE, cancellable, null);
        if (account_removed (key)) {
            yield discard (key);
        }
        yield prune ();
    }

    public async void discard (string key) {
        try {
            yield directory.get_child (key).delete_async (Priority.LOW, null);
        } catch (Error e) {
            if (!(e is IOError.NOT_FOUND)) {
                debug ("Could not discard cached message: %s", e.message);
            }
        }
    }

    public async void remove_account (string uid) {
        var prefix = account_prefix (uid);
        removed_accounts.add (prefix);
        try {
            var files = yield directory.enumerate_children_async (FileAttribute.STANDARD_NAME,
                FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, null);
            while (true) {
                var batch = yield files.next_files_async (64, Priority.LOW, null);
                if (batch == null) {
                    break;
                }
                foreach (var info in batch) {
                    if (info.get_name ().has_prefix (prefix)) {
                        yield discard (info.get_name ());
                    }
                }
            }
            yield files.close_async (Priority.LOW, null);
        } catch (Error e) {
            debug ("Could not remove account message cache: %s", e.message);
        }
    }

    public void enable_account (string uid) {
        removed_accounts.remove (account_prefix (uid));
    }

    private async void prune () {
        prune_again = true;
        if (pruning) {
            return;
        }
        pruning = true;
        do {
            prune_again = false;
            try {
                var entries = new Gee.ArrayList<CachedFile> ();
                uint64 total = 0;
                var files = yield directory.enumerate_children_async (
                    "standard::name,standard::type,standard::size,time::modified,time::modified-usec",
                    FileQueryInfoFlags.NOFOLLOW_SYMLINKS, Priority.LOW, null);
                while (true) {
                    var batch = yield files.next_files_async (64, Priority.LOW, null);
                    if (batch == null) {
                        break;
                    }
                    foreach (var info in batch) {
                        if (info.get_file_type () == FileType.REGULAR && info.get_name ().has_suffix (".cache")) {
                            var entry = new CachedFile ();
                            entry.file = directory.get_child (info.get_name ());
                            entry.size = info.get_size ();
                            entry.used = info.get_attribute_uint64 (FileAttribute.TIME_MODIFIED) * 1000000 +
                                info.get_attribute_uint32 (FileAttribute.TIME_MODIFIED_USEC);
                            total += entry.size;
                            entries.add (entry);
                        }
                    }
                }
                yield files.close_async (Priority.LOW, null);
                entries.sort ((a, b) => a.used < b.used ? -1 : (a.used > b.used ? 1 : 0));
                int remaining = entries.size;
                foreach (var entry in entries) {
                    if (remaining <= max_entries && total <= max_bytes) {
                        break;
                    }
                    yield entry.file.delete_async (Priority.LOW, null);
                    total -= entry.size;
                    remaining--;
                }
            } catch (Error e) {
                debug ("Could not trim message disk cache: %s", e.message);
            }
        } while (prune_again);
        pruning = false;
    }
}
