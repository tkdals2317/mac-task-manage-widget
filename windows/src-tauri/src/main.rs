// 콘솔 창을 띄우지 않는다 (릴리스 빌드)
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    atm_lib::run()
}
