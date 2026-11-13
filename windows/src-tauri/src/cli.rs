//! 창을 띄우지 않는 명령줄 진입점 (Mac main.swift 와 같은 두 가지).
//! - `atm.exe --hook` : Claude Code 훅. stdin JSON 을 activity.jsonl 에 한 줄 덧붙인다.
//! - `atm.exe --add-todo --title ...` : atm-todo 스킬. inbox/<uuid>.json 을 남기고 결과 JSON 한 줄을 출력한다.
//! 둘 다 앱(todos.json 의 유일한 쓰기 주체)과 동시에 돌아도 안전하다.

use std::fs;
use std::io::{Read, Write};
use std::path::Path;

use serde_json::{json, Map, Value};

use crate::data_dir;

const PROMPT_CAP: usize = 2000;
const STOP_CAP: usize = 4000;

/// 처리했으면 종료 코드. 아니면 None (앱을 띄운다).
pub fn handle(args: &[String]) -> Option<i32> {
    if args.iter().any(|a| a == "--hook") {
        let mut input = Vec::new();
        let _ = std::io::stdin().read_to_end(&mut input);
        handle_hook(&input, &data_dir(), chrono::Local::now());
        return Some(0);
    }
    if let Some(i) = args.iter().position(|a| a == "--add-todo") {
        let (out, code) = add_todo(&args[i + 1..], &data_dir(), chrono::Local::now());
        println!("{out}");
        let _ = std::io::stdout().flush();
        return Some(code);
    }
    None
}

// ---- --hook ----

fn cap(s: &str, n: usize) -> String {
    s.trim().chars().take(n).collect()
}

/// 훅 stdin → 한 줄 레코드. 대상 이벤트가 아니거나 내용이 없으면 None.
pub fn hook_record(input: &[u8], exclude_prefix: &str, now: chrono::DateTime<chrono::Local>) -> Option<String> {
    let v: Value = serde_json::from_slice(input).ok()?;
    let event = v.get("hook_event_name")?.as_str()?;
    let cwd = v.get("cwd")?.as_str()?;
    if cwd.is_empty() {
        return None;
    }
    if !exclude_prefix.is_empty() && cwd.to_lowercase().starts_with(&exclude_prefix.to_lowercase()) {
        return None;
    }
    let (kind, raw, n) = match event {
        "UserPromptSubmit" => ("prompt", v.get("prompt").and_then(Value::as_str).unwrap_or(""), PROMPT_CAP),
        "Stop" => ("stop", v.get("last_assistant_message").and_then(Value::as_str).unwrap_or(""), STOP_CAP),
        _ => return None,
    };
    let text = cap(raw, n);
    if text.is_empty() {
        return None;
    }
    let rec = json!({
        "cwd": cwd,
        "event": kind,
        "session": v.get("session_id").and_then(Value::as_str).unwrap_or(""),
        "text": text,
        "ts": now.to_rfc3339_opts(chrono::SecondsFormat::Secs, false),
    });
    Some(rec.to_string())
}

fn handle_hook(input: &[u8], dir: &Path, now: chrono::DateTime<chrono::Local>) {
    let Some(line) = hook_record(input, &dir.to_string_lossy(), now) else { return };
    let r = (|| -> std::io::Result<()> {
        fs::create_dir_all(dir)?;
        // append 모드 한 번 쓰기라 여러 세션이 동시에 써도 줄이 섞이지 않는다
        let mut f = fs::OpenOptions::new().create(true).append(true).open(dir.join("activity.jsonl"))?;
        f.write_all(format!("{line}\n").as_bytes())
    })();
    if let Err(e) = r {
        let logs = dir.join("logs");
        let _ = fs::create_dir_all(&logs);
        if let Ok(mut f) = fs::OpenOptions::new().create(true).append(true).open(logs.join("hook.log")) {
            let _ = writeln!(f, "{} append failed: {e}", now.to_rfc3339());
        }
    }
}

// ---- --add-todo ----

fn normalized_title(s: &str) -> Option<String> {
    let t = s.split_whitespace().collect::<Vec<_>>().join(" ");
    if t.is_empty() { None } else { Some(t) }
}

fn valid_due(s: &str) -> bool {
    chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").is_ok()
        && s.len() == 10
        && s.chars().enumerate().all(|(i, c)| if i == 4 || i == 7 { c == '-' } else { c.is_ascii_digit() })
}

/// tags.json 의 태그 이름들. 파일이 없으면 기본 태그 (lib/tags.ts defaultTagConfig 와 같음).
fn tag_names(dir: &Path) -> Vec<String> {
    let names: Option<Vec<String>> = fs::read_to_string(dir.join("tags.json")).ok().and_then(|s| {
        let v: Value = serde_json::from_str(&s).ok()?;
        Some(
            v.get("groups")?
                .as_array()?
                .iter()
                .flat_map(|g| g.get("tags").and_then(Value::as_array).cloned().unwrap_or_default())
                .filter_map(|t| t.get("name").and_then(Value::as_str).map(str::to_string))
                .collect(),
        )
    });
    names.unwrap_or_else(|| ["긴급", "높음", "보통", "낮음"].iter().map(|s| s.to_string()).collect())
}

