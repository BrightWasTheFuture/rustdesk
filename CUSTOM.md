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

## Customising the UI
The Flutter UI lives in `flutter/lib/` (desktop: `flutter/lib/desktop/`, mobile:
`flutter/lib/mobile/`). Rust core is in `src/`. Commit to `custom` and re-run the workflow.

## Syncing with upstream
`git fetch upstream && git merge upstream/master` on `custom` (and bump the
`hbb_common` fork from `rustdesk/hbb_common` the same way if needed).
