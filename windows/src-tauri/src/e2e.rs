//! E2E 탭 (Aside) 지원 명령. Mac E2EJobStore·AsideCLI 의 파일 쪽 짝.
//! - 검증 기록: 데이터 폴더 `e2e/jobs/<jobId>/` (job.json·result.json·run.log·스크린샷·jira/)
//! - 실행용 폴더: Aside 계정 폴더 아래 `u/<계정>/atm-e2e/<jobId>/`. guard 권한의 Aside 가 읽고 쓸 수 있는 곳.
//!   요청을 복사해 넣고, 끝나면 result.json 과 이미지(링크·큰 파일 제외)만 가져온 뒤 지운다.
//! 창을 만지는 명령은 없다 (동기 창 명령은 Windows 에서 교착이 걸린다).

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use crate::commands::home_dir;
use crate::{data_dir, proc};

const REQUEST: &str = "request.json";
const RESULT: &str = "result.json";
const JIRA_DIR: &str = "jira";
const IMAGE_EXT: [&str; 5] = ["png", "jpg", "jpeg", "webp", "gif"];
const MAX_RESULT: u64 = 2 * 1024 * 1024;
const MAX_IMAGE: u64 = 20 * 1024 * 1024;

/// Aside 가 계정·캐시를 두는 폴더. Windows 에서는 아직 확인하지 못했다 (Mac 과 같은 `%USERPROFILE%\.aside` 로 가정).
/// 위치가 다르면 여기 한 곳만 고치면 된다.
// unverified on Windows
fn aside_base() -> PathBuf {
    home_dir().join(".aside")
}

fn valid_job_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 64 && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
}

fn job_dir(id: &str) -> Result<PathBuf, String> {
    if !valid_job_id(id) {
        return Err(format!("잘못된 job id: {id}"));
    }
    Ok(data_dir().join("e2e").join("jobs").join(id))
}

fn work_dir(account: u32, id: &str) -> Result<PathBuf, String> {
    if !valid_job_id(id) {
        return Err(format!("잘못된 job id: {id}"));
    }
    Ok(aside_base().join("u").join(account.to_string()).join("atm-e2e").join(id))
}

/// 링크가 아닌 일반 파일이고 max 바이트 이하인가 (링크를 따라가지 않고 본다).
fn is_plain_file(p: &Path, max: u64) -> bool {
    fs::symlink_metadata(p).map(|m| m.file_type().is_file() && m.len() <= max).unwrap_or(false)
}

fn base_name(n: &str) -> &str {
    n.rsplit(['/', '\\']).next().unwrap_or("")
}

/// 점으로 시작하지 않고 확장자가 이미지인 이름.
fn is_image_name(n: &str) -> bool {
    !n.is_empty()
        && !n.starts_with('.')
        && Path::new(n).extension().map(|e| IMAGE_EXT.contains(&e.to_string_lossy().to_lowercase().as_str())).unwrap_or(false)
}

fn mime_of(n: &str) -> &'static str {
    match Path::new(n).extension().map(|e| e.to_string_lossy().to_lowercase()).as_deref() {
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("webp") => "image/webp",
        Some("gif") => "image/gif",
        _ => "image/png",
    }
}

/// 결과 이미지 → job 폴더 안의 일반 파일. 이름만 보고 (경로가 붙어 와도 마지막 이름), 이미지가 아니거나 링크·폴더면 None.
fn screenshot_path(job: &str, name: &str) -> Option<PathBuf> {
    let n = base_name(name);
    if !is_image_name(n) {
        return None;
    }
    let p = job_dir(job).ok()?.join(n);
    is_plain_file(&p, MAX_IMAGE).then_some(p)
}

fn copy_tree(from: &Path, to: &Path) -> std::io::Result<()> {
    fs::create_dir_all(to)?;
    for e in fs::read_dir(from)? {
        let e = e?;
        let ft = e.file_type()?; // 링크는 따라가지 않는다 (is_dir·is_file 둘 다 false)
        let dest = to.join(e.file_name());
        if ft.is_dir() {
            copy_tree(&e.path(), &dest)?;
        } else if ft.is_file() {
            fs::copy(e.path(), dest)?;
        }
    }
    Ok(())
}

fn b64(data: &[u8]) -> String {
    const T: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(data.len().div_ceil(3) * 4);
    for c in data.chunks(3) {
        let n = (c[0] as u32) << 16 | (*c.get(1).unwrap_or(&0) as u32) << 8 | *c.get(2).unwrap_or(&0) as u32;
        out.push(T[(n >> 18) as usize & 63] as char);
        out.push(T[(n >> 12) as usize & 63] as char);
        out.push(if c.len() > 1 { T[(n >> 6) as usize & 63] as char } else { '=' });
        out.push(if c.len() > 2 { T[n as usize & 63] as char } else { '=' });
    }
    out
}

