/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

public class Mail.TrashOperations : Object {
    public static async void empty (Camel.Folder folder, Cancellable? cancellable = null) throws Error {
        if (!(Camel.FolderFlags.IS_TRASH in (Camel.FolderFlags) folder.get_flags ())) {
            var trash = yield folder.parent_store.get_trash_folder (Priority.DEFAULT, cancellable);
            if (trash == null || trash.full_name != folder.full_name) {
                throw new IOError.INVALID_ARGUMENT (_("The selected folder is not Trash."));
            }
        }

        unowned var uids = folder.get_uids ();
        folder.freeze ();
        try {
            for (uint i = 0; i < uids.length; i++) {
                var info = folder.get_message_info (uids[i]);
                if (info != null) {
                    info.set_flags (Camel.MessageFlags.DELETED, Camel.MessageFlags.DELETED);
                }
            }
        } finally {
            folder.thaw ();
            folder.free_uids (uids);
        }

        if (!yield folder.synchronize (true, Priority.DEFAULT, cancellable)) {
            throw new IOError.FAILED (_("Failed to empty Trash."));
        }
        yield folder.refresh_info (Priority.DEFAULT, cancellable);
    }
}
