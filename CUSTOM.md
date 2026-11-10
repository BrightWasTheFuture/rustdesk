# Custom RustDesk build (private server)

This fork builds a RustDesk client that connects to my own server out of the box.
Work happens on the **`custom`** branch (the default branch of this fork).
`master` is kept as a clean mirror of upstream `rustdesk/rustdesk`.

## Where the server settings live

| Setting | Value | File |
|---|---|---|
| ID / rendezvous server | `65.108.148.37` | `libs/hbb_common/src/config.rs` → `RENDEZVOUS_SERVERS` |
| Relay server | `65.108.148.37:21117` (derived automatically from the ID server + `RELAY_PORT`) | `libs/hbb_common/src/config.rs` |
| Server public key | `nIzF7CmpAnnvOjs5Kv4T3J2xo8CqW9ohSMJdSgFWuhk=` | `libs/hbb_common/src/config.rs` → `RS_PUB_KEY` |
| API server fallback | `http://65.108.148.37:21114` (instead of admin.rustdesk.com) | `src/common.rs` → `get_api_server_` |

`libs/hbb_common` is a git submodule. In this fork `.gitmodules` points it at
**https://github.com/BrightWasTheFuture/hbb_common** (branch `custom`), which carries
the patched `config.rs`. Upstream RustDesk no longer reads `RENDEZVOUS_SERVER` /
`RS_PUB_KEY` environment variables at build time, so the values are compiled in as constants.

### Changing the server or key
1. Edit `src/config.rs` in `BrightWasTheFuture/hbb_common` (branch `custom`) and push.
2. In this repo: `git submodule update --init --remote libs/hbb_common`,
   then `git add libs/hbb_common && git commit -m "bump hbb_common" && git push`.

## Rebuilding (GitHub Actions)

Push a version tag from the `custom` branch, e.g.:

```
git tag 1.5.3-2 && git push origin 1.5.3-2
```

(Tags matching `1.2.3-4` / `v1.2.3` trigger **Flutter Tag Build**.) You can also run
Actions → **Flutter Tag Build** → *Run workflow*, but then the release tag is the
branch name, so a tag push is cleaner. (**Flutter Nightly Build** is disabled on forks
because of its nightly schedule.)

It runs upstream's `.github/workflows/flutter-build.yml` with `upload-artifact: true`
and publishes the results as a pre-release named after the tag in this fork:
- Windows x64: `rustdesk-<ver>-x86_64.exe` (portable/self-installing) and `rustdesk-<ver>-x86_64.msi`
- Android arm64: `rustdesk-<ver>-aarch64-signed.apk`

The upstream workflow also attempts other platforms (Linux, macOS, iOS, web, arm Windows).
This repo is public, so those minutes are free; jobs that need upstream-only secrets
(macOS notarisation, Windows code signing) are skipped or fail harmlessly.

To trim the build to just Windows x64 + Android arm64, add a workflow such as
`.github/workflows/custom-build.yml` (or delete matrix entries in `flutter-build.yml`).
Note: pushing changes under `.github/workflows/` needs a token with the `workflow` scope
(`gh auth refresh -s workflow`) or editing in the GitHub web UI.

### Android signing
The APK is signed with a private keystore stored as repo secrets
`ANDROID_SIGNING_KEY` (base64 keystore), `ANDROID_ALIAS`, `ANDROID_KEY_STORE_PASSWORD`,
`ANDROID_KEY_PASSWORD`. Keep the same keystore for future builds, otherwise Android
will refuse to update the installed app (uninstall first).

## Hobson Remote

This branch turns the Flutter client into a private app for three devices.
The window title and Android label are **Hobson Remote**. The Windows service,
install directory, and config folder are **HobsonRemote** (no space): the
installer rejects spaces in the application name. Android installs as
`com.hobson.remote` (`applicationId` in `flutter/android/app/build.gradle`),
so it can sit next to the official RustDesk app. The Kotlin namespace stays
`com.carriez.flutter_hbb`, which is why activity and service class names in
the APK still use that prefix. `aapt dump badging` on the 1.5.3-3 APK reports
`package: name='com.hobson.remote'`. The first install is a new app; later
updates still need the same `ANDROID_SIGNING_KEY` keystore.

