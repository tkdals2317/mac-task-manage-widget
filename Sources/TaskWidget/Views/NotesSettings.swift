import SwiftUI
import TaskWidgetCore

/// 설정 > 노트: 잠금 비밀번호, Touch ID, Confluence. Form 안에서 Section 들로 펼쳐진다.
struct NotesSettingsSections: View {
    @ObservedObject var notes: NotesModel
    @EnvironmentObject var state: AppState
    /// 입력 중인 값. 저장(AppStorage)은 Enter 나 "연결 확인" 때만 — 반쪽 주소로 요청이 나가지 않게.
    @State private var confluenceDraft = Settings.shared.confluenceBaseURL

    @State private var pw = ""
    @State private var pw2 = ""
    @State private var oldPw = ""
    @State private var showChange = false
    @State private var confirmReset = false
    @State private var askTouchPw = false
    @State private var touchPw = ""
    @State private var message = ""
    @State private var touchMessage = ""
    @State private var isError = false
    @State private var busy = false
    @State private var confluenceStatus = ""

    var body: some View {
        Section {
            if !notes.hasLock {
                pwField("새 비밀번호", $pw)
                pwField("비밀번호 확인", $pw2)
                HStack {
                    Button("만들기") { run { try await notes.createPassword(pw, confirm: pw2); pw = ""; pw2 = ""; return "비밀번호를 만들었어요" } }
                        .disabled(busy)
                    Text("4자 이상").font(.caption).foregroundStyle(.secondary)
                }
                Text("비밀번호를 잊으면 잠긴 메모는 되살릴 수 없습니다.").font(.caption).foregroundStyle(.orange)
            } else {
                LabeledContent("상태", value: "설정됨")
                if showChange {
                    pwField("현재 비밀번호", $oldPw)
                    pwField("새 비밀번호", $pw)
                    pwField("새 비밀번호 확인", $pw2)
                    HStack {
                        Button("변경") {
                            run {
                                try await notes.changePassword(old: oldPw, new: pw, confirm: pw2)
                                oldPw = ""; pw = ""; pw2 = ""; showChange = false
                                return "비밀번호를 바꿨어요"
                            }
                        }
                        .disabled(busy)
                        Button("취소") { showChange = false; oldPw = ""; pw = ""; pw2 = "" }
                    }
                } else {
                    HStack {
                        Button("비밀번호 변경") { showChange = true }
                        Button("비밀번호 초기화", role: .destructive) { confirmReset = true }
                    }
                }
            }
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(isError ? Color.red : Color.secondary)
            }
        } header: {
            Text("잠금 비밀번호")
        } footer: {
            Text("메모마다 잠금을 켤 수 있고, 비밀번호는 모든 잠긴 메모가 함께 씁니다. 잠긴 메모는 패널을 닫거나 5분이 지나면 다시 잠겨요.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("비밀번호를 초기화할까요?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("잠긴 메모를 모두 삭제하고 초기화", role: .destructive) {
                Task { await notes.resetPassword(); message = "초기화했어요"; isError = false }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("잠긴 메모는 비밀번호 없이 열 수 없어서 전부 삭제됩니다. 잠기지 않은 메모는 그대로 남아요.")
        }

        Section {
            Toggle("Touch ID로 열기", isOn: Binding(
                get: { notes.touchIDEnabled || askTouchPw },
                set: { on in
                    if on { askTouchPw = true } else if askTouchPw { askTouchPw = false; touchPw = "" } else { Task { await notes.disableTouchID() } }
                }
            ))
            .disabled(!notes.hasLock || !NotesModel.touchIDAvailable)
            if askTouchPw {
                pwField("잠금 비밀번호", $touchPw).onSubmit { enableTouchID() }
                HStack {
                    Button("켜기") { enableTouchID() }.disabled(busy)
                    Button("취소") { askTouchPw = false; touchPw = "" }
                }
            }
            if !touchMessage.isEmpty {
                Text(touchMessage).font(.caption).foregroundStyle(.red)
            }
            if !NotesModel.touchIDAvailable {
                Text("이 Mac 에서는 Touch ID 를 쓸 수 없어요").font(.caption).foregroundStyle(.secondary)
            } else if !notes.hasLock {
                Text("먼저 잠금 비밀번호를 만드세요").font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Touch ID")
        } footer: {
            Text("Touch ID 를 켜면 메모 열쇠가 앱 비밀 저장소(키체인 또는 secrets.json)에 저장됩니다. 끄면 지워져요.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        Section {
            TextField("주소", text: $confluenceDraft, prompt: Text("https://your-site.atlassian.net"))
                .onSubmit { Settings.shared.confluenceBaseURL = confluenceDraft.trimmingCharacters(in: .whitespaces) }
            HStack {
                Button("연결 확인") {
                    confluenceStatus = "확인 중…"
                    Settings.shared.confluenceBaseURL = confluenceDraft.trimmingCharacters(in: .whitespaces)
                    Task { confluenceStatus = await state.testConfluence(baseURL: confluenceDraft) }
                }
                .disabled(confluenceDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                Text(confluenceStatus).foregroundStyle(.secondary).lineLimit(2)
            }
        } header: {
            Text("Confluence")
        } footer: {
            Text("Jira 와 같은 Atlassian 계정 토큰을 씁니다. 비워 두면 노트 탭에서 Confluence 별표 문서를 숨겨요.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear { Settings.shared.confluenceBaseURL = confluenceDraft.trimmingCharacters(in: .whitespaces) }
    }

    /// grouped Form 의 SecureField 는 prompt 가 없으면 입력칸이 보이지 않는다. 자동완성 말풍선도 막는다.
    private func pwField(_ label: String, _ text: Binding<String>) -> some View {
        SecureField(label, text: text, prompt: Text("입력"))
            .noPasswordSuggestions()
    }

    /// 비동기 동작을 돌리고 결과/오류를 한 줄로 보여준다.
    private func run(_ work: @escaping () async throws -> String) {
        busy = true; message = ""
        Task {
            defer { busy = false }
            do { message = try await work(); isError = false }
            catch { message = error.localizedDescription; isError = true }
        }
    }

    private func enableTouchID() {
        let p = touchPw
        busy = true; touchMessage = ""
        Task {
            defer { busy = false }
            do {
                try await notes.enableTouchID(password: p)
                askTouchPw = false; touchPw = ""; touchMessage = ""
            } catch { touchMessage = error.localizedDescription }
        }
    }
}
