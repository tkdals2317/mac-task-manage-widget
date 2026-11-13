//! 외부 프로그램 실행 (claude·gh·git·tsh). Mac ProcessRunner·TeleportTsh·TeleportLogin 의 Windows 짝.
//! 콘솔 창이 번쩍이지 않게 CREATE_NO_WINDOW 로 띄운다.

use std::collections::HashMap;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use serde::{Deserialize, Serialize};

#[cfg(windows)]
use std::os::windows::process::CommandExt;
#[cfg(windows)]
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

fn hide(cmd: &mut Command) -> &mut Command {
    #[cfg(windows)]
    cmd.creation_flags(CREATE_NO_WINDOW);
    cmd
}

#[derive(Serialize, Default, Debug)]
#[serde(rename_all = "camelCase")]
pub struct ProcResult {
    pub code: i32,
    pub stdout: String,
    pub stderr: String,
    pub timed_out: bool,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct RunOptions {
    pub stdin: Option<String>,
    pub cwd: Option<String>,
    #[serde(default)]
    pub env: HashMap<String, String>,
    #[serde(default)]
    pub env_remove: Vec<String>,
    pub timeout_ms: Option<u64>,
}

/// 실행해서 끝날 때까지 기다린다. 시간 초과면 프로세스 트리를 죽이고 timedOut.
pub fn run(program: &str, args: &[String], opts: RunOptions) -> ProcResult {
    let mut cmd = Command::new(program);
    cmd.args(args).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::piped());
    hide(&mut cmd);
    if let Some(cwd) = opts.cwd.as_deref().filter(|c| !c.is_empty()) {
        cmd.current_dir(cwd);
    }
    for k in &opts.env_remove {
        cmd.env_remove(k);
    }
    cmd.envs(&opts.env);
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => return ProcResult { code: -1, stderr: format!("{program} 실행 실패: {e}"), ..Default::default() },
    };
    // 읽기를 먼저 걸어야 큰 stdin 쓰기와 자식 출력이 서로 막히지 않는다
    let mut out = child.stdout.take();
    let mut err = child.stderr.take();
    let t_out = std::thread::spawn(move || {
        let mut b = Vec::new();
        if let Some(o) = out.as_mut() {
            let _ = o.read_to_end(&mut b);
        }
        b
    });
    let t_err = std::thread::spawn(move || {
        let mut b = Vec::new();
        if let Some(e) = err.as_mut() {
            let _ = e.read_to_end(&mut b);
        }
        b
    });
    if let Some(mut si) = child.stdin.take() {
        let input = opts.stdin.unwrap_or_default();
        std::thread::spawn(move || {
            let _ = si.write_all(input.as_bytes());
        });
    }
    let deadline = Instant::now() + Duration::from_millis(opts.timeout_ms.unwrap_or(60_000));
    let mut timed_out = false;
    let code = loop {
        match child.try_wait() {
            Ok(Some(s)) => break s.code().unwrap_or(-1),
            Ok(None) if Instant::now() >= deadline => {
                timed_out = true;
                kill_tree(&mut child);
                break -1;
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(30)),
            Err(_) => break -1,
        }
    };
    let stdout = String::from_utf8_lossy(&t_out.join().unwrap_or_default()).into_owned();
    let stderr = String::from_utf8_lossy(&t_err.join().unwrap_or_default()).into_owned();
    ProcResult { code, stdout, stderr, timed_out }
}