### Device list

Edit one file, then rebuild:

`flutter/assets/hobson_devices.json`

| Slot | Name | Hostname | RustDesk ID |
|---|---|---|---|
| pc | PC | DESKTOP-T5EC28K | `526130151` |
| laptop | Laptop | DESKTOP-0FGJD6S | `199304064` |
| phone | Pixel | Pixel 11 Pro XL | `1084254837` |

The PC tile also has MAC `58-04-4F-F1-38-DF` for Wake-on-LAN on `192.168.0.x`.
Rust (`src/hobson/`) and Flutter both read this file. To change an ID, edit
the JSON and rebuild. Do not put the trust secret in this file.

### Trust secret

Listed devices accept each other with no prompt only when **both** are true:

1. The peer's RustDesk ID is in the device list. That ID is self-reported in
   the login message, so the list is a filter, not a proof of identity.
2. The peer proves a shared secret. The secret is stored as this device's
   permanent password. Login hashes it with the salt and challenge from the
   controlled device, so the password is not sent in the clear. A connection
   that only claims an allowlisted ID, or that sends no password, is refused
   before any accept prompt, and the app raises an alert.

The secret is compiled in. It is never committed.

- Local build: copy `hobson/secret.example` to `hobson/secret` (gitignored)
  and put the passphrase on one line, or export `HOBSON_TRUST_SECRET`.
- GitHub Actions: set the repo secret `HOBSON_TRUST_SECRET` to the same
  passphrase. `.github/workflows/flutter-build.yml` passes it into the build.
  Pushing that workflow file needs a token with the `workflow` scope.

Use the same secret for every device. A build with no secret still compiles,
but trusted auto-accept stays off and incoming logins are refused.

Changing the secret means rebuilding and reinstalling all three devices.
Until they all have the new secret, they cannot connect to each other.

### What the home screen does

The launch screen is three tiles (PC, Laptop, Pixel) with online/offline from
the existing peer online query, and one-tap connect. The gear opens the
existing settings. Connections always use the relay unless you turn off
**Always use the relay** on the home screen (that toggle is not written onto
the peer, so you can turn it back on). On Windows, **Blank this screen for
trusted sessions** turns on RustDesk privacy mode when a listed device
connects. It is off until you enable it.

The session toolbar keeps fullscreen, file transfer, clipboard, Ctrl+Alt+Del,
privacy screen, and disconnect. Address book, account login, LAN discovery,
rustdesk.com promotions, and the public update check are not shown. The
update request to `api.rustdesk.com` is skipped. The API fallback stays the
private server from `hbb_common`.

Drag a file onto a desktop tile to open a file transfer and send it to that
device's Downloads folder (or its home folder if Downloads cannot be opened).
On Android, the share sheet entry **Send to PC/Laptop** copies the files and
asks which listed device to send them to. The Quick Settings tile **Share
screen** starts or stops the phone's screen share; the system capture consent
dialog still appears the first time.

**Wake PC** sends a Wake-on-LAN magic packet to `255.255.255.255` and
`192.168.0.255`. It only works from a device on that LAN, and only if the
PC's BIOS and NIC have Wake-on-LAN enabled.

The history icon opens the connection log (time, device, duration, and
blocked attempts). The log file is `hobson-connections.json` in the
HobsonRemote config directory. A blocked ID also raises a system notification
(Windows toast, Linux `notify-send`, Android notification).

### Customising further

Flutter UI for the new screen is `flutter/lib/hobson/`. Policy (allowlist,
password, relay, privacy) is `src/hobson/`. Commit to `custom` and push a
version tag to rebuild, as below.

## Daily use

These switches live in `flutter/assets/hobson_devices.json`.

