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
#[cfg(windows)]
mod banner;
#[cfg(windows)]
mod preview;

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
    idle_disconnect_minutes: u64,
    #[allow(dead_code)]
    #[serde(default = "default_free_gb")]
    free_space_gb: u64,
    #[allow(dead_code)]
    #[serde(default)]
    keep_awake_processes: Vec<String>,
    #[allow(dead_code)]
    #[serde(default = "default_clipboard_history")]
    clipboard_history: usize,
    #[serde(default)]
    tile_previews: bool,
    #[allow(dead_code)]
    #[serde(default = "default_preview_seconds")]
    preview_seconds: u64,
    #[allow(dead_code)]
    #[serde(default = "default_true")]
    clipboard_sync: bool,
    #[allow(dead_code)]
    #[serde(default)]
    watch_titles: bool,
    #[allow(dead_code)]
    #[serde(default)]
    title_patterns: Vec<String>,
    #[serde(default)]
    devices: Vec<Device>,
}

fn default_free_gb() -> u64 {
    10
}

fn default_clipboard_history() -> usize {
    10
}

fn default_preview_seconds() -> u64 {
    45
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
    aliases: Vec<String>,
    #[serde(default)]
    os: String,
    #[serde(default)]
    mac: String,
    #[serde(default)]
    lan_prefix: String,
    #[serde(default = "default_true")]
    enabled: bool,
    #[serde(default)]
    role: String,
    #[serde(default)]
    profile: String,
    #[serde(default)]
    quality_from_phone: String,
    #[serde(default)]
    quality_from_desktop: String,
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
                idle_disconnect_minutes: 0,
                free_space_gb: default_free_gb(),
                keep_awake_processes: Vec::new(),
                clipboard_history: default_clipboard_history(),
                tile_previews: false,
                preview_seconds: default_preview_seconds(),
                clipboard_sync: true,
                watch_titles: false,
                title_patterns: Vec::new(),
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
        if !device.enabled {
            continue;
        }
        let mut device_ids = vec![device.id().to_owned()];
        device_ids.extend(device.aliases.iter().map(|alias| alias.trim().to_owned()));
        for id in device_ids {
            if !id.is_empty() && !ids.iter().any(|have| have == &id) {
                ids.push(id);
            }
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
    let minutes = file().idle_disconnect_minutes;
    if minutes == 0 {
        Config::set_option("allow-auto-disconnect".into(), "N".into());
    } else {
        Config::set_option("allow-auto-disconnect".into(), "Y".into());
        Config::set_option("auto-disconnect-timeout".into(), minutes.to_string());
    }
    start_keep_awake();
    start_title_watch();
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
    let text = format!(
        "Refused ID {id}. Add it to flutter/assets/hobson_devices.json and rebuild. ({label})"
    );
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

const OPT_PANIC: &str = "hobson-panic";

pub fn panic_locked() -> bool {
    LocalConfig::get_option(OPT_PANIC) == "Y"
}

pub fn set_panic(on: bool) {
    LocalConfig::set_option(
        OPT_PANIC.to_owned(),
        if on { "Y".to_owned() } else { String::new() },
    );
}

pub fn clear_panic() {
    set_panic(false);
}

pub fn is_helper(id: &str) -> bool {
    let id = id.trim();
    file().devices.iter().any(|device| {
        device.enabled && device.role == "helper" && device.id() == id
    })
}

pub fn handle_cli() -> bool {
    let mut args = std::env::args().skip(1);
    if args.next().as_deref() != Some("--hobson-notify") {
        return false;
    }
    let text = args
        .next()
        .filter(|text| !text.trim().is_empty())
        .unwrap_or_else(|| "Agent needs you".to_owned());
    record_alert(&text);
    notify(&text);
    true
}

pub fn notify_local(text: &str) {
    notify(text);
}

fn record_alert(text: &str) {
    let path = Config::path("hobson-alerts.json");
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let mut events = std::fs::read(&path)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Vec<serde_json::Value>>(&bytes).ok())
        .unwrap_or_default();
    events.push(serde_json::json!({
        "t": hbb_common::get_time(),
        "text": text,
        "state": "open",
    }));
    if events.len() > 20 {
        let drop_n = events.len() - 20;
        events.drain(0..drop_n);
    }
    let _ = std::fs::write(&path, serde_json::to_vec(&events).unwrap_or_default());
}

fn start_keep_awake() {
    #[cfg(windows)]
    {
        use std::sync::atomic::{AtomicBool, Ordering};
        static STARTED: AtomicBool = AtomicBool::new(false);
        if STARTED.swap(true, Ordering::SeqCst) {
            return;
        }
        let names = if file().keep_awake_processes.is_empty() {
            vec!["claude.exe".to_owned(), "cargo.exe".to_owned()]
        } else {
            file().keep_awake_processes.clone()
        };
        std::thread::spawn(move || {
            let mut lock: Option<crate::platform::windows::WakeLock> = None;
            loop {
                let running = agent_running(&names);
                if running && lock.is_none() {
                    lock = Some(crate::platform::windows::WakeLock::new(false, true, true));
                } else if !running {
                    lock = None;
                }
                std::thread::sleep(std::time::Duration::from_secs(20));
            }
        });
    }
}

#[cfg(windows)]
fn agent_running(names: &[String]) -> bool {
    let Ok(output) = std::process::Command::new("tasklist").output() else {
        return false;
    };
    let text = String::from_utf8_lossy(&output.stdout).to_ascii_lowercase();
    names
        .iter()
        .any(|name| text.contains(&name.to_ascii_lowercase()))
}

pub fn tile_previews() -> bool {
    file().tile_previews
}

#[allow(dead_code)]
pub fn clipboard_sync_enabled() -> bool {
    file().clipboard_sync
}

#[allow(dead_code)]
pub fn preview_seconds() -> u64 {
    let seconds = file().preview_seconds;
    if seconds == 0 {
        default_preview_seconds()
    } else {
        seconds
    }
}

pub fn capture_primary_jpeg() -> Option<Vec<u8>> {
    #[cfg(windows)]
    {
        preview::primary_jpeg(320)
    }
    #[cfg(not(windows))]
    {
        None
    }
}

pub fn window_titles() -> Vec<String> {
    #[cfg(windows)]
    {
        preview::window_titles()
    }
    #[cfg(not(windows))]
    {
        Vec::new()
    }
}

pub fn capture_named_window(title: &str) -> Option<Vec<u8>> {
    #[cfg(windows)]
    {
        preview::window_jpeg(title, 480)
    }
    #[cfg(not(windows))]
    {
        let _ = title;
        None
    }
}

pub fn helper_arrived(label: &str) {
    #[cfg(windows)]
    banner::show(label);
    #[cfg(not(windows))]
    {
        let _ = label;
    }
}

pub fn helper_left() {
    #[cfg(windows)]
    banner::hide();
}

pub fn title_matches(title: &str, patterns: &[String]) -> bool {
    let lower = title.to_lowercase();
    patterns.iter().any(|pattern| {
        let pattern = pattern.trim().to_lowercase();
        !pattern.is_empty() && lower.contains(&pattern)
    })
}

pub fn merge_clip_lists(incoming: &[String], existing: &[String], limit: usize) -> Vec<String> {
    let limit = limit.max(1);
    let mut merged = Vec::new();
    for text in incoming.iter().chain(existing.iter()) {
        let text = text.trim();
        if text.is_empty() || merged.iter().any(|have: &String| have == text) {
            continue;
        }
        merged.push(text.to_owned());
        if merged.len() == limit {
            break;
        }
    }
    merged
}

pub fn ingest_clips(body: &str) -> String {
    let incoming = serde_json::from_str::<Vec<String>>(body).unwrap_or_default();
    let path = Config::path("hobson-clips.json");
    if let Some(dir) = path.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let existing = std::fs::read(&path)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Vec<String>>(&bytes).ok())
        .unwrap_or_default();
    let merged = merge_clip_lists(&incoming, &existing, file().clipboard_history);
    let _ = std::fs::write(&path, serde_json::to_vec(&merged).unwrap_or_default());
    serde_json::to_string(&merged).unwrap_or_else(|_| "[]".to_owned())
}

