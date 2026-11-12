//! 화면(TS)에서 부르는 명령: 외부 프로그램·홈 폴더 파일·진단 내보내기. 창·트레이는 lib.rs.

use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Duration;

use crate::{data_dir, proc, safe_path};

// ---- 외부 프로그램 ----

#[tauri::command]
pub async fn run_process(program: String, args: Vec<String>, opts: Option<serde_json::Value>) -> proc::ProcResult {
    let opts: proc::RunOptions = opts.and_then(|v| serde_json::from_value(v).ok()).unwrap_or_default();
    tauri::async_runtime::spawn_blocking(move || proc::run(&program, &args, opts))
        .await
        .unwrap_or_else(|e| proc::ProcResult { code: -1, stderr: e.to_string(), ..Default::default() })
}

/// 실행 파일 찾기. 설정에 적은 경로가 있으면 그것부터. (경로, 찾은 곳)
#[tauri::command]
pub fn which_program(name: String, configured: Option<String>) -> Option<(String, String)> {
    if let Some(c) = configured.filter(|c| !c.trim().is_empty()) {
        if Path::new(c.trim()).is_file() {
            return Some((c.trim().to_string(), "설정 경로".into()));
        }
    }
    proc::which(&name)
}

#[tauri::command]
pub fn port_listening(port: u16) -> bool {
    proc::port_listening(port)
}

/// 포트를 듣는 프로세스 (pid, 이미지 이름).
#[tauri::command]
pub async fn port_owner(port: u16) -> Option<(u32, String)> {
    tauri::async_runtime::spawn_blocking(move || proc::port_owner(port)).await.ok().flatten()
}

#[tauri::command]
pub fn kill_pid(pid: u32) {
    proc::kill_pid(pid)
}

#[tauri::command]
pub fn tunnel_spawn(key: String, program: String, args: Vec<String>, log: String) -> Result<u32, String> {
    let p = safe_path(&log)?;
    proc::spawn_tunnel(&key, &program, &args, &p)
}

/// 돌고 있으면 null, 끝났으면 종료 코드.
#[tauri::command]
pub fn tunnel_exit(key: String) -> Option<i32> {
    proc::tunnel_exit(&key)
}

#[tauri::command]
pub fn tunnel_stop(key: String) {
    proc::stop_tunnel(&key)
}

#[tauri::command]
pub async fn tsh_login(
    program: String,
    args: Vec<String>,
    env: HashMap<String, String>,
    password: String,
    otp_secret: String,
    min_counter: Option<u64>,
    timeout_secs: u64,
) -> proc::LoginResult {
    tauri::async_runtime::spawn_blocking(move || {
        proc::pty_login(&program, &args, &env, &password, &otp_secret, min_counter, Duration::from_secs(timeout_secs.max(5)))
    })
    .await
    .unwrap_or_default()
}

/// 지금 OTP 코드와 남은 초.
#[tauri::command]
pub fn totp_now(secret: String) -> Option<(String, u64)> {
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).ok()?.as_secs();
    proc::totp(&secret, now).map(|c| (c, 30 - now % 30))
}

// ---- 파일 (데이터 폴더 밖: 홈의 .claude 등) ----

pub fn home_dir() -> PathBuf {
    std::env::var_os("USERPROFILE").or_else(|| std::env::var_os("HOME")).map(PathBuf::from).unwrap_or_default()
}

/// 홈 아래 상대 경로만 (..·절대 경로 금지).
fn home_path(rel: &str) -> Result<PathBuf, String> {
    let ok = !rel.is_empty() && !rel.contains("..") && !rel.contains(':') && !rel.starts_with(['/', '\\']);
    if !ok {
        return Err(format!("잘못된 경로: {rel}"));
    }
    Ok(home_dir().join(rel))
}

#[tauri::command]
pub fn home_dir_path() -> String {
    home_dir().to_string_lossy().into_owned()
}

