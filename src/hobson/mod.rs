//! Private three-device policy for Hobson Remote.
//!
//! The device list is `flutter/assets/hobson_devices.json` (compiled into the
//! binary). The shared trust secret is **not** in that file. `build.rs` reads
//! `HOBSON_TRUST_SECRET` or the gitignored `hobson/secret` and exposes it as
//! `option_env!("HOBSON_TRUST_SECRET")`.
//!
//! Trust model: a peer is accepted only when both of these hold.
//! 1. Its RustDesk ID is in the device list. The ID in the login message is
//!    self-reported, so this list is a filter, not a proof.
//! 2. It proves the build-time secret. That secret is the permanent password.
//!    RustDesk's login hashes it with the salt and challenge from this device,
//!    so the password is not sent in the clear. An allowlisted ID with no
//!    secret is rejected with no accept prompt.
//!
//! The Windows install name cannot contain a space (`validate_install_app_name`),
//! so the service and config directory use `HobsonRemote`. The window title
//! and Android label use `Hobson Remote`.

#[path = "log.rs"]
mod conn_log;

use base::config::keys;
use hbb_common::{
    config::{self, Config, LocalConfig},
    log,
};
use serde::Deserialize;

const DEVICES_JSON: &str = include_str!("../../flutter/assets/hobson_devices.json");
const NONE_ID: &str = "__hobson_none__";
const OPT_RELAY: &str = "hobson-relay";
const OPT_PRIVACY: &str = "hobson-privacy";

#[derive(Clone, Debug, Deserialize)]
struct File {
    #[serde(default = "default_app_name")]
    app_name: String,
    #[serde(default = "default_display_name")]
    display_name: String,
    #[serde(default = "default_true")]
    relay_by_default: bool,
    #[serde(default)]
    privacy_on_trusted_windows: bool,
    #[serde(default)]
    devices: Vec<Device>,
}

fn default_app_name() -> String {
    "HobsonRemote".to_owned()
}

fn default_display_name() -> String {
    "Hobson Remote".to_owned()
}

fn default_true() -> bool {
    true
}

#[derive(Clone, Debug, Deserialize)]
#[allow(dead_code)]
struct Device {
    #[serde(default)]
    slot: String,
    #[serde(default)]
    name: String,
    #[serde(default)]
    hostname: String,
    #[serde(default)]
    id: String,
    #[serde(default)]
    os: String,
    #[serde(default)]
    mac: String,
    #[serde(default)]
    lan_prefix: String,
}

impl Device {
    fn id(&self) -> &str {
        self.id.trim()
    }
}

fn file() -> &'static File {
    use std::sync::OnceLock;
    static FILE: OnceLock<File> = OnceLock::new();
    FILE.get_or_init(|| match serde_json::from_str::<File>(DEVICES_JSON) {
        Ok(file) => file,
        Err(err) => {
            eprintln!("Hobson Remote device list failed to parse: {err}");
            File {
                app_name: default_app_name(),
                display_name: default_display_name(),
                relay_by_default: true,
                privacy_on_trusted_windows: false,
                devices: Vec::new(),
            }
        }
    })
}

pub fn active() -> bool {
    true
}

pub fn install_identity() {
    *config::APP_NAME.write().unwrap() = file().app_name.clone();
}

fn known_ids() -> Vec<String> {
    let mut ids = Vec::new();
    for device in &file().devices {
        let id = device.id();
        if !id.is_empty() && !ids.iter().any(|have| have == id) {
            ids.push(id.to_owned());
        }
    }
    ids
}

fn whitelist_value() -> String {
    let ids = known_ids();
    if ids.is_empty() {
        NONE_ID.to_owned()
    } else {
        ids.join(",")
    }
}

pub fn allows(id: &str) -> bool {
    let id = id.trim();
    !id.is_empty() && known_ids().iter().any(|known| known == id)
}

pub fn check_outgoing(id: &str) -> Result<(), String> {
    if allows(id) {
        Ok(())
    } else {
        Err(format!(
            "Hobson Remote only connects to devices listed in flutter/assets/hobson_devices.json (refused {id})"
        ))
    }
}

fn trust_secret() -> &'static str {
    option_env!("HOBSON_TRUST_SECRET").unwrap_or("").trim()
}

pub fn trust_configured() -> bool {
    !trust_secret().is_empty()
}

/// Plaintext secret for an allowlisted peer, used only to build the login hash.
pub fn trust_password_for(peer_id: &str) -> Option<String> {
    let secret = trust_secret();
    if secret.is_empty() || !allows(peer_id) {
        None
    } else {
        Some(secret.to_owned())
    }
}

fn local_yes(key: &str, default_yes: bool) -> bool {
    match LocalConfig::get_option(key).as_str() {
        "Y" => true,
        "N" => false,
        _ => default_yes,
    }
}

pub fn relay_enabled() -> bool {
    local_yes(OPT_RELAY, file().relay_by_default)
}