pub fn latest_alert() -> String {
    let path = Config::path("hobson-alerts.json");
    let Ok(bytes) = std::fs::read(path) else {
        return String::new();
    };
    let Ok(events) = serde_json::from_slice::<Vec<serde_json::Value>>(&bytes) else {
        return String::new();
    };
    events
        .iter()
        .rev()
        .find_map(|event| {
            if event.get("state").and_then(|state| state.as_str()) == Some("open") {
                event
                    .get("text")
                    .and_then(|text| text.as_str())
                    .map(|text| text.replace(['\n', '\r'], " "))
            } else {
                None
            }
        })
        .unwrap_or_default()
}

pub fn ack_alert() {
    let path = Config::path("hobson-alerts.json");
    let Ok(bytes) = std::fs::read(&path) else {
        return;
    };
    let Ok(mut events) = serde_json::from_slice::<Vec<serde_json::Value>>(&bytes) else {
        return;
    };
    if let Some(event) = events.iter_mut().rev().find(|event| {
        event.get("state").and_then(|state| state.as_str()) == Some("open")
    }) {
        event["state"] = serde_json::Value::String("done".to_owned());
    }
    let _ = std::fs::write(path, serde_json::to_vec(&events).unwrap_or_default());
}

fn start_title_watch() {
    #[cfg(windows)]
    {
        use std::sync::atomic::{AtomicBool, Ordering};
        static STARTED: AtomicBool = AtomicBool::new(false);
        if !file().watch_titles || STARTED.swap(true, Ordering::SeqCst) {
            return;
        }
        let patterns = if file().title_patterns.is_empty() {
            vec![
                "waiting for your input".to_owned(),
                "approve this action".to_owned(),
                "needs you".to_owned(),
            ]
        } else {
            file().title_patterns.clone()
        };
        std::thread::spawn(move || {
            let mut seen: Vec<(String, std::time::Instant)> = Vec::new();
            loop {
                for title in window_titles() {
                    if !title_matches(&title, &patterns) {
                        continue;
                    }
                    let now = std::time::Instant::now();
                    let recent = seen.iter().any(|(have, at)| {
                        have == &title && now.duration_since(*at).as_secs() < 180
                    });
                    if recent {
                        continue;
                    }
                    seen.retain(|(_, at)| now.duration_since(*at).as_secs() < 180);
                    seen.push((title.clone(), now));
                    let text = format!("Agent needs you: {title}");
                    record_alert(&text);
                    notify(&text);
                }
                std::thread::sleep(std::time::Duration::from_secs(5));
            }
        });
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
        assert_eq!(devices.len(), 4);
        assert!(!devices[3].enabled);
        assert_eq!(devices[3].role, "helper");
        assert_eq!(file().app_name, "HobsonRemote");
        assert_eq!(devices[0].hostname, "DESKTOP-T5EC28K");
        assert_eq!(devices[0].id(), "526130151");
        assert_eq!(devices[1].id(), "199304064");
        assert_eq!(devices[2].id(), "1374413193");
        assert_eq!(devices[2].aliases, vec!["1084254837"]);
        assert!(devices[0].mac.contains("58-04-4F-F1-38-DF"));
    }

    #[test]
    fn allowlist_rejects_unknown_and_blank_ids() {
        assert!(allows("526130151"));
        assert!(allows("199304064"));
        assert!(allows("1374413193"));
        assert!(allows("1084254837"));
        assert!(allows(" 199304064"));
        assert!(!allows(""));
        assert!(!allows("123"));
        assert!(!allows("19930406"));
        assert_eq!(
            whitelist_value(),
            "526130151,199304064,1374413193,1084254837"
        );
    }

    #[test]
    fn clipboard_merge_keeps_newest_unique_items() {
        let merged = merge_clip_lists(
            &["newest".into(), "kept".into()],
            &["kept".into(), "older".into(), " ".into()],
            3,
        );
        assert_eq!(merged, vec!["newest", "kept", "older"]);
        assert!(title_matches(
            "Claude Code — waiting for your input",
            &["waiting for your input".into()]
        ));
        assert!(!title_matches("cargo build", &["waiting for your input".into()]));
    }
}
