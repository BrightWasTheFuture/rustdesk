//! Dummy X session for a Hobson Linux host with no physical display.
//!
//! Started only when `allow-linux-headless` is `Y` and logind has no seat0
//! user. Requires `Xorg` and, for a usable desktop, `xserver-xorg-video-dummy`
//! plus `xfce4`.

use std::{
    path::Path,
    process::Command,
    sync::atomic::{AtomicBool, Ordering},
    thread,
    time::Duration,
};

use hbb_common::{config::Config, log};

const DISPLAY: &str = ":99";
const SOCKET: &str = "/tmp/.X11-unix/X99";
const CONF: &str = "/var/lib/hobson/dummy.conf";

const DUMMY_CONF: &str = r#"
Section "Device"
    Identifier "Hobson Dummy"
    Driver "dummy"
    VideoRam 256000
EndSection

Section "Monitor"
    Identifier "Hobson Monitor"
    HorizSync 5.0 - 1000.0
    VertRefresh 5.0 - 200.0
    Modeline "1920x1080" 172.80 1920 2040 2248 2576 1080 1081 1084 1118 -hsync +vsync
EndSection

Section "Screen"
    Identifier "Hobson Screen"
    Device "Hobson Dummy"
    Monitor "Hobson Monitor"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "1920x1080"
    EndSubSection
EndSection
"#;

pub fn prepare() -> bool {
    if Config::get_option("allow-linux-headless") != "Y" {
        return false;
    }
    if Path::new(SOCKET).exists() {
        std::env::set_var("DISPLAY", DISPLAY);
        let auth = "/root/.Xauthority";
        if Path::new(auth).exists() {
            std::env::set_var("XAUTHORITY", auth);
        }
        return true;
    }
    spawn_once();
    false
}

fn spawn_once() {
    static STARTED: AtomicBool = AtomicBool::new(false);
    if STARTED.swap(true, Ordering::SeqCst) {
        return;
    }
    thread::spawn(|| {
        if !command_exists("Xorg") {
            log::warn!(
                "allow-linux-headless is on, but Xorg is not installed. \
                 Install xserver-xorg-video-dummy and xfce4."
            );
            return;
        }
        if let Some(dir) = Path::new(CONF).parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        if std::fs::write(CONF, DUMMY_CONF.trim_start()).is_err() {
            log::warn!("could not write {CONF}");
            return;
        }
        match Command::new("Xorg")
            .args([
                DISPLAY,
                "-nolisten",
                "tcp",
                "-noreset",
                "-config",
                CONF,
                "-logfile",
                "/var/log/hobson-xorg.log",
            ])
            .spawn()
        {
            Ok(_) => log::info!("starting dummy X on {DISPLAY}"),
            Err(err) => {
                log::warn!("failed to start Xorg: {err}");
                return;
            }
        }
        for _ in 0..20 {
            if Path::new(SOCKET).exists() {
                break;
            }
            thread::sleep(Duration::from_millis(250));
        }
        if !Path::new(SOCKET).exists() {
            log::warn!("dummy X socket {SOCKET} did not appear");
            return;
        }
        if command_exists("startxfce4") {
            let _ = Command::new("startxfce4").env("DISPLAY", DISPLAY).spawn();
        } else if command_exists("xfce4-session") {
            let _ = Command::new("xfce4-session")
                .env("DISPLAY", DISPLAY)
                .spawn();
        } else {
            log::warn!("xfce4 is not installed; the dummy display has no desktop");
        }
    });
}

fn command_exists(name: &str) -> bool {
    Command::new("sh")
        .args(["-c", &format!("command -v {name}")])
        .output()
        .map(|out| out.status.success())
        .unwrap_or(false)
}
