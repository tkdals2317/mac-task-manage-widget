import AppKit
import CoreImage
import SwiftUI
import UniformTypeIdentifiers
import TaskWidgetCore

struct DBEntry: Identifiable {
    let name: String
    let isProd: Bool
    var kind: TeleportTunnel.Kind = .db
    var checked = false
    var dbUser = "developer"
    var portText = ""
    var id: String { name }
}

/// OTP 콜백(백그라운드)에서 쓴 카운터를 받아 오는 상자.
final class SetupOTPBox: @unchecked Sendable { var counter: Int64? }

@MainActor
final class TeleportSetupModel: ObservableObject {
    @Published var step = 1
    @Published var proxy: String
    @Published var user: String
    @Published var password = ""
    @Published var otpKey = ""
    @Published var busy = false
    @Published var error: String?
    @Published var note: String?
    @Published var entries: [DBEntry] = []

    private let tp: TeleportManager
    private var saved: TeleportConfig
    /// 목록을 받지 못한 종류의 저장된 터널. 화면에 없다고 저장 때 지워지지 않게 그대로 다시 넣는다.
    private var kept: [TeleportTunnel] = []

    init(tp: TeleportManager) {
        self.tp = tp
        saved = tp.config
        proxy = tp.config.proxy
        user = tp.config.user
    }

    var canNext: Bool {
        !busy && !TeleportConfig.cleanID(proxy).isEmpty && !TeleportConfig.cleanID(user).isEmpty && !password.isEmpty && TOTP(input: otpKey) != nil
    }

    var checked: [DBEntry] { entries.filter(\.checked) }
    var duplicates: Set<Int> {
        TeleportConfig.duplicatePorts(checked.map { TeleportTunnel(name: $0.name, port: Int($0.portText) ?? -1) } + kept)
    }
    var canSave: Bool {
        !checked.isEmpty && duplicates.isEmpty
            && checked.allSatisfy { (Int($0.portText).map { (1024...65535).contains($0) } ?? false) && ($0.kind == .app || !$0.dbUser.trimmed.isEmpty) }
    }

    // MARK: Step 1

    func next() async {
        guard canNext, let tsh = tp.tshPath, let totp = TOTP(input: otpKey) else { return }
        busy = true; error = nil; note = nil
        defer { busy = false }
        var login = TeleportLogin(tsh: tsh, proxy: TeleportConfig.cleanID(proxy), user: TeleportConfig.cleanID(user))
        // 늘 빈 임시 프로필로 로그인해 비밀번호·OTP 를 실제로 확인한다. ~/.tsh 에 유효한 세션이 남아 있으면
        // (터미널에서 로그인해 둔 경우 등) tsh 가 비밀번호를 묻지 않아, 틀린 비밀번호가 검증 없이 저장됐다.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("atm-tsh-verify-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        login.extraEnvironment["TELEPORT_HOME"] = dir.path
        let tempHome: URL? = dir
        let pw = password
        let last = TeleportManager.lastOTPCounter
        let used = SetupOTPBox()
        let (res, report) = await Task.detached { [login] in
            login.runReported(password: pw, otp: { let r = totp.freshCode(after: last); used.counter = r.counter; return r.code })
        }.value
        // 이어지는 실제 로그인이 같은 코드를 다시 쓰지 않게 (Teleport 는 재사용 코드를 거부한다)
        if let c = used.counter { TeleportManager.lastOTPCounter = c }
        TeleportLoginLog.append(kind: "setup", user: TeleportConfig.cleanID(user), proxy: TeleportConfig.cleanID(proxy), tsh: tsh, report: report, result: res)
        if let d = tempHome { try? FileManager.default.removeItem(at: d) }
        if case .failure(let e) = res { error = e.message; return }
        do {
            try TeleportSecrets(password: password, otpSecret: otpKey.trimmed).save()
        } catch {
            self.error = "비밀 정보 저장 실패: \(error)"; return
        }
        saved.proxy = TeleportConfig.cleanID(proxy)
        saved.user = TeleportConfig.cleanID(user)
        try? saved.save()
        tp.reloadConfig()
        // 검증은 임시 프로필에서 했으니, 실제 프로필이 로그인돼 있지 않으면 여기서 로그인한다.
        guard await tp.ensureLoggedIn(kind: "setup") else { error = tp.message ?? "로그인 실패"; return }
        await loadDBs(tsh: tsh)
    }