/// npm 의 .cmd 셈 같은 래퍼는 node 자식을 띄우므로 트리째 끝낸다.
fn kill_tree(child: &mut Child) {
    #[cfg(windows)]
    {
        let _ = hide(&mut Command::new("taskkill"))
            .args(["/PID", &child.id().to_string(), "/T", "/F"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
    let _ = child.kill();
    let _ = child.wait();
}

// ---- 위치 찾기 ----

fn is_file(p: &Path) -> bool {
    p.is_file()
}

fn home() -> PathBuf {
    std::env::var_os("USERPROFILE").or_else(|| std::env::var_os("HOME")).map(PathBuf::from).unwrap_or_default()
}

fn env_path(name: &str) -> Option<PathBuf> {
    std::env::var_os(name).map(PathBuf::from)
}

/// 이름 → 실행 파일. PATH(+PATHEXT) → 흔히 설치되는 곳 순. 못 찾으면 None.
/// GUI 앱은 시작 뒤에 바뀐 PATH 를 모르니 기본 위치도 본다.
pub fn which(name: &str) -> Option<(String, String)> {
    let exts: Vec<String> = if cfg!(windows) {
        std::env::var("PATHEXT")
            .unwrap_or_else(|_| ".EXE;.CMD;.BAT".into())
            .split(';')
            .filter(|s| !s.is_empty())
            .map(|s| s.to_lowercase())
            .collect()
    } else {
        vec![String::new()]
    };
    let candidates = |dir: &Path| -> Option<PathBuf> {
        if Path::new(name).extension().is_some() {
            let p = dir.join(name);
            return is_file(&p).then_some(p);
        }
        // 확장자 없는 이름(npm 의 sh 셈)은 Windows 에서 실행할 수 없으니 확장자 붙은 것만
        exts.iter().map(|e| dir.join(format!("{name}{e}"))).find(|p| is_file(p))
    };
    if let Some(path) = std::env::var_os("PATH") {
        for dir in std::env::split_paths(&path) {
            if let Some(p) = candidates(&dir) {
                return Some((p.to_string_lossy().into_owned(), "PATH".into()));
            }
        }
    }
    let h = home();
    let mut known: Vec<PathBuf> = vec![h.join(".local").join("bin"), h.join(".claude").join("local"), h.join(".bun").join("bin")];
    if let Some(a) = env_path("APPDATA") {
        known.push(a.join("npm"));
    }
    if let Some(l) = env_path("LOCALAPPDATA") {
        known.push(l.join("Programs").join("Teleport"));
        known.push(l.join("Programs").join("claude"));
        known.push(l.join("Microsoft").join("WinGet").join("Links"));
        known.push(l.join("Volta").join("bin"));
    }
    for pf in ["ProgramFiles", "ProgramW6432", "ProgramFiles(x86)"] {
        if let Some(p) = env_path(pf) {
            known.push(p.join("GitHub CLI"));
            known.push(p.join("Git").join("cmd"));
            known.push(p.join("Teleport"));
            known.push(p.join("nodejs"));
        }
    }
    for dir in known {
        if let Some(p) = candidates(&dir) {
            return Some((p.to_string_lossy().into_owned(), "기본 위치".into()));
        }
    }
    if name == "claude" {
        return desktop_claude().map(|p| (p.to_string_lossy().into_owned(), "Claude 데스크톱 앱".into()));
    }
    None
}

/// 폴더의 하위 폴더를 버전 숫자 비교로 내림차순 (2.1.321 > 2.1.99).
fn subdirs_desc(dir: &Path) -> Vec<PathBuf> {
    let mut v: Vec<PathBuf> = std::fs::read_dir(dir)
        .map(|it| it.filter_map(Result::ok).map(|e| e.path()).filter(|p| p.is_dir()).collect())
        .unwrap_or_default();
    let key = |p: &PathBuf| -> Vec<u64> {
        p.file_name().map(|n| n.to_string_lossy().split(['.', '-']).map(|x| x.parse().unwrap_or(0)).collect()).unwrap_or_default()
    };
    v.sort_by(|a, b| key(b).cmp(&key(a)));
    v
}

/// Claude 데스크톱 앱이 받아 둔 Claude Code (%LOCALAPPDATA%\Claude-Data\<계정>\claude-code\<버전>\<id>\claude.exe 등).
fn desktop_claude() -> Option<PathBuf> {
    let mut roots = Vec::new();
    if let Some(l) = env_path("LOCALAPPDATA") {
        roots.extend(subdirs_desc(&l.join("Claude-Data")).into_iter().map(|d| d.join("claude-code")));
        roots.push(l.join("Claude").join("claude-code"));
        roots.push(l.join("AnthropicClaude").join("claude-code"));
    }
    if let Some(a) = env_path("APPDATA") {
        roots.push(a.join("Claude").join("claude-code"));
    }
    // 가장 새 버전부터, 그 안에서는 가장 최근에 바뀐 것
    let mut best: Option<(Vec<u64>, std::time::SystemTime, PathBuf)> = None;
    for root in roots.iter().filter(|r| r.is_dir()) {
        for ver in subdirs_desc(root) {
            let vkey: Vec<u64> = ver.file_name().map(|n| n.to_string_lossy().split('.').map(|x| x.parse().unwrap_or(0)).collect()).unwrap_or_default();
            let mut cands = vec![ver.join("claude.exe")];
            cands.extend(subdirs_desc(&ver).into_iter().map(|d| d.join("claude.exe")));
            for c in cands.into_iter().filter(|c| c.is_file()) {
                let t = c.metadata().and_then(|m| m.modified()).unwrap_or(std::time::UNIX_EPOCH);
                if best.as_ref().map_or(true, |(bv, bt, _)| (&vkey, t) > (bv, *bt)) {
                    best = Some((vkey.clone(), t, c));
                }
            }
        }
    }
    best.map(|b| b.2)
}

// ---- 포트·터널 ----

pub fn port_listening(port: u16) -> bool {
    std::net::TcpStream::connect_timeout(&([127, 0, 0, 1], port).into(), Duration::from_millis(300)).is_ok()
}

struct Tunnel {
    child: Child,
}

fn tunnels() -> &'static Mutex<HashMap<String, Tunnel>> {
    static T: OnceLock<Mutex<HashMap<String, Tunnel>>> = OnceLock::new();
    T.get_or_init(|| Mutex::new(HashMap::new()))
}

/// 오래 도는 프로세스(`tsh proxy db`)를 띄워 이름으로 잡아 둔다. 출력은 로그 파일로.
pub fn spawn_tunnel(key: &str, program: &str, args: &[String], log: &Path) -> Result<u32, String> {
    stop_tunnel(key);
    if let Some(d) = log.parent() {
        let _ = std::fs::create_dir_all(d);
    }
    let f = std::fs::OpenOptions::new().create(true).append(true).open(log).map_err(|e| e.to_string())?;
    let f2 = f.try_clone().map_err(|e| e.to_string())?;
    let mut cmd = Command::new(program);
    cmd.args(args).stdin(Stdio::null()).stdout(f).stderr(f2);
    hide(&mut cmd);
    let child = cmd.spawn().map_err(|e| format!("{program} 실행 실패: {e}"))?;
    let pid = child.id();
    tunnels().lock().unwrap().insert(key.to_string(), Tunnel { child });
    Ok(pid)
}

/// 돌고 있으면 None, 끝났으면 종료 코드 (모르는 이름은 Some(-1)).
pub fn tunnel_exit(key: &str) -> Option<i32> {
    let mut map = tunnels().lock().unwrap();
    let Some(t) = map.get_mut(key) else { return Some(-1) };
    match t.child.try_wait() {
        Ok(None) => None,
        Ok(Some(s)) => {
            map.remove(key);
            Some(s.code().unwrap_or(-1))
        }
        Err(_) => {
            map.remove(key);
            Some(-1)
        }
    }
}

pub fn stop_tunnel(key: &str) {
    if let Some(mut t) = tunnels().lock().unwrap().remove(key) {
        kill_tree(&mut t.child);
    }
}

pub fn stop_all_tunnels() {
    let keys: Vec<String> = tunnels().lock().unwrap().keys().cloned().collect();
    for k in keys {
        stop_tunnel(&k);
    }
}

/// 포트를 듣고 있는 프로세스 이미지 이름 (netstat + tasklist). 모르면 None.
pub fn port_owner(port: u16) -> Option<(u32, String)> {
    #[cfg(windows)]
    {
        let r = run("netstat", &["-ano".into(), "-p".into(), "TCP".into()], RunOptions { timeout_ms: Some(5000), ..Default::default() });
        let pid = r.stdout.lines().find_map(|l| {
            let parts: Vec<&str> = l.split_whitespace().collect();
            (parts.len() >= 5 && parts[3].eq_ignore_ascii_case("LISTENING") && parts[1].ends_with(&format!(":{port}")))
                .then(|| parts[4].parse::<u32>().ok())
                .flatten()
        })?;
        let t = run(
            "tasklist",
            &["/FI".into(), format!("PID eq {pid}"), "/FO".into(), "CSV".into(), "/NH".into()],
            RunOptions { timeout_ms: Some(5000), ..Default::default() },
        );
        let name = t.stdout.split(',').next().unwrap_or("").trim_matches('"').to_string();
        Some((pid, name))
    }
    #[cfg(not(windows))]
    {
        let _ = port;
        None
    }
}

pub fn kill_pid(pid: u32) {
    #[cfg(windows)]
    {
        let _ = hide(&mut Command::new("taskkill"))
            .args(["/PID", &pid.to_string(), "/T", "/F"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
    #[cfg(not(windows))]
    let _ = pid;
}

// ---- TOTP ----

pub fn base32_decode(s: &str) -> Option<Vec<u8>> {
    let clean: String = s.chars().filter(|c| !c.is_whitespace() && *c != '=' && *c != '-').collect::<String>().to_uppercase();
    if clean.is_empty() {
        return None;
    }
    let mut out = Vec::new();
    let (mut buf, mut bits) = (0u32, 0u32);
    for c in clean.chars() {
        let v = match c {
            'A'..='Z' => c as u32 - 'A' as u32,
            '2'..='7' => c as u32 - '2' as u32 + 26,
            _ => return None,
        };
        buf = (buf << 5) | v;
        bits += 5;
        if bits >= 8 {
            bits -= 8;
            out.push((buf >> bits) as u8 & 0xff);
        }
    }
    Some(out)
}

pub fn totp(secret: &str, unix: u64) -> Option<String> {
    use hmac::{Hmac, Mac};
    let key = base32_decode(secret)?;
    let mut mac = Hmac::<sha1::Sha1>::new_from_slice(&key).ok()?;
    mac.update(&(unix / 30).to_be_bytes());
    let h = mac.finalize().into_bytes();
    let off = (h[19] & 0x0f) as usize;
    let n = ((h[off] as u32 & 0x7f) << 24) | ((h[off + 1] as u32) << 16) | ((h[off + 2] as u32) << 8) | h[off + 3] as u32;
    Some(format!("{:06}", n % 1_000_000))
}

fn now_unix() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

// ---- tsh login (ConPTY) ----

#[derive(Serialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct LoginResult {
    pub ok: bool,
    pub message: String,
    pub transcript: String,
    pub exit_code: i32,
    pub timed_out: bool,
    pub duration_ms: u64,
    /// 실제로 쓴 OTP 30초 구간 번호 (다음 로그인에서 같은 코드를 다시 쓰지 않게)
    pub otp_counter: Option<u64>,
}

const PROMPTS: [&[&str]; 3] = [
    &["press [enter] to continue"],
    &["enter password"],
    &["enter your otp token", "enter a code from a otp device", "enter an otp code"],
];

fn strip_ansi(s: &str) -> String {
    let mut out = String::new();
    let mut it = s.chars().peekable();
    while let Some(c) = it.next() {
        if c == '\u{1b}' {
            match it.peek() {
                Some('[') => {
                    it.next();
                    while let Some(&n) = it.peek() {
                        it.next();
                        if n.is_ascii_alphabetic() {
                            break;
                        }
                    }
                }
                Some(']') => {
                    // OSC: BEL 이나 ESC \ 까지
                    while let Some(n) = it.next() {
                        if n == '\u{7}' {
                            break;
                        }
                        if n == '\u{1b}' {
                            it.next();
                            break;
                        }
                    }
                }
                _ => {
                    it.next();
                }
            }
        } else {
            out.push(c);
        }
    }
    out
}

fn terminal_replies(out: &str) -> Vec<&'static str> {
    let mut r = Vec::new();
    if out.contains("\u{1b}]10;?") {
        r.push("\u{1b}]10;rgb:0000/0000/0000\u{1b}\\");
    }
    if out.contains("\u{1b}]11;?") {
        r.push("\u{1b}]11;rgb:ffff/ffff/ffff\u{1b}\\");
    }
    if out.contains("\u{1b}[6n") {
        r.push("\u{1b}[1;1R");
    }
    if out.contains("\u{1b}[c") || out.contains("\u{1b}[0c") {
        r.push("\u{1b}[?1;2c");
    }
    r
}

/// 마지막 의미 있는 줄 (ERROR: 줄 우선). 비밀값은 가린다.
pub fn login_tail(all: &str, secrets: &[String], code: i32) -> String {
    let mut t = strip_ansi(all);
    for s in secrets.iter().filter(|s| !s.is_empty()) {
        t = t.replace(s.as_str(), "***");
    }
    let lines: Vec<&str> = t.split(['\n', '\r']).map(str::trim).filter(|l| !l.is_empty()).collect();
    let shown: Vec<&str> = match lines.iter().rev().find(|l| l.contains("ERROR:")) {
        Some(e) => vec![e],
        None => lines.iter().rev().take(3).rev().copied().collect(),
    };
    format!("tsh 로그인 실패 (exit {code}){}", if shown.is_empty() { String::new() } else { format!(": {}", shown.join(" / ")) })
}

/// `tsh login` 을 가상 콘솔(ConPTY) 안에서 돌리고 Enter → 비밀번호 → OTP 프롬프트에 답한다.
/// OTP 는 프롬프트가 나온 순간에 계산한다 (30초 경계에 걸리지 않게).
pub fn pty_login(program: &str, args: &[String], env: &HashMap<String, String>, password: &str, otp_secret: &str, min_counter: Option<u64>, timeout: Duration) -> LoginResult {
    use portable_pty::{native_pty_system, CommandBuilder, PtySize};
    let start = Instant::now();
    let mut secrets = vec![password.to_string()];
    let fail = |m: String| LoginResult { message: m, exit_code: -1, ..Default::default() };
    let pty = native_pty_system();
    let pair = match pty.openpty(PtySize { rows: 40, cols: 200, pixel_width: 0, pixel_height: 0 }) {
        Ok(p) => p,
        Err(e) => return fail(format!("가상 콘솔을 만들지 못했어요: {e}")),
    };
    let mut cb = CommandBuilder::new(program);
    cb.args(args);
    cb.env("TERM", "xterm");
    for (k, v) in env {
        cb.env(k, v);
    }
    let mut child = match pair.slave.spawn_command(cb) {
        Ok(c) => c,
        Err(e) => return fail(format!("tsh 실행 실패: {e}")),
    };
    drop(pair.slave);
    let mut reader = match pair.master.try_clone_reader() {
        Ok(r) => r,
        Err(e) => return fail(e.to_string()),
    };
    let mut writer = match pair.master.take_writer() {
        Ok(w) => w,
        Err(e) => return fail(e.to_string()),
    };
    let (tx, rx) = std::sync::mpsc::channel::<Vec<u8>>();
    std::thread::spawn(move || {
        let mut b = [0u8; 4096];
        loop {
            match reader.read(&mut b) {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    if tx.send(b[..n].to_vec()).is_err() {
                        break;
                    }
                }
            }
        }
    });
    let mut transcript = String::new();
    let (mut buf, mut all) = (String::new(), String::new());
    let mut sent = [0u32; 3];
    let mut failure: Option<String> = None;
    let mut timed_out = false;
    let deadline = start + timeout;
    let mut exit: Option<i32> = None;
    let mut used_counter: Option<u64> = None;
    loop {
        if Instant::now() > deadline {
            timed_out = true;
            failure = Some(format!("시간 초과 ({}초) · {}", timeout.as_secs(), login_tail(&all, &secrets, -1)));
            break;
        }
        match rx.recv_timeout(Duration::from_millis(200)) {
            Ok(bytes) => {
                let s = String::from_utf8_lossy(&bytes).into_owned();
                transcript.push_str(&format!("[{:>6}ms] < {}\n", start.elapsed().as_millis(), s.escape_debug()));
                buf.push_str(&s);
                all.push_str(&s);
                for r in terminal_replies(&s) {
                    let _ = writer.write_all(r.as_bytes());
                }
                let lower = strip_ansi(&buf).to_lowercase();
                if let Some(i) = PROMPTS.iter().position(|alts| alts.iter().any(|a| lower.contains(a))) {
                    sent[i] += 1;
                    if sent[i] > 1 {
                        failure = Some("같은 프롬프트가 다시 나왔어요 (비밀번호/OTP 거절?)".into());
                        break;
                    }
                    let answer = match i {
                        0 => String::new(),
                        1 => password.to_string(),
                        _ => {
                            // 직전 로그인과 같은 30초 구간이면 다음 구간까지 기다린다 (같은 코드는 Teleport 가 거부할 수 있다)
                            let mut now = now_unix();
                            if min_counter.is_some_and(|m| now / 30 <= m) {
                                std::thread::sleep(Duration::from_millis((30 - now % 30) * 1000 + 500));
                                now = now_unix();
                            }
                            used_counter = Some(now / 30);
                            let code = totp(otp_secret, now).unwrap_or_default();
                            secrets.push(code.clone());
                            code
                        }
                    };
                    // tsh 가 입력 모드를 바꾸기 전에 보내면 앞 글자가 버려질 수 있다
                    std::thread::sleep(Duration::from_millis(300));
                    transcript.push_str(&format!("[{:>6}ms] > {}\n", start.elapsed().as_millis(), if i == 0 { "⏎" } else { "***⏎" }));
                    let _ = writer.write_all(format!("{answer}\r\n").as_bytes());
                    let _ = writer.flush();
                    buf.clear();
                }
            }
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {
                if let Ok(Some(s)) = child.try_wait() {
                    exit = Some(s.exit_code() as i32);
                    // 남은 출력 마저 받기
                    while let Ok(bytes) = rx.recv_timeout(Duration::from_millis(100)) {
                        all.push_str(&String::from_utf8_lossy(&bytes));
                    }
                    break;
                }
            }
            Err(_) => {
                if let Ok(s) = child.wait() {
                    exit = Some(s.exit_code() as i32);
                }
                break;
            }
        }
    }
    if failure.is_some() {
        let _ = child.kill();
    }
    let code = exit.or_else(|| child.wait().ok().map(|s| s.exit_code() as i32)).unwrap_or(-1);
    let mut transcript_safe = transcript;
    for s in secrets.iter().filter(|s| !s.is_empty()) {
        transcript_safe = transcript_safe.replace(s.as_str(), "***");
    }
    let ok = failure.is_none() && code == 0;
    LoginResult {
        ok,
        message: if ok { String::new() } else { failure.unwrap_or_else(|| login_tail(&all, &secrets, code)) },
        transcript: transcript_safe,
        exit_code: code,
        timed_out,
        duration_ms: start.elapsed().as_millis() as u64,
        otp_counter: used_counter,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn totp_matches_rfc6238() {
        // RFC 6238 부록 B: 비밀값 "12345678901234567890", T=59 → 94287082 (8자리) → 끝 6자리 287082
        let secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
        assert_eq!(totp(secret, 59).unwrap(), "287082");
        assert_eq!(totp(secret, 1111111109).unwrap(), "081804");
        assert!(totp("!!", 0).is_none());
        assert_eq!(base32_decode("gezd gnbv").unwrap(), b"12345".to_vec());
    }

    #[test]
    fn tail_prefers_error_line_and_redacts() {
        let out = "banner\r\nmore\r\nERROR: invalid credentials pw123\r\n";
        assert_eq!(login_tail(out, &["pw123".into()], 1), "tsh 로그인 실패 (exit 1): ERROR: invalid credentials ***");
        assert_eq!(strip_ansi("\u{1b}[31mred\u{1b}[0m \u{1b}]11;?\u{1b}\\x"), "red x");
    }

    #[test]
    fn run_reports_exit_and_timeout() {
        let r = run("cmd", &["/C".into(), "echo hi & exit 3".into()], RunOptions::default());
        assert_eq!(r.code, 3);
        assert!(r.stdout.contains("hi"));
        let r = run("cmd", &["/C".into(), "ping -n 5 127.0.0.1 >nul".into()], RunOptions { timeout_ms: Some(300), ..Default::default() });
        assert!(r.timed_out);
        let r = run("no-such-program-xyz", &[], RunOptions::default());
        assert_eq!(r.code, -1);
    }
}
