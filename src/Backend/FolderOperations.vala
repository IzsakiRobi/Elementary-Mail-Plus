/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class Mail.FolderOperations : Object {
    public static bool valid_name (string name) {
        var value = name.strip ();
        return value != "" && value != "." && value != ".."
            && !value.contains ("/") && !value.contains ("\r") && !value.contains ("\n");
    }

    public static bool is_within (string path, string parent) {
        return path == parent || path.has_prefix (parent + "/");
    }

    public static bool is_protected (Camel.Store store, Camel.FolderInfo info) {
        var flags = Utils.get_full_folder_info_flags (store, info);
        return (flags & Camel.FOLDER_TYPE_MASK) != Camel.FolderInfoFlags.TYPE_NORMAL
            || (flags & (Camel.FolderInfoFlags.SYSTEM | Camel.FolderInfoFlags.VIRTUAL | Camel.FolderInfoFlags.READONLY)) != 0;
    }

    public static async Camel.FolderInfo create (Camel.Store store, string? parent, string name, Cancellable? cancellable = null) throws Error {
        var normalized = name.strip ();
        if (!valid_name (normalized)) {
            throw new IOError.INVALID_ARGUMENT (_("Enter a folder name without slashes or line breaks."));
        }
        if (parent != null) {
            var info = yield store.get_folder_info (parent, Camel.StoreGetFolderInfoFlags.FAST, Priority.DEFAULT, cancellable);
            if (info == null || info.full_name != parent
                || (info.flags & (Camel.FolderInfoFlags.VIRTUAL | Camel.FolderInfoFlags.NOINFERIORS | Camel.FolderInfoFlags.READONLY)) != 0) {
                throw new IOError.NOT_SUPPORTED (_("This folder cannot contain subfolders."));
            }
        }
        var created = yield store.create_folder (parent, normalized, Priority.DEFAULT, cancellable);
        if (created == null) {
            throw new IOError.FAILED (_("The server did not create the folder."));
        }
        if (parent != null) {
            created.full_name = parent + "/" + normalized;
        }
        if (store is Camel.Subscribable) {
            try {
                if (!yield ((Camel.Subscribable) store).subscribe_folder (created.full_name, Priority.DEFAULT, cancellable)) {
                    throw new IOError.FAILED (_("The server rejected the subscription."));
                }
            } catch (Error e) {
                if (e is IOError.CANCELLED) {
                    throw e;
                }
                throw new IOError.FAILED (_("The folder was created, but could not be subscribed: %s").printf (e.message));
            }
        }
        return created;
    }

    public static async string move_to_trash (Camel.Store store, string path, Cancellable? cancellable = null) throws Error {
        var source = yield store.get_folder_info (path,
            Camel.StoreGetFolderInfoFlags.RECURSIVE | Camel.StoreGetFolderInfoFlags.NO_VIRTUAL,
            Priority.DEFAULT, cancellable);
        if (source == null || source.full_name != path) {
            throw new IOError.NOT_FOUND (_("The folder no longer exists."));
        }
        validate_tree (store, source);
        var trash = yield store.get_trash_folder (Priority.DEFAULT, cancellable);
        if (trash == null || trash is Camel.VTrashFolder || is_within (path, trash.full_name)
            || is_within (trash.full_name, path)) {
            throw new IOError.NOT_SUPPORTED (_("A separate server Trash folder is required to move this folder."));
        }
        var trash_info = yield store.get_folder_info (trash.full_name,
            Camel.StoreGetFolderInfoFlags.RECURSIVE | Camel.StoreGetFolderInfoFlags.NO_VIRTUAL,
            Priority.DEFAULT, cancellable);
        if (trash_info == null || trash_info.full_name != trash.full_name
            || (trash_info.flags & (Camel.FolderInfoFlags.NOINFERIORS | Camel.FolderInfoFlags.READONLY)) != 0) {
            throw new IOError.NOT_SUPPORTED (_("The server Trash folder cannot contain subfolders."));
        }
        var existing = new Gee.HashSet<string> ();
        collect_names (trash_info, existing);
        var leaf = path.substring (path.last_index_of ("/") + 1);
        var destination = trash.full_name + "/" + leaf;
        for (int suffix = 2; existing.contains (destination.casefold ()); suffix++) {
            destination = "%s/%s (%d)".printf (trash.full_name, leaf, suffix);
        }
        if (!yield store.rename_folder (path, destination, Priority.DEFAULT, cancellable)) {
            throw new IOError.FAILED (_("The server could not move the folder to Trash."));
        }
        return destination;
    }

    private static void validate_tree (Camel.Store store, Camel.FolderInfo info) throws Error {
        if (is_protected (store, info)) {
            throw new IOError.PERMISSION_DENIED (_("System folders and read-only folders cannot be moved to Trash."));
        }
        unowned Camel.FolderInfo? child = (Camel.FolderInfo?) info.child;
        while (child != null) {
            validate_tree (store, child);
            child = (Camel.FolderInfo?) child.next;
        }
    }

    private static void collect_names (Camel.FolderInfo info, Gee.Set<string> names) {
        names.add (info.full_name.casefold ());
        unowned Camel.FolderInfo? child = (Camel.FolderInfo?) info.child;
        while (child != null) {
            collect_names (child, names);
            child = (Camel.FolderInfo?) child.next;
        }
    }
}
