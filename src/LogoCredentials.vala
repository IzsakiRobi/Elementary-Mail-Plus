/* SPDX-License-Identifier: GPL-3.0-or-later */
public class Mail.LogoCredentials : Object {
    private static LogoCredentials? instance;
    private Secret.Schema schema;
    public string? key { get; private set; }
    public bool ready { get; private set; }
    public signal void changed ();

    public static unowned LogoCredentials get_default () {
        if (instance == null) {
            instance = new LogoCredentials ();
        }
        return instance;
    }

    construct {
        schema = new Secret.Schema (APPLICATION_ID + ".LogoDev", Secret.SchemaFlags.NONE,
            "service", Secret.SchemaAttributeType.STRING);
        load.begin ();
    }

    public async void ensure_ready () {
        if (ready) {
            return;
        }
        var handler = notify["ready"].connect (() => ensure_ready.callback ());
        yield;
        disconnect (handler);
    }

    private async void load () {
        try {
            key = yield Secret.password_lookup (schema, null, "service", "logo.dev");
        } catch (Error e) {
            debug ("Unable to load Logo.dev key from the keyring");
        }
        ready = true;
        changed ();
    }

    public async void save (string value) throws Error {
        string normalized = value.strip ();
        if (normalized != "" && !Regex.match_simple ("^pk_[A-Za-z0-9_-]+$", normalized)) {
            throw new IOError.INVALID_ARGUMENT (_("Enter the Logo.dev publishable key beginning with pk_. The image API does not use an sk_ secret key."));
        }
        if (normalized == "") {
            yield Secret.password_clear (schema, null, "service", "logo.dev");
        } else if (!yield Secret.password_store (schema, Secret.COLLECTION_DEFAULT,
            "Mail — Logo.dev API key", normalized, null, "service", "logo.dev")) {
            throw new IOError.FAILED (_("The API key could not be saved in the keyring."));
        }
        key = normalized == "" ? null : normalized;
        changed ();
    }
}