`idle_disconnect_minutes` uses RustDesk's existing inactivity timer (mouse and keyboard reset it). `0` leaves it off. `free_space_gb` warns on a Windows home screen when C: is below that many gigabytes. `keep_awake_processes` is the list of process names that hold a Windows wake lock while they are running. `clipboard_history` is how many clipboard texts are kept. `clipboard_sync` (default on) exchanges that list with the other listed devices over a short chat-only connection. `tile_previews` (default off) asks those same connections for one small JPEG of the primary monitor; `preview_seconds` is how often the home screen asks (default 45). `watch_titles` (default off) on Windows scans visible window titles every few seconds. `title_patterns` are case-insensitive substrings. With the flag on and the list empty, the built-in patterns are `waiting for your input`, `approve this action`, and `needs you`.

Each device can set `enabled` (default true), `role` (`helper` for a later Grok machine), `quality_from_phone`, and `quality_from_desktop` (`low`, `balanced`, or `best`). Connecting from the phone uses the phone quality (default `low`) and turns touch mode on. Connecting from a PC or laptop uses desktop quality (default `best`). A device with `"enabled": false` is shown but cannot be connected to. The Grok entry is that, with an empty ID, until you want it.

View style, zoom, and the last monitor are the values RustDesk already stores per peer. After a network drop to a listed device, the session retries for about three minutes.

Tapping an offline PC tile that has a MAC sends Wake-on-LAN and connects when the online query says it is up, or stops after about 90 seconds.

**Panic lock** on the home screen (and the Android Quick Settings tile of the same name) marks this device so new sessions are refused, asks the other Windows PCs to lock, and locks this PC. **Unlock** on a Windows tile connects with the trust secret and clears the lock without starting a desktop session. A listed device can also send the chat commands `hobson:panic`, `hobson:lock`, `hobson:open https://...`, `hobson:paste ...`, and `hobson:keys y` or `hobson:keys n`.

The prompt box sends `hobson:paste` into the focused window on the PC. Android's share sheet **Open on PC/Laptop** does the same for an `http` or `https` link, which the PC opens in the default browser.

The session **More** menu has **Monitors** (a still thumbnail of each display; tap one to switch), **Low data** (quality `low`, 2 frames per second), and **One window** (a list of window titles; the chosen window is sent as a small JPEG about twice a second and the full desktop video subscription is dropped until you choose **Back to desktop**).

**Screenshot** saves the PNG and, on Windows and Linux and macOS, copies it to the clipboard. On Android it opens the system share sheet so it can go to Grok or any other app.

A helper device shows **Helper has control · Take back** on the viewer's session bar. On the controlled Windows desktop a small always-on-top, click-through banner stays up for as long as that helper is connected. Take back still means disconnecting from the helper's side. The banner is not a button.

### Agent alerts and what Approve cannot do

`HobsonRemote.exe --hobson-notify "message"` writes an alert and shows a Windows toast. The next clipboard/preview sync (or a running session) delivers that text to the phone, which shows Approve and Deny. Those buttons type `y` or `n` and Enter into whatever window is focused on the PC.

Turn on `watch_titles` to raise the same alert when a visible window title contains one of `title_patterns`. A title match is reported at most once every three minutes.

Claude Code can call the same command from its hooks. In the project's `.claude/settings.json` (or `~/.claude/settings.json`):

```json
{
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "HobsonRemote.exe --hobson-notify \"Claude Code needs you\""
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "HobsonRemote.exe --hobson-notify \"Claude Code finished\""
          }
        ]
      }
    ]
  }
}
```

Use the full path to `HobsonRemote.exe` if it is not on `PATH`. Cursor can run the same command from a terminal hook or a user rule when an agent stops.

Approve and Deny cannot accept a Windows UAC prompt. `consent.exe` runs on the secure desktop (the winlogon desktop), which is a different desktop from the one RustDesk captures and the one `hobson:keys` types into. Windows does not give a remote session input or pixels on that desktop unless the session is already elevated and the secure desktop is disabled in policy. Hobson does not do either. A UAC prompt still has to be answered on the PC itself, or by RustDesk's own elevation prompt when that path is available. The Approve button is only for a normal window that is waiting for `y` or `n`.

## Syncing with upstream
`git fetch upstream && git merge upstream/master` on `custom` (and bump the
`hbb_common` fork from `rustdesk/hbb_common` the same way if needed).