    /// 화면에 묶어 보여줄 그룹: teleport.json 에 적은 그룹이 있으면 그걸, 없으면 이름의 첫 토큰.
    func displayGroup(_ name: String) -> String {
        saved.tunnels.first { $0.name == name }?.group ?? TeleportTunnel.group(forName: name)
    }

    /// 이미 비밀번호·OTP 키가 저장돼 있는지 (설정 도우미를 다시 열었을 때 다시 입력하지 않게).
    var hasSavedSecrets: Bool { tp.hasSecrets }

    /// 저장된 정보로 로그인한 뒤 DB·앱 목록을 받는다.
    func loadWithSaved() async {
        error = nil
        guard await tp.ensureLoggedIn(kind: "setup") else {
            error = "저장된 정보로 로그인하지 못했어요. 비밀번호와 OTP 키를 다시 넣어 주세요."
            return
        }
        await loadDBs()
    }

    // MARK: Step 2

    /// `tsh db ls` 와 `tsh apps ls` 를 함께 받는다. 앱 목록은 권한이 없으면 실패할 수 있어, 앱 쪽 실패는 DB 목록을 막지 않는다.
    func loadDBs(tsh: String? = nil) async {
        guard let tsh = tsh ?? tp.tshPath else { return }
        busy = true; error = nil; note = nil; kept = []
        defer { busy = false }
        let (r, ar) = await Task.detached {
            (ProcessRunner.run(executable: tsh, arguments: ["db", "ls", "--format=json"], timeout: 30),
             ProcessRunner.run(executable: tsh, arguments: ["apps", "ls", "--format=json"], timeout: 30))
        }.value
        let dbs = r.status == 0 ? TeleportTsh.parseDBList(json: Data(r.stdout.utf8)) : []
        // apps ls 출력(spec)에는 자격 값이 들어 있어 stdout/stderr 를 로그에 남기지 않는다.
        if ar.status != 0 { DiagLog.append("teleport setup: tsh apps ls 실패 (exit \(ar.status)), DB 만 표시") }
        let savedDBs = saved.tunnels.filter { $0.kind == .db }, savedApps = saved.tunnels.filter { $0.kind == .app }
        // states·wanted 가 이름으로 묶여 있어 DB 와 이름이 같은 앱은 뺀다 (DB 우선).
        // DB 목록을 못 받았으면 저장된 DB 터널 이름을 기준으로 삼는다.
        let dbNames = Set(dbs.map(\.name) + (r.status != 0 ? savedDBs.map(\.name) : []))
        let apps = ar.status == 0 ? TeleportTsh.parseAppList(json: Data(ar.stdout.utf8)).filter { !dbNames.contains($0.name) } : []
        if dbs.isEmpty && apps.isEmpty {
            error = r.status != 0 ? "tsh db ls 실패: \(r.stderr.trimmed.suffix(200))" : "접근 가능한 DB·앱이 없어요"
            step = 2; entries = []; return
        }
        var notes: [String] = []
        if r.status != 0 {
            notes.append("tsh db ls 실패: \(r.stderr.trimmed.suffix(200))" + (savedDBs.isEmpty ? "" : " · 저장된 DB 터널은 그대로 둬요"))
            kept += savedDBs
        }
        if ar.status != 0, !savedApps.isEmpty {
            notes.append("앱 목록을 받지 못했어요 · 저장된 앱 터널은 그대로 둬요")
            kept += savedApps
        }
        let dropped = ar.status == 0 ? savedApps.filter { dbNames.contains($0.name) }.map(\.name) : []
        if !dropped.isEmpty { notes.append("이름이 같은 DB 가 있어 앱 터널 \(dropped.joined(separator: ", ")) 는 목록에서 빠졌어요") }
        note = notes.isEmpty ? nil : notes.joined(separator: "\n")
        let prev = Dictionary(saved.tunnels.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        func entry(_ x: TeleportDB, _ kind: TeleportTunnel.Kind) -> DBEntry {
            var e = DBEntry(name: x.name, isProd: x.isProd, kind: kind)
            if let t = prev[x.name], t.kind == kind { e.checked = true; e.dbUser = t.dbUser; e.portText = String(t.port) }
            return e
        }
        entries = dbs.map { entry($0, .db) } + apps.map { entry($0, .app) }
        step = 2
    }

    func setChecked(_ id: String, _ on: Bool) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].checked = on
        if on, entries[i].portText.isEmpty {
            let used = Set(entries.filter { $0.checked && $0.id != id }.compactMap { Int($0.portText) } + kept.map(\.port))
            entries[i].portText = String(TeleportConfig.nextFreePort(startingAt: TeleportConfig.basePort, used: used))
        }
    }

    func save() {
        error = nil
        var c = saved
        // teleport.json 에 직접 적은 그룹 이름은 유지한다.
        let prevGroup = Dictionary(saved.tunnels.map { ($0.name, $0.groupOverride) }, uniquingKeysWith: { a, _ in a })
        c.tunnels = checked.map { e in
            var t = e.kind == .app
                ? TeleportTunnel(name: e.name, port: Int(e.portText) ?? 0, kind: .app)
                : TeleportTunnel(name: e.name, dbUser: e.dbUser.trimmed, port: Int(e.portText) ?? 0)
            t.groupOverride = prevGroup[e.name] ?? nil
            return t
        }
        // 목록을 받지 못한 종류의 저장된 터널은 유지한다 (같은 이름을 새로 고른 게 있으면 그쪽 우선).
        let names = Set(c.tunnels.map(\.name))
        c.tunnels += kept.filter { !names.contains($0.name) }
        do {
            try c.save()
            tp.setupFinished(c)
            password = ""; otpKey = ""   // 저장 끝났으니 화면 상태에서 비밀을 지운다
        } catch {
            self.error = "저장 실패: \(error.localizedDescription)"
        }
    }

    // MARK: QR

    func readQR() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let img = CIImage(contentsOf: url) else { return }
        let det = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let msg = det?.features(in: img).compactMap { ($0 as? CIQRCodeFeature)?.messageString }.first
        if let m = msg, TOTP(input: m) != nil { otpKey = m; error = nil } else {
            error = msg == nil ? "이미지에서 QR 코드를 찾지 못했어요" : "otpauth://totp QR 이 아니에요"
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct TeleportSetupView: View {
    @ObservedObject var tp: TeleportManager
    @StateObject private var m: TeleportSetupModel
    @Environment(\.fontScale) private var scale

    init(tp: TeleportManager) {
        self.tp = tp
        _m = StateObject(wrappedValue: TeleportSetupModel(tp: tp))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(m.step == 1 ? "1/2  계정" : "2/2  DB·앱 선택")
                        .font(.system(size: 12 * scale, weight: .semibold)).foregroundStyle(.secondary)
                    if m.step == 1 { account } else { dbs }
                    if let e = m.error {
                        Text(e).font(.system(size: 11 * scale)).foregroundStyle(.red).textSelection(.enabled)
                        Button("로그") { NSWorkspace.shared.open(TeleportManager.loginLogURL) }.controlSize(.mini)
                    }
                    if let n = m.note { Text(n).font(.system(size: 11 * scale)).foregroundStyle(.orange) }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                if tp.isConfigured { Button("취소") { tp.setupRequested = false } }
                if m.step == 2 { Button("이전") { m.step = 1; m.error = nil } }
                Spacer()
                if m.busy { ProgressView().controlSize(.small) }
                if m.step == 1 {
                    Button("다음") { Task { await m.next() } }.disabled(!m.canNext).keyboardShortcut(.defaultAction)
                } else {
                    Button("\(m.checked.count)개 저장") { m.save() }.disabled(!m.canSave).keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.small).padding(.horizontal, 12).padding(.vertical, 6)
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 8) {
            field("프록시") { TextField("", text: $m.proxy, prompt: Text("teleport.example.com")) }
            field("사용자 ID") {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Teleport 계정 (DB 사용자 developer 아님)", text: $m.user)
                    if let u = TOTP.accountUser(in: m.otpKey), u != TeleportConfig.cleanID(m.user) {
                        Text("OTP 키의 계정은 \(u) 이에요").font(.system(size: 10.5 * scale)).foregroundStyle(.orange)
                    }
                }
            }
            field("비밀번호") { SecureField("", text: $m.password) }
            field("OTP 키") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("base32 키 또는 otpauth:// URL", text: $m.otpKey)
                        .onChange(of: m.otpKey) { _, k in
                            if TeleportConfig.cleanID(m.user).isEmpty, let u = TOTP.accountUser(in: k) { m.user = u }
                        }
                    HStack {
                        Button("QR 이미지로 읽기") { m.readQR() }.controlSize(.small)
                        Link("OTP 키 구하는 법 ↗", destination: Links.otpKeyGuide).font(.system(size: 11 * scale))
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            if let t = TOTP(input: m.otpKey) {
                                let c = t.code(at: ctx.date)
                                Text("현재 코드 \(c.prefix(3)) \(c.suffix(3))")
                                    .monospacedDigit().foregroundStyle(.secondary)
                                    .help("\(TOTP.secondsLeft(at: ctx.date))초 후 갱신")
                            }
                        }
                    }
                }
            }
            Text("비밀번호와 OTP 키는 설정에서 고른 저장 위치(키체인 또는 secrets.json)에만 저장돼요. 다음을 누르면 실제로 로그인해 확인합니다.")
                .font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
        .disabled(m.busy)
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.system(size: 12 * scale)).frame(width: 64, alignment: .trailing).padding(.top, 3)
            content()
        }
    }

    private var dbs: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DB 접속 툴: localhost, 이 포트, DB 사용자, 비밀번호 없음")
                .font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
            if m.entries.contains(where: { $0.kind == .app }) {
                Text("HTTP 앱: http://localhost:포트, 인증 자동")
                    .font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
            }
            if m.entries.isEmpty && !m.busy {
                Button("다시 불러오기") { Task { await m.loadDBs() } }.controlSize(.small)
            }
            let dup = m.duplicates
            ForEach(m.entries) { e in
                HStack(spacing: 6) {
                    Toggle(isOn: Binding(get: { e.checked }, set: { m.setChecked(e.id, $0) })) {
                        Text(e.name).font(.system(size: 12 * scale))
                    }
                    .toggleStyle(.checkbox)
                    if e.kind == .app { Text("HTTP").font(.system(size: 10.5 * scale, weight: .semibold)).foregroundStyle(.secondary) }
                    if e.isProd { Text("운영").font(.system(size: 10.5 * scale, weight: .semibold)).foregroundStyle(.red) }
                    Spacer()
                    if e.checked, let i = m.entries.firstIndex(where: { $0.id == e.id }) {
                        // 앱은 DB 사용자가 없다 (tsh proxy app 은 포트만 받는다).
                        if e.kind == .db { TextField("DB 사용자", text: $m.entries[i].dbUser).frame(width: 90) }
                        TextField("포트", text: $m.entries[i].portText).frame(width: 60)
                            .foregroundStyle(dup.contains(Int(e.portText) ?? -1) ? Color.red : Color.primary)
                    }
                }
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}
