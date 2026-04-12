// KWallet access via P5Support.DataSource (executable engine).
// Adapted from plasma-meets SecureHelper.qml.
// Usage: WalletHelper { id: wallet }
//   wallet.readSecret("caldav-password", function(pass) { ... })
//   wallet.writeSecret("caldav-password", "value")
//   wallet.clearSecret("caldav-password")
//   wallet.hasEntry("caldav-password", function(has) { ... })
import QtQuick
import org.kde.plasma.plasma5support as P5Support

Item {
    id: walletRoot
    visible: false

    readonly property string helperPath: {
        var url = Qt.resolvedUrl("../bin/wallet-helper.sh").toString()
        return url.startsWith("file://") ? decodeURIComponent(url.slice(7)) : url
    }

    readonly property string googleAuthPath: {
        var url = Qt.resolvedUrl("../bin/google-auth.py").toString()
        return url.startsWith("file://") ? decodeURIComponent(url.slice(7)) : url
    }

    property var _pending: ({})

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var cb = walletRoot._pending[sourceName]
            executable.disconnectSource(sourceName)
            delete walletRoot._pending[sourceName]
            if (cb) cb(data || {})
        }
    }

    function _quoteArg(v) {
        return "'" + String(v).replace(/'/g, "'\"'\"'") + "'"
    }

    function _run(args, callback) {
        var parts = [_quoteArg(helperPath)]
        for (var i = 0; i < args.length; ++i)
            parts.push(_quoteArg(args[i]))
        var cmd = parts.join(" ")
        _pending[cmd] = callback
        executable.connectSource(cmd)
    }

    function _stdout(data) {
        if (!data) return ""
        var out = data["stdout"] !== undefined ? data["stdout"]
                : data["standard output"] !== undefined ? data["standard output"]
                : ""
        return String(out).replace(/\r?\n$/, "")
    }

    // Read a secret. callback(value: string) — empty string if not set.
    function readSecret(entry, callback) {
        _run(["wallet-read", entry], function(data) {
            callback(_stdout(data))
        })
    }

    // Write a secret. Optional callback() when done.
    function writeSecret(entry, value, callback) {
        _run(["wallet-write", entry, String(value || "")], callback || function() {})
    }

    // Delete a secret.
    function clearSecret(entry, callback) {
        _run(["wallet-clear", entry], callback || function() {})
    }

    // Check if a secret exists. callback(has: bool)
    function hasEntry(entry, callback) {
        _run(["wallet-has", entry], function(data) {
            callback(_stdout(data) === "true")
        })
    }

    // Open browser OAuth2 flow for Google Tasks.
    // callback(tokensJson: string) — JSON string with access_token, refresh_token, etc.
    function googleAuth(clientId, clientSecret, callback) {
        var parts = [
            _quoteArg("python3"),
            _quoteArg(googleAuthPath),
            _quoteArg(clientId),
            _quoteArg(clientSecret)
        ]
        var cmd = parts.join(" ")
        _pending[cmd] = function(data) { callback(_stdout(data)) }
        executable.connectSource(cmd)
    }
}