// ---- Aside ----

/// 실행용 폴더 경로 (프롬프트에 들어간다). 만들지는 않는다.
#[tauri::command]
pub fn aside_work_dir(account_id: u32, job_id: String) -> Result<String, String> {
    work_dir(account_id, &job_id).map(|p| p.to_string_lossy().into_owned())
}

/// Aside 폴더 안 텍스트 파일 (모델 목록·업데이트 확인). 상대 경로만, 없으면 None.
#[tauri::command]
pub fn aside_read(rel: String) -> Result<Option<String>, String> {
    let ok = !rel.is_empty() && !rel.contains("..") && !rel.contains(':') && !rel.starts_with(['/', '\\']);
    if !ok {
        return Err(format!("잘못된 경로: {rel}"));
    }
    let p = aside_base().join(rel);
    if !is_plain_file(&p, MAX_RESULT) {
        return Ok(None);
    }
    Ok(fs::read(&p).ok().map(|b| String::from_utf8_lossy(&b).into_owned()))
}

/// Aside 브라우저 실행 파일. Windows 에서는 설치 위치를 아직 확인하지 못해 흔한 곳만 본다.
// unverified on Windows
fn aside_browser_exe() -> Option<PathBuf> {
    #[cfg(windows)]
    {
        let mut c: Vec<PathBuf> = Vec::new();
        if let Some(l) = std::env::var_os("LOCALAPPDATA").map(PathBuf::from) {
            c.push(l.join("Programs").join("Aside").join("Aside.exe"));
            c.push(l.join("Aside").join("Aside.exe"));
        }
        for pf in ["ProgramFiles", "ProgramFiles(x86)"] {
            if let Some(p) = std::env::var_os(pf).map(PathBuf::from) {
                c.push(p.join("Aside").join("Aside.exe"));
            }
        }
        c.into_iter().find(|p| p.is_file())
    }
    #[cfg(not(windows))]
    {
        None
    }
}

#[tauri::command]
pub fn aside_browser() -> Option<String> {
    aside_browser_exe().map(|p| p.to_string_lossy().into_owned())
}

/// 주소를 Aside 브라우저로 연다 (직접 로그인해 Aside Vault 에 저장하는 용도). http(s) 만.
#[tauri::command]
pub fn aside_open_url(url: String) -> Result<(), String> {
    let ok = (url.starts_with("https://") || url.starts_with("http://")) && !url.chars().any(|c| c.is_whitespace() || c == '"');
    if !ok {
        return Err("열 수 없는 주소예요".into());
    }
    let exe = aside_browser_exe().ok_or("Aside 브라우저를 찾지 못했어요")?;
    std::process::Command::new(exe).arg(url).spawn().map(|_| ()).map_err(|e| e.to_string())
}

/// Aside 브라우저를 켠다 (활성화하지 않고 켜는 것은 지원하지 않는다).
#[tauri::command]
pub fn aside_launch() -> Result<(), String> {
    let exe = aside_browser_exe().ok_or("Aside 브라우저를 찾지 못했어요")?;
    std::process::Command::new(exe).spawn().map(|_| ()).map_err(|e| e.to_string())
}

/// PowerShell 창을 열어 `aside update` 또는 `aside login` 을 돌린다. exe 는 aside 실행 파일이어야 한다.
#[tauri::command]
pub fn aside_terminal(exe: String, sub: String) -> Result<(), String> {
    if !["update", "login"].contains(&sub.as_str()) {
        return Err("지원하지 않는 명령이에요".into());
    }
    let p = Path::new(&exe);
    let is_aside = p.is_file() && p.file_stem().map(|s| s.to_string_lossy().eq_ignore_ascii_case("aside")).unwrap_or(false);
    if !is_aside {
        return Err("aside 실행 파일이 아니에요".into());
    }
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NEW_CONSOLE: u32 = 0x0000_0010;
        let script = format!("& '{}' {sub}", exe.replace('\'', "''"));
        std::process::Command::new("powershell")
            .args(["-NoExit", "-Command", script.as_str()])
            .creation_flags(CREATE_NEW_CONSOLE)
            .spawn()
            .map(|_| ())
            .map_err(|e| e.to_string())
    }
    #[cfg(not(windows))]
    {
        Err("Windows 에서만 쓸 수 있어요".into())
    }
}