pub fn privacy_on_connect() -> bool {
    if !cfg!(windows) {
        return false;
    }
    local_yes(OPT_PRIVACY, file().privacy_on_trusted_windows)
}

/// Apply identity-independent policy. Call after [`install_identity`] and after
/// `APP_DIR` is set on Android, and before connections are accepted.
pub fn apply_policy() {
    install_identity();
    {
        let mut hard = config::HARD_SETTINGS.write().unwrap();
        hard.insert("disable-account".to_owned(), "Y".to_owned());
        hard.insert("disable-ab".to_owned(), "Y".to_owned());
    }
    {
        let mut over = config::OVERWRITE_SETTINGS.write().unwrap();
        over.insert(keys::OPTION_APPROVE_MODE.to_owned(), "password".to_owned());
        over.insert(
            keys::OPTION_VERIFICATION_METHOD.to_owned(),
            "use-permanent-password".to_owned(),
        );
        over.insert("allow-hide-cm".to_owned(), "Y".to_owned());
        over.insert(keys::OPTION_ID_WHITELIST.to_owned(), whitelist_value());
        over.insert("enable-lan-discovery".to_owned(), "N".to_owned());
        over.insert(keys::OPTION_ENABLE_FILE_TRANSFER.to_owned(), "Y".to_owned());
        over.insert(keys::OPTION_ENABLE_CLIPBOARD.to_owned(), "Y".to_owned());
        over.insert(keys::OPTION_ENABLE_PRIVACY_MODE.to_owned(), "Y".to_owned());
    }
    let secret = trust_secret();
    if secret.is_empty() {
        log::warn!(
            "HOBSON_TRUST_SECRET is unset. Listed devices cannot auto-accept until you rebuild with the secret."
        );
    } else {
        config::BUILTIN_SETTINGS.write().unwrap().insert(
            keys::OPTION_DEFAULT_CONNECT_PASSWORD.to_owned(),
            secret.to_owned(),
        );
        if !Config::set_permanent_password(secret) {
            log::warn!("Hobson Remote could not store the shared permanent password");
        }
    }
    log::info!(
        "{} ready. allowlist={} relay_default={} trust_secret={}",
        file().display_name,
        whitelist_value(),
        file().relay_by_default,
        if secret.is_empty() { "missing" } else { "set" }
    );
}

pub fn on_outgoing_open(id: &str) {
    conn_log::begin_outgoing(id);
}

pub fn on_outgoing_closed(id: &str) {
    conn_log::end_outgoing(id);
}

pub fn on_incoming_open(conn_id: i32, id: &str, name: &str) {
    conn_log::begin_incoming(conn_id, id, name);
}

pub fn on_incoming_closed(conn_id: i32) {
    conn_log::end_incoming(conn_id);
}

pub fn on_rejected(id: &str, name: &str, ip: &str) {
    let label = if name.is_empty() { id } else { name };
    let text = format!("Blocked a connection from {label} ({id})");
    conn_log::denied(id, name, ip);
    notify(&text);
    #[cfg(feature = "flutter")]
    {
        let evt = serde_json::json!({
            "name": "hobson_alert",
            "id": id,
            "peer": name,
            "text": text,
        });
        if let Ok(evt) = serde_json::to_string(&evt) {
            crate::flutter::push_global_event(crate::flutter::APP_TYPE_MAIN, evt);
        }
    }
}

fn notify(text: &str) {
    #[cfg(windows)]
    {
        use tauri_winrt_notification::{Duration, Sound, Toast};
        let _ = Toast::new(Toast::POWERSHELL_APP_ID)
            .title(&file().display_name)
            .text1(text)
            .sound(Some(Sound::Default))
            .duration(Duration::Short)
            .show();
    }
    #[cfg(target_os = "linux")]
    {
        let _ = std::process::Command::new("notify-send")
            .arg(&file().display_name)
            .arg(text)
            .spawn();
    }
    #[cfg(not(any(windows, target_os = "linux")))]
    {
        log::warn!("{text}");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn device_list_has_the_three_machines() {
        let devices = &file().devices;
        assert_eq!(devices.len(), 3);
        assert_eq!(file().app_name, "HobsonRemote");
        assert_eq!(devices[0].hostname, "DESKTOP-T5EC28K");
        assert_eq!(devices[0].id(), "526130151");
        assert_eq!(devices[1].id(), "199304064");
        assert_eq!(devices[2].id(), "1084254837");
        assert!(devices[0].mac.contains("58-04-4F-F1-38-DF"));
    }

    #[test]
    fn allowlist_rejects_unknown_and_blank_ids() {
        assert!(allows("526130151"));
        assert!(allows("199304064"));
        assert!(allows("1084254837"));
        assert!(allows(" 199304064"));
        assert!(!allows(""));
        assert!(!allows("123"));
        assert!(!allows("19930406"));
        assert_eq!(
            whitelist_value(),
            "526130151,199304064,1084254837"
        );
    }
}