#[tauri::command]
pub fn home_read(rel: String) -> Result<Option<String>, String> {
    let p = home_path(&rel)?;
    match fs::read(&p) {
        Ok(b) => Ok(Some(String::from_utf8_lossy(&b).into_owned())),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e.to_string()),
    }
}

/// 쓰기. backup 이면 기존 파일을 <이름>.bak-YYYYMMDD-HHMMSS 로 먼저 복사 (실패하면 쓰지 않음). 백업 경로를 돌려준다.
#[tauri::command]
pub fn home_write(rel: String, content: String, backup: bool) -> Result<Option<String>, String> {
    let p = home_path(&rel)?;
    let mut saved = None;
    if backup && p.is_file() {
        let stamp = chrono::Local::now().format("%Y%m%d-%H%M%S");
        let mut b = PathBuf::from(format!("{}.bak-{stamp}", p.display()));
        let mut n = 1;
        while b.exists() {
            b = PathBuf::from(format!("{}.bak-{stamp}-{n}", p.display()));
            n += 1;
        }
        fs::copy(&p, &b).map_err(|e| format!("백업 실패: {e}"))?;
        saved = Some(b.to_string_lossy().into_owned());
    }
    if let Some(d) = p.parent() {
        fs::create_dir_all(d).map_err(|e| e.to_string())?;
    }
    let tmp = p.with_extension("atm-tmp");
    fs::write(&tmp, content.as_bytes()).map_err(|e| e.to_string())?;
    fs::rename(&tmp, &p).map_err(|e| e.to_string())?;
    Ok(saved)
}

/// 파일을 지우고, 그 폴더가 비면 폴더도 지운다.
#[tauri::command]
pub fn home_remove(rel: String) -> Result<(), String> {
    let p = home_path(&rel)?;
    match fs::remove_file(&p) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
        Err(e) => return Err(e.to_string()),
    }
    if let Some(d) = p.parent() {
        if fs::read_dir(d).map(|mut it| it.next().is_none()).unwrap_or(false) {
            let _ = fs::remove_dir(d);
        }
    }
    Ok(())
}

/// 절대 경로 폴더의 하위 폴더 이름 (클론 찾기용). 없으면 빈 목록.
#[tauri::command]
pub fn list_subdirs(path: String) -> Vec<String> {
    let mut out: Vec<String> = fs::read_dir(path)
        .map(|it| {
            it.filter_map(Result::ok)
                .filter(|e| e.file_type().map(|t| t.is_dir()).unwrap_or(false))
                .map(|e| e.file_name().to_string_lossy().into_owned())
                .collect()
        })
        .unwrap_or_default();
    out.sort();
    out
}

#[tauri::command]
pub fn path_exists(path: String) -> bool {
    Path::new(&path).exists()
}

/// 데이터 폴더 파일의 수정 시각 (ms). 없으면 null.
#[tauri::command]
pub fn file_mtime(name: String) -> Result<Option<f64>, String> {
    let p = safe_path(&name)?;
    Ok(fs::metadata(p)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_millis() as f64))
}

#[tauri::command]
pub fn set_file_mtime(name: String, ms: f64) -> Result<(), String> {
    let p = safe_path(&name)?;
    let f = fs::OpenOptions::new().write(true).open(p).map_err(|e| e.to_string())?;
    f.set_modified(std::time::UNIX_EPOCH + Duration::from_millis(ms.max(0.0) as u64)).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn delete_file(name: String) -> Result<(), String> {
    let p = safe_path(&name)?;
    match fs::remove_file(p) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.to_string()),
    }
}

/// 이 실행 파일의 경로 (훅·스킬에 넣는다).
#[tauri::command]
pub fn exe_path() -> String {
    std::env::current_exe().map(|p| p.to_string_lossy().into_owned()).unwrap_or_default()
}