/// aside 프로세스일 때만 트리째 끝낸다 (pid 재사용으로 남의 프로세스를 죽이지 않게 이미지 이름을 본다).
#[tauri::command]
pub async fn kill_pid_if_aside(pid: u32) -> bool {
    tauri::async_runtime::spawn_blocking(move || proc::kill_pid_if_image(pid, "aside")).await.unwrap_or(false)
}

// ---- 실행용 폴더 ----

/// 요청(request.json)과 Jira 내용(jira/)을 실행용 폴더에 둔다. 남아 있던 폴더는 비우고 다시 만든다.
#[tauri::command]
pub fn e2e_work_prepare(account_id: u32, job_id: String, request: String) -> Result<(), String> {
    let work = work_dir(account_id, &job_id)?;
    let _ = fs::remove_dir_all(&work);
    fs::create_dir_all(&work).map_err(|e| e.to_string())?;
    fs::write(work.join(REQUEST), request.as_bytes()).map_err(|e| e.to_string())?;
    let jira = job_dir(&job_id)?.join(JIRA_DIR);
    if fs::symlink_metadata(&jira).map(|m| m.is_dir()).unwrap_or(false) {
        copy_tree(&jira, &work.join(JIRA_DIR)).map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// 실행용 폴더에서 result.json 과 스크린샷 이미지만 job 폴더로 가져오고 실행용 폴더를 지운다.
/// 링크·폴더·이미지가 아닌 파일·너무 큰 파일은 가져오지 않고 그 이름을 돌려준다.
#[tauri::command]
pub fn e2e_work_import(account_id: u32, job_id: String) -> Result<Vec<String>, String> {
    let work = work_dir(account_id, &job_id)?;
    let dst = job_dir(&job_id)?;
    fs::create_dir_all(&dst).map_err(|e| e.to_string())?;
    let mut names: Vec<String> = fs::read_dir(&work)
        .map(|it| it.filter_map(Result::ok).map(|e| e.file_name().to_string_lossy().into_owned()).collect())
        .unwrap_or_default();
    names.sort();
    let mut skipped = Vec::new();
    for name in names {
        if name == REQUEST || name == JIRA_DIR {
            continue;
        }
        let is_result = name == RESULT;
        let src = work.join(&name);
        let ok = (is_result || is_image_name(&name)) && is_plain_file(&src, if is_result { MAX_RESULT } else { MAX_IMAGE });
        if !ok || fs::copy(&src, dst.join(&name)).is_err() {
            skipped.push(name);
        }
    }
    let _ = fs::remove_dir_all(&work);
    Ok(skipped)
}

/// ATM 이 실행 중에 죽어 남은 실행용 폴더를 지운다. id 앞 14자(YYYYMMDDHHmmss, 로컬 시각)가 before 보다 이른 것만.
#[tauri::command]
pub fn e2e_work_prune(before: String) -> Vec<String> {
    let mut removed = Vec::new();
    let Ok(accounts) = fs::read_dir(aside_base().join("u")) else { return removed };
    for a in accounts.filter_map(Result::ok) {
        let root = a.path().join("atm-e2e");
        let Ok(it) = fs::read_dir(&root) else { continue };
        for e in it.filter_map(Result::ok) {
            let id = e.file_name().to_string_lossy().into_owned();
            if valid_job_id(&id) && id.len() >= 14 && id[..14] < *before && fs::remove_dir_all(e.path()).is_ok() {
                removed.push(id);
            }
        }
    }
    removed.sort();
    removed
}

// ---- job 폴더 ----

/// run.log 에 한 줄 덧붙인다 (실행 중에는 aside 가 같은 파일에 쓰므로 다시 쓰지 않고 덧붙이기만 한다).
#[tauri::command]
pub fn e2e_log_append(job_id: String, text: String) -> Result<(), String> {
    let dir = job_dir(&job_id)?;
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let mut f = fs::OpenOptions::new().create(true).append(true).open(dir.join("run.log")).map_err(|e| e.to_string())?;
    writeln!(f, "{}", text.trim_end_matches('\n')).map_err(|e| e.to_string())
}

/// run.log 의 처음과 끝 (세션 id 는 앞쪽에, 실패 원인은 뒤쪽에 있다). 없으면 빈 문자열.
#[tauri::command]
pub fn e2e_log_text(job_id: String) -> String {
    const PART: usize = 16 * 1024;
    let Ok(dir) = job_dir(&job_id) else { return String::new() };
    let Ok(b) = fs::read(dir.join("run.log")) else { return String::new() };
    if b.len() <= 2 * PART {
        return String::from_utf8_lossy(&b).into_owned();
    }
    format!("{}\n…\n{}", String::from_utf8_lossy(&b[..PART]), String::from_utf8_lossy(&b[b.len() - PART..]))
}

/// 이 이름들 중 job 폴더에 실제로 있는 이미지 (이름만 본다).
#[tauri::command]
pub fn e2e_screenshots(job_id: String, names: Vec<String>) -> Vec<String> {
    names.into_iter().filter(|n| screenshot_path(&job_id, n).is_some()).collect()
}

/// 스크린샷 (mime, base64). 이미지 확장자의 일반 파일이 아니면 None.
#[tauri::command]
pub fn e2e_screenshot_data(job_id: String, name: String) -> Option<(String, String)> {
    let p = screenshot_path(&job_id, &name)?;
    let data = fs::read(&p).ok()?;
    Some((mime_of(base_name(&name)).into(), b64(&data)))
}

/// 스크린샷을 기본 이미지 뷰어로 연다. 이미지 확장자의 일반 파일만.
#[tauri::command]
pub fn e2e_screenshot_open(job_id: String, name: String) -> Result<(), String> {
    let p = screenshot_path(&job_id, &name).ok_or("열 수 없는 파일이에요")?;
    tauri_plugin_opener::open_path(p, None::<&str>).map_err(|e| e.to_string())
}

/// job 폴더 아래 `jira/...` 파일 하나를 쓴다 (ATM 이 Jira API 로 받은 이슈 내용·첨부 이미지). 본문은 파일 바이트 그대로,
/// 헤더 x-job-id·x-rel 로 위치를 준다. 상대 경로는 jira/ 아래 일반 이름만 (.. · 절대 경로 · 드라이브 문자 금지).
#[tauri::command]
pub fn e2e_job_write(request: tauri::ipc::Request<'_>) -> Result<(), String> {
    let tauri::ipc::InvokeBody::Raw(bytes) = request.body() else { return Err("본문이 없어요".into()) };
    let header = |k: &str| request.headers().get(k).and_then(|v| v.to_str().ok()).unwrap_or("").to_string();
    let (job, rel) = (header("x-job-id"), header("x-rel"));
    let segs: Vec<&str> = rel.split('/').collect();
    let ok = segs.first() == Some(&JIRA_DIR) && segs.len() >= 2 && segs.iter().all(|s| !s.is_empty() && *s != ".." && *s != "." && !s.contains(['\\', ':']));
    if !ok {
        return Err(format!("잘못된 경로: {rel}"));
    }
    let dest = segs.iter().fold(job_dir(&job)?, |p, s| p.join(s));
    if let Some(d) = dest.parent() {
        fs::create_dir_all(d).map_err(|e| e.to_string())?;
    }
    fs::write(&dest, bytes).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn e2e_job_delete(job_id: String) -> Result<(), String> {
    match fs::remove_dir_all(job_dir(&job_id)?) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(e) => Err(e.to_string()),
    }
}

/// 결과 보고서(HTML)를 바탕 화면에 쓴다. 파일 이름은 영문·숫자·-·_·. 만 남기고 .html 로 끝나야 한다. 경로를 돌려준다.
#[tauri::command]
pub fn e2e_export_html(file_name: String, content: String) -> Result<String, String> {
    let name: String = base_name(&file_name).chars().filter(|c| c.is_ascii_alphanumeric() || "-_.+".contains(*c)).collect();
    if !name.ends_with(".html") || name.starts_with('.') {
        return Err("잘못된 파일 이름이에요".into());
    }
    let desktop = home_dir().join("Desktop");
    let dir = if desktop.is_dir() { desktop } else { home_dir() };
    let dest = dir.join(name);
    fs::write(&dest, content.as_bytes()).map_err(|e| e.to_string())?;
    Ok(dest.to_string_lossy().into_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_matches_rfc4648() {
        assert_eq!(b64(b""), "");
        assert_eq!(b64(b"f"), "Zg==");
        assert_eq!(b64(b"fo"), "Zm8=");
        assert_eq!(b64(b"foo"), "Zm9v");
        assert_eq!(b64(b"foobar"), "Zm9vYmFy");
    }

    #[test]
    fn names_and_ids_are_validated() {
        assert!(valid_job_id("20261120103000-ab12"));
        assert!(!valid_job_id("../x") && !valid_job_id("") && !valid_job_id("a b"));
        assert!(is_image_name("ABC-1-1.PNG") && !is_image_name(".hidden.png") && !is_image_name("run.log"));
        assert_eq!(base_name("..\\evil/shot.png"), "shot.png");
        assert!(screenshot_path("../x", "a.png").is_none());
    }
}