pub fn add_todo(args: &[String], dir: &Path, now: chrono::DateTime<chrono::Local>) -> (String, i32) {
    let fail = |m: String| (json!({ "ok": false, "error": m }).to_string(), 2);
    let (mut title, mut due, mut memo) = (String::new(), None::<String>, None::<String>);
    let (mut tags, mut subs) = (Vec::<String>::new(), Vec::<String>::new());
    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_str();
        if !["--title", "--due", "--tag", "--memo", "--sub"].contains(&a) {
            i += 1;
            continue;
        }
        let Some(v) = args.get(i + 1).cloned() else { return fail(format!("{a} 값이 없습니다")) };
        match a {
            "--title" => title = v,
            "--due" => due = Some(v),
            "--tag" => tags.push(v),
            "--sub" => subs.push(v),
            _ => memo = Some(v),
        }
        i += 2;
    }
    let Some(t) = normalized_title(&title) else { return fail("제목이 비어 있습니다".into()) };
    if let Some(d) = &due {
        if !valid_due(d) {
            return fail(format!("마감일 형식이 잘못되었습니다 (YYYY-MM-DD): {d}"));
        }
    }
    let known_names = tag_names(dir);
    let (mut known, mut unknown) = (Vec::new(), Vec::new());
    for raw in tags {
        let n = raw.trim().to_string();
        if n.is_empty() {
            continue;
        }
        if known_names.iter().any(|k| k.to_lowercase() == n.to_lowercase()) {
            known.push(n);
        } else {
            unknown.push(n);
        }
    }
    let subtasks: Vec<String> = subs.iter().filter_map(|s| normalized_title(s)).collect();
    let memo = memo.as_deref().and_then(normalized_title);
    let id = uuid_v4().to_uppercase();
    let mut item = Map::new();
    item.insert("title".into(), json!(t));
    if let Some(d) = &due {
        item.insert("due".into(), json!(d));
    }
    item.insert("tags".into(), json!(known));
    if let Some(m) = &memo {
        item.insert("memo".into(), json!(m));
    }
    item.insert("subtasks".into(), json!(subtasks));
    item.insert("createdAt".into(), json!(now.with_timezone(&chrono::Utc).format("%Y-%m-%dT%H:%M:%SZ").to_string()));
    let inbox = dir.join("inbox");
    let w = (|| -> std::io::Result<()> {
        fs::create_dir_all(&inbox)?;
        let tmp = inbox.join(format!("{id}.tmp"));
        fs::write(&tmp, Value::Object(item).to_string())?;
        fs::rename(&tmp, inbox.join(format!("{id}.json")))
    })();
    if let Err(e) = w {
        return fail(format!("inbox 에 쓰지 못했습니다: {e}"));
    }
    (
        json!({ "ok": true, "id": id, "title": t, "due": due, "tags": known, "unknownTags": unknown, "subtasks": subtasks })
            .to_string(),
        0,
    )
}

/// 의존성 없이 무작위 UUID v4 (시간·주소·카운터를 섞은 해시라 충돌 걱정 없는 수준).
pub fn uuid_v4() -> String {
    use std::collections::hash_map::RandomState;
    use std::hash::{BuildHasher, Hasher};
    let mut bytes = [0u8; 16];
    for (k, chunk) in bytes.chunks_mut(8).enumerate() {
        let mut h = RandomState::new().build_hasher();
        h.write_u128(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or(0));
        h.write_usize(k);
        h.write_u32(std::process::id());
        chunk.copy_from_slice(&h.finish().to_le_bytes());
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    format!("{}-{}-{}-{}-{}", &hex[0..8], &hex[8..12], &hex[12..16], &hex[16..20], &hex[20..32])
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn now() -> chrono::DateTime<chrono::Local> {
        chrono::Local.with_ymd_and_hms(2026, 11, 13, 10, 0, 0).unwrap()
    }

    #[test]
    fn hook_keeps_prompt_and_stop_only() {
        let p = br#"{"hook_event_name":"UserPromptSubmit","cwd":"C:\\proj\\shop","session_id":"s1","prompt":"  hi  "}"#;
        let line = hook_record(p, "C:\\Users\\x\\AppData\\Roaming\\TaskWidget", now()).unwrap();
        let v: Value = serde_json::from_str(&line).unwrap();
        assert_eq!(v["event"], "prompt");
        assert_eq!(v["text"], "hi");
        assert!(hook_record(br#"{"hook_event_name":"PreToolUse","cwd":"C:\\p"}"#, "", now()).is_none());
        assert!(hook_record(br#"{"hook_event_name":"Stop","cwd":"C:\\p","last_assistant_message":" "}"#, "", now()).is_none());
        // 데이터 폴더 안에서 돈 세션(요약 생성 자체)은 빼고, 경로 대소문자는 무시
        let own = br#"{"hook_event_name":"Stop","cwd":"c:\\data\\taskwidget\\x","last_assistant_message":"ok"}"#;
        assert!(hook_record(own, "C:\\Data\\TaskWidget", now()).is_none());
        assert!(hook_record(b"not json", "", now()).is_none());
    }

    #[test]
    fn add_todo_writes_inbox_and_reports_unknown_tags() {
        let dir = std::env::temp_dir().join(format!("atm-cli-{}", uuid_v4()));
        let args: Vec<String> = ["--title", " 보고서  작성 ", "--due", "2026-11-14", "--tag", "긴급", "--tag", "없는태그", "--sub", "a", "--memo", "m"]
            .iter().map(|s| s.to_string()).collect();
        let (out, code) = add_todo(&args, &dir, now());
        assert_eq!(code, 0, "{out}");
        let v: Value = serde_json::from_str(&out).unwrap();
        assert_eq!(v["title"], "보고서 작성");
        assert_eq!(v["unknownTags"], json!(["없는태그"]));
        let files: Vec<_> = fs::read_dir(dir.join("inbox")).unwrap().collect();
        assert_eq!(files.len(), 1);
        let (bad, code) = add_todo(&["--title".into(), "x".into(), "--due".into(), "2026-02-30".into()], &dir, now());
        assert_eq!(code, 2, "{bad}");
        let (_, code) = add_todo(&["--title".into(), "  ".into()], &dir, now());
        assert_eq!(code, 2);
        let _ = fs::remove_dir_all(dir);
    }
}
