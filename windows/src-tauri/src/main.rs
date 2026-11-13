// 콘솔 창을 띄우지 않는다 (릴리스 빌드)
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    // `--hook`·`--add-todo` 는 창 없이 처리하고 끝낸다 (Claude Code 훅·atm-todo 스킬)
    let args: Vec<String> = std::env::args().collect();
    if let Some(code) = atm_lib::handle_cli(&args) {
        std::process::exit(code);
    }
    atm_lib::run()
}
