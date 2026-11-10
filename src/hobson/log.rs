//! Connection log shared by the UI process and the `--server` process.
//!
//! Entries are a JSON array in the config directory (`hobson-connections.json`),
//! not in the in-memory option cache. The Flutter log screen reads that same
//! path. Keep the path rules in `flutter/lib/hobson/log_page.dart` in sync.

use hbb_common::{config::Config, get_time, log};
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    fs,
    sync::Mutex,
    time::Duration,
};

const MAX_EVENTS: usize = 100;

struct Open {
    at: i64,
    id: String,
    name: String,
}

fn opens() -> &'static Mutex<HashMap<String, Open>> {
    use std::sync::OnceLock;
    static OPENS: OnceLock<Mutex<HashMap<String, Open>>> = OnceLock::new();
    OPENS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn path() -> std::path::PathBuf {
    Config::path("hobson-connections.json")
}

fn append(entry: Value) {
    let path = path();
    if let Some(dir) = path.parent() {
        if let Err(err) = fs::create_dir_all(dir) {
            log::warn!("Hobson connection log directory: {err}");
            return;
        }
    }
    let mut events = fs::read(&path)
        .ok()
        .and_then(|bytes| serde_json::from_slice::<Vec<Value>>(&bytes).ok())
        .unwrap_or_default();
    events.push(entry);
    if events.len() > MAX_EVENTS {
        let drop_n = events.len() - MAX_EVENTS;
        events.drain(0..drop_n);
    }
    if let Err(err) = fs::write(&path, serde_json::to_vec(&events).unwrap_or_default()) {
        log::warn!("Hobson connection log write: {err}");
    }
}

pub(super) fn begin_outgoing(id: &str) {
    let at = get_time();
    opens().lock().unwrap().insert(
        format!("out:{id}"),
        Open {
            at,
            id: id.to_owned(),
            name: String::new(),
        },
    );
    append(json!({
        "t": at,
        "dir": "out",
        "id": id,
        "name": "",
        "ev": "start",
        "secs": 0,
    }));
}

pub(super) fn end_outgoing(id: &str) {
    end(&format!("out:{id}"), "out");
}

pub(super) fn begin_incoming(conn_id: i32, id: &str, name: &str) {
    let at = get_time();
    opens().lock().unwrap().insert(
        format!("in:{conn_id}"),
        Open {
            at,
            id: id.to_owned(),
            name: name.to_owned(),
        },
    );
    append(json!({
        "t": at,
        "dir": "in",
        "id": id,
        "name": name,
        "ev": "start",
        "secs": 0,
    }));
}

pub(super) fn end_incoming(conn_id: i32) {
    end(&format!("in:{conn_id}"), "in");
}

fn end(key: &str, dir: &str) {
    let Some(open) = opens().lock().unwrap().remove(key) else {
        return;
    };
    let now = get_time();
    let secs = Duration::from_millis(now.saturating_sub(open.at) as u64).as_secs();
    append(json!({
        "t": now,
        "dir": dir,
        "id": open.id,
        "name": open.name,
        "ev": "end",
        "secs": secs,
    }));
}

pub(super) fn unlisted(id: &str, name: &str, ip: &str, ev: &str) {
    append(json!({
        "t": get_time(),
        "dir": "unlisted",
        "id": id,
        "name": name,
        "ip": ip,
        "ev": ev,
        "secs": 0,
    }));
}

pub(super) fn denied(id: &str, name: &str, ip: &str) {
    append(json!({
        "t": get_time(),
        "dir": "denied",
        "id": id,
        "name": name,
        "ip": ip,
        "ev": "denied",
        "secs": 0,
    }));
}
