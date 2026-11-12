mod cli;
mod commands;
mod proc;

pub use cli::handle as handle_cli;


use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::time::Duration;

use tauri::menu::{Menu, MenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{AppHandle, Emitter, Manager, WebviewUrl, WebviewWindowBuilder, WindowEvent};

/// 데이터 폴더. Windows: %APPDATA%\TaskWidget (Mac 판과 같은 이름).
/// 개발 빌드(`tauri dev`)는 설치한 앱의 데이터를 건드리지 않게 %APPDATA%\TaskWidget-dev 를 쓴다.
/// 개발용 Mac 빌드는 Mac 판 데이터를 건드리지 않게 TaskWidget-win-dev 를 쓴다. ATM_DATA_DIR 이 있으면 그 폴더.
pub(crate) fn data_dir() -> PathBuf {
    if let Ok(p) = std::env::var("ATM_DATA_DIR") {
        if !p.is_empty() {
            return PathBuf::from(p);
        }
    }
    #[cfg(windows)]
    {
        let base = std::env::var("APPDATA").unwrap_or_else(|_| ".".into());
        PathBuf::from(base).join(if cfg!(debug_assertions) { "TaskWidget-dev" } else { "TaskWidget" })
    }
    #[cfg(not(windows))]
    {
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
        PathBuf::from(home).join("Library/Application Support/TaskWidget-win-dev")
    }
}

/// 데이터 폴더 밖으로 나가는 이름(.., 절대 경로, 구분자)을 막는다.
pub(crate) fn safe_path(name: &str) -> Result<PathBuf, String> {
    let ok = !name.is_empty()
        && !name.contains("..")
        && !name.starts_with('/')
        && !name.starts_with('\\')
        && !name.contains(':')
        && name.split(['/', '\\']).all(|p| !p.is_empty());
    if !ok {
        return Err(format!("잘못된 파일 이름: {name}"));
    }
    Ok(data_dir().join(name))
}

#[tauri::command]
fn data_dir_path() -> String {
    data_dir().to_string_lossy().into_owned()
}

/// 파일이 없으면 None.
#[tauri::command]
fn read_text(name: String) -> Result<Option<String>, String> {
    let p = safe_path(&name)?;
    match fs::read_to_string(&p) {
        Ok(s) => Ok(Some(s)),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

/// 임시 파일에 쓴 뒤 바꿔치기 (중간에 꺼져도 반쯤 쓴 파일이 남지 않게).
#[tauri::command]
fn write_text(name: String, content: String) -> Result<(), String> {
    let p = safe_path(&name)?;
    if let Some(dir) = p.parent() {
        fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let tmp = p.with_extension("tmp");
    {
        let mut f = fs::File::create(&tmp).map_err(|e| e.to_string())?;
        f.write_all(content.as_bytes()).map_err(|e| e.to_string())?;
        f.sync_all().map_err(|e| e.to_string())?;
    }
    fs::rename(&tmp, &p).map_err(|e| e.to_string())
}

/// 깨진 파일을 옆으로 치운다 (todos.json → todos.corrupt-<ts>.json).
#[tauri::command]
fn move_aside(name: String, to: String) -> Result<(), String> {
    let from = safe_path(&name)?;
    let dest = safe_path(&to)?;
    fs::rename(from, dest).map_err(|e| e.to_string())
}

/// 폴더 안 파일 이름 목록 (하위 폴더 제외). 폴더가 없으면 만든다.
/// inbox 는 처리한 파일을 옮길 done/·bad/ 도 같이 만든다.
#[tauri::command]
fn list_dir(name: String) -> Result<Vec<String>, String> {
    let dir = safe_path(&name)?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    if name == "inbox" {
        let _ = fs::create_dir_all(dir.join("done"));
        let _ = fs::create_dir_all(dir.join("bad"));
    }
    let mut out = Vec::new();
    for e in fs::read_dir(&dir).map_err(|e| e.to_string())? {
        let e = e.map_err(|e| e.to_string())?;
        if e.file_type().map(|t| t.is_file()).unwrap_or(false) {
            out.push(e.file_name().to_string_lossy().into_owned());
        }
    }
    out.sort();
    Ok(out)
}

/// logs/app.log 에 한 줄. 비밀값은 넘기지 않는다.
#[tauri::command]
fn log_line(line: String) -> Result<(), String> {
    let p = data_dir().join("logs");
    fs::create_dir_all(&p).map_err(|e| e.to_string())?;
    let mut f = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(p.join("app.log"))
        .map_err(|e| e.to_string())?;
    writeln!(f, "{}", line.replace('\n', " ")).map_err(|e| e.to_string())
}

// 비밀값: Windows 자격 증명 관리자 (Mac 개발 빌드는 키체인).
#[tauri::command]
fn secret_get(service: String, account: String) -> Result<Option<String>, String> {
    let e = keyring::Entry::new(&service, &account).map_err(|e| e.to_string())?;
    match e.get_password() {
        Ok(v) => Ok(Some(v)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(err) => Err(err.to_string()),
    }
}

#[tauri::command]
fn secret_set(service: String, account: String, value: String) -> Result<(), String> {
    let e = keyring::Entry::new(&service, &account).map_err(|e| e.to_string())?;
    e.set_password(&value).map_err(|e| e.to_string())
}

#[tauri::command]
fn secret_delete(service: String, account: String) -> Result<(), String> {
    let e = keyring::Entry::new(&service, &account).map_err(|e| e.to_string())?;
    match e.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(err) => Err(err.to_string()),
    }
}

/// Windows Hello 를 쓸 수 있는가 (지문·얼굴·PIN 중 하나라도 설정돼 있어야 true).
#[tauri::command]
async fn hello_available() -> bool {
    #[cfg(windows)]
    {
        use windows::Security::Credentials::UI::{UserConsentVerifier, UserConsentVerifierAvailability};
        tauri::async_runtime::spawn_blocking(|| {
            UserConsentVerifier::CheckAvailabilityAsync()
                .and_then(|op| op.get())
                .map(|a| a == UserConsentVerifierAvailability::Available)
                .unwrap_or(false)
        })
        .await
        .unwrap_or(false)
    }
    #[cfg(not(windows))]
    {
        false
    }
}

/// Windows Hello 확인 창을 띄운다. 통과하면 true.
#[tauri::command]
async fn hello_verify(reason: String) -> bool {
    #[cfg(windows)]
    {
        use windows::core::HSTRING;
        use windows::Security::Credentials::UI::{UserConsentVerificationResult, UserConsentVerifier};
        tauri::async_runtime::spawn_blocking(move || {
            UserConsentVerifier::RequestVerificationAsync(&HSTRING::from(reason))
                .and_then(|op| op.get())
                .map(|r| r == UserConsentVerificationResult::Verified)
                .unwrap_or(false)
        })
        .await
        .unwrap_or(false)
    }
    #[cfg(not(windows))]
    {
        let _ = reason;
        false
    }
}


// ---- 창 ----

fn toggle_main(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let shown = w.is_visible().unwrap_or(false) && !w.is_minimized().unwrap_or(false);
        if shown && w.is_focused().unwrap_or(false) {
            let _ = app.emit("panel-hidden", ());
            let _ = w.hide();
        } else {
            show_main(app);
        }
    }
}

/// 패널을 보이고 앞으로. 최소화돼 있으면 되살린다 (트레이·단축키·두 번째 실행 모두 여기로).
fn show_main(app: &AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.show();
        let _ = w.unminimize();
        let _ = w.set_skip_taskbar(true);
        let _ = w.set_focus();
    }
}

/// 노란 버튼: 작업 표시줄로 최소화 (Mac 의 Dock 최소화). 평소엔 작업 표시줄에 없으니 최소화하는 동안만 보인다.
#[tauri::command]
fn minimize_panel(app: AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.set_skip_taskbar(false);
        let _ = w.minimize();
    }
}

#[tauri::command]
fn set_tray_tooltip(app: AppHandle, text: String) {
    if let Some(t) = app.tray_by_id("tray") {
        let _ = t.set_tooltip(Some(text));
    }
}

#[tauri::command]
fn quit_app(app: AppHandle) {
    proc::stop_all_tunnels();
    app.exit(0);
}

/// 설정 창 보이기 (화면이 다 그려진 뒤 settings-main 이 부른다. 흰 화면 번쩍임 방지).
#[tauri::command]
fn settings_ready(app: AppHandle) {
    if let Some(w) = app.get_webview_window("settings") {
        let _ = w.show();
        let _ = w.set_focus();
    }
}

/// 설정 창. 이미 있으면 앞으로.
/// 창을 만드는 명령은 반드시 async 여야 한다. 동기 명령에서 만들면 Windows 에서 교착이 걸려
/// 새 창이 빈 화면으로 멈추고 숨기기·닫기·종료까지 전부 막힌다 (Tauri 문서의 경고).
#[tauri::command]
async fn open_settings(app: AppHandle, pane: Option<String>) -> Result<(), String> {
    // 화면 id 는 영문 소문자만 (스크립트에 넣으므로)
    let pane = pane.filter(|p| !p.is_empty() && p.chars().all(|c| c.is_ascii_lowercase()));
    if let Some(w) = app.get_webview_window("settings") {
        let _ = w.show();
        let _ = w.unminimize();
        let _ = w.set_focus();
        if let Some(p) = pane {
            let _ = w.emit("settings-pane", p);
        }
        return Ok(());
    }
    // 처음 열 화면은 URL 해시 대신 초기화 스크립트로 넘긴다 (Windows 의 앱 경로에서 #이 파일 이름으로 인코딩될 수 있음).
    let init = format!("window.__ATM_PANE = {};", pane.map(|p| format!("\"{p}\"")).unwrap_or("null".into()));
    let w = WebviewWindowBuilder::new(&app, "settings", WebviewUrl::App("settings.html".into()))
        .title("ATM 설정")
        .inner_size(800.0, 660.0)
        .min_inner_size(680.0, 480.0)
        // 패널이 항상 위라서 설정 창도 위로 띄워야 가려지지 않는다
        .always_on_top(true)
        // 그려지기 전 흰 화면이 보이지 않게 숨긴 채 만들고, 화면이 준비되면(settings_ready) 보인다
        .visible(false)
        .initialization_script(&init)
        .build()
        .map_err(|e| e.to_string())?;
    // 패널이 있는 모니터 가운데 (그냥 두면 Windows 가 주 모니터 구석에 띄운다)
    if let (Some(main), Ok(size)) = (app.get_webview_window("main"), w.outer_size()) {
        if let Ok(Some(m)) = main.current_monitor().or_else(|_| w.current_monitor()) {
            let (mp, ms) = (m.position(), m.size());
            let x = mp.x + (ms.width as i32 - size.width as i32) / 2;
            let y = mp.y + (ms.height as i32 - size.height as i32) / 2;
            let _ = w.set_position(tauri::PhysicalPosition::new(x.max(mp.x), y.max(mp.y)));
        }
    }
    // 화면이 4초 안에 신호를 못 보내도 창은 보이게
    let w2 = w.clone();
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(4));
        if !w2.is_visible().unwrap_or(true) {
            let _ = w2.show();
            let _ = w2.set_focus();
        }
    });
    Ok(())
}