/// 데이터 폴더 안 파일·폴더를 기본 프로그램으로 연다 (없으면 만든다: 폴더는 폴더로, 파일은 빈 파일로).
#[tauri::command]
pub fn open_data_path(name: String, create_file: bool) -> Result<(), String> {
    let p = if name.is_empty() { data_dir() } else { safe_path(&name)? };
    if !p.exists() {
        if create_file {
            if let Some(d) = p.parent() {
                fs::create_dir_all(d).map_err(|e| e.to_string())?;
            }
            fs::write(&p, "").map_err(|e| e.to_string())?;
        } else {
            fs::create_dir_all(&p).map_err(|e| e.to_string())?;
        }
    }
    tauri_plugin_opener::open_path(p, None::<&str>).map_err(|e| e.to_string())
}

/// 탐색기에서 이 파일을 선택해 보여준다.
#[tauri::command]
pub fn reveal_path(path: String) -> Result<(), String> {
    tauri_plugin_opener::reveal_item_in_dir(path).map_err(|e| e.to_string())
}

/// 진단 정보 zip 을 바탕 화면에 만든다 (Mac DiagnosticsExport). 보고서 + 로그·설정·teleport.json·tags.json.
/// 비밀값(secrets, 노트 본문, 할 일)은 넣지 않는다.
#[tauri::command]
pub async fn export_diagnostics(report: String) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || -> Result<String, String> {
        use zip::write::SimpleFileOptions;
        let desktop = home_dir().join("Desktop");
        let dest_dir = if desktop.is_dir() { desktop } else { home_dir() };
        let stamp = chrono::Local::now().format("%Y%m%d-%H%M%S");
        let dest = dest_dir.join(format!("ATM-진단-{stamp}.zip"));
        let f = fs::File::create(&dest).map_err(|e| e.to_string())?;
        let mut z = zip::ZipWriter::new(f);
        let opt = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated);
        z.start_file("report.txt", opt).map_err(|e| e.to_string())?;
        z.write_all(report.as_bytes()).map_err(|e| e.to_string())?;
        let dir = data_dir();
        let mut files: Vec<(String, PathBuf)> =
            ["settings.json", "teleport.json", "tags.json"].iter().map(|n| (n.to_string(), dir.join(n))).collect();
        if let Ok(it) = fs::read_dir(dir.join("logs")) {
            for e in it.filter_map(Result::ok).filter(|e| e.path().is_file()) {
                files.push((format!("logs/{}", e.file_name().to_string_lossy()), e.path()));
            }
        }
        for (rel, path) in files {
            if let Ok(b) = fs::read(&path) {
                // 너무 큰 로그는 끝 2MB 만
                let b = if b.len() > 2_000_000 { b[b.len() - 2_000_000..].to_vec() } else { b };
                z.start_file(rel, opt).map_err(|e| e.to_string())?;
                z.write_all(&b).map_err(|e| e.to_string())?;
            }
        }
        z.finish().map_err(|e| e.to_string())?;
        Ok(dest.to_string_lossy().into_owned())
    })
    .await
    .map_err(|e| e.to_string())?
}

/// tsh 가 인증서를 쓰다 죽으면 ~/.tsh/keys 에 0바이트 파일이 남아 모든 로그인이 "missing PEM encoded block" 으로 실패한다.
/// 빈 파일만 지우고 지운 상대 경로를 돌려준다 (Mac TshProfileRepair).
#[tauri::command]
pub fn tsh_repair_empty_keys() -> Vec<String> {
    let base = std::env::var_os("TELEPORT_HOME").map(PathBuf::from).unwrap_or_else(|| home_dir().join(".tsh")).join("keys");
    let mut removed = Vec::new();
    let mut stack = vec![base.clone()];
    while let Some(dir) = stack.pop() {
        let Ok(it) = fs::read_dir(&dir) else { continue };
        for e in it.filter_map(Result::ok) {
            let p = e.path();
            match e.metadata() {
                Ok(m) if m.is_dir() => stack.push(p),
                Ok(m) if m.is_file() && m.len() == 0 => {
                    if fs::remove_file(&p).is_ok() {
                        removed.push(p.strip_prefix(&base).unwrap_or(&p).to_string_lossy().into_owned());
                    }
                }
                _ => {}
            }
        }
    }
    removed.sort();
    removed
}