#[tauri::command]
fn toggle_panel(app: AppHandle) {
    toggle_main(&app);
}

pub fn run() {
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| {
            // 두 번째 실행은 이미 떠 있는 패널을 보여준다 (최소화돼 있어도).
            show_main(app);
        }))
        .plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, None))
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_http::init())
        .plugin(tauri_plugin_notification::init())
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            data_dir_path,
            read_text,
            write_text,
            move_aside,
            list_dir,
            log_line,
            secret_get,
            secret_set,
            secret_delete,
            hello_available,
            hello_verify,
            open_settings,
            settings_ready,
            toggle_panel,
            minimize_panel,
            set_tray_tooltip,
            quit_app,
            commands::run_process,
            commands::which_program,
            commands::port_listening,
            commands::port_owner,
            commands::kill_pid,
            commands::tunnel_spawn,
            commands::tunnel_exit,
            commands::tunnel_stop,
            commands::tsh_login,
            commands::totp_now,
            commands::home_dir_path,
            commands::home_read,
            commands::home_write,
            commands::home_remove,
            commands::list_subdirs,
            commands::path_exists,
            commands::file_mtime,
            commands::set_file_mtime,
            commands::delete_file,
            commands::exe_path,
            commands::open_data_path,
            commands::reveal_path,
            commands::export_diagnostics,
            commands::tsh_repair_empty_keys
        ])
        .setup(|app| {
            let _ = fs::create_dir_all(data_dir().join("logs"));
            // 패널은 트레이 앱이라 작업 표시줄에 띄우지 않는다 (설정 창은 일반 창이라 보인다)
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.set_skip_taskbar(true);
            }
            let open = MenuItem::with_id(app, "open", "ATM 열기", true, None::<&str>)?;
            let settings = MenuItem::with_id(app, "settings", "설정…", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "종료", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&open, &settings, &quit])?;
            TrayIconBuilder::with_id("tray")
                .icon(app.default_window_icon().cloned().expect("icon"))
                .tooltip("ATM")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, e| match e.id.as_ref() {
                    "open" => show_main(app),
                    "settings" => {
                        let app = app.clone();
                        tauri::async_runtime::spawn(async move {
                            let _ = open_settings(app, None).await;
                        });
                    }
                    "quit" => {
                        proc::stop_all_tunnels();
                        app.exit(0)
                    }
                    _ => {}
                })
                .on_tray_icon_event(|tray, e| {
                    if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = e {
                        toggle_main(tray.app_handle());
                    }
                })
                .build(app)?;
            Ok(())
        })
        .on_window_event(|w, e| match e {
            // 패널의 ✕ 는 끄지 않고 숨긴다 (트레이에서 다시 연다). 설정 창은 그냥 닫는다.
            WindowEvent::CloseRequested { api, .. } if w.label() == "main" => {
                api.prevent_close();
                let _ = w.emit("panel-hidden", ());
                let _ = w.hide();
            }
            // 최소화에서 돌아오면 다시 작업 표시줄에서 뺀다
            WindowEvent::Focused(true) if w.label() == "main" => {
                let _ = w.set_skip_taskbar(true);
            }
            _ => {}
        })
        .build(tauri::generate_context!())
        .expect("ATM 실행 실패");
    app.run(|_app, e| {
        if let tauri::RunEvent::Exit = e {
            // ATM 이 연 터널은 ATM 과 같이 닫는다
            proc::stop_all_tunnels();
        }
    });
}
