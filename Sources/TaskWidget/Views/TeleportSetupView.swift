import AppKit
import CoreImage
import SwiftUI
import UniformTypeIdentifiers
import TaskWidgetCore

struct DBEntry: Identifiable {
    let name: String
    let isProd: Bool
    var checked = false
    var dbUser = "developer"
    var portText = ""
    var id: String { name }
}

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

    init(tp: TeleportManager) {
        self.tp = tp
        saved = tp.config
        proxy = tp.config.proxy
        user = tp.config.user
    }

    var canNext: Bool {
        !busy && !proxy.trimmed.isEmpty && !user.trimmed.isEmpty && !password.isEmpty && TOTP(input: otpKey) != nil
    }

    var checked: [DBEntry] { entries.filter(\.checked) }
    var duplicates: Set<Int> {
        TeleportConfig.duplicatePorts(checked.map { TeleportTunnel(name: $0.name, port: Int($0.portText) ?? -1) })
    }
    var canSave: Bool {
        !checked.isEmpty && duplicates.isEmpty
            && checked.allSatisfy { (Int($0.portText).map { (1024...65535).contains($0) } ?? false) && !$0.dbUser.trimmed.isEmpty }
    }

    // MARK: Step 1

    func next() async {
        guard canNext, let tsh = tp.tshPath, let totp = TOTP(input: otpKey) else { return }
        busy = true; error = nil; note = nil
        defer { busy = false }
        let wasLoggedIn = tp.loggedIn
        let login = TeleportLogin(tsh: tsh, proxy: proxy.trimmed, user: user.trimmed)
        let pw = password
        let res = await Task.detached { login.run(password: pw, otp: { totp.code() }) }.value
        if case .failure(let e) = res { error = e.message; return }
        if wasLoggedIn { note = "이미 로그인된 세션이 있어 비밀번호는 확인되지 않았어요" }
        do {
            try TeleportSecrets(password: password, otpSecret: otpKey.trimmed).save()
        } catch {
            self.error = "키체인 저장 실패: \(error)"; return
        }
        saved.proxy = proxy.trimmed
        saved.user = user.trimmed
        try? saved.save()
        tp.reloadConfig()
        await loadDBs(tsh: tsh)
    }

    // MARK: Step 2

    func loadDBs(tsh: String? = nil) async {
        guard let tsh = tsh ?? tp.tshPath else { return }
        busy = true; error = nil
        defer { busy = false }
        let r = await Task.detached { ProcessRunner.run(executable: tsh, arguments: ["db", "ls", "--format=json"], timeout: 30) }.value
        let dbs = TeleportTsh.parseDBList(json: Data(r.stdout.utf8))
        if r.status != 0 || dbs.isEmpty {
            error = r.status != 0 ? "tsh db ls 실패: \(r.stderr.trimmed.suffix(200))" : "접근 가능한 DB 가 없어요"
            step = 2; entries = []; return
        }
        let prev = Dictionary(uniqueKeysWithValues: saved.tunnels.map { ($0.name, $0) })
        entries = dbs.map { db in
            var e = DBEntry(name: db.name, isProd: db.isProd)
            if !db.isProd, let t = prev[db.name] { e.checked = true; e.dbUser = t.dbUser; e.portText = String(t.port) }
            return e
        }
        step = 2
    }

    func setChecked(_ id: String, _ on: Bool) {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[i].checked = on
        if on, entries[i].portText.isEmpty {
            let used = Set(entries.filter { $0.checked && $0.id != id }.compactMap { Int($0.portText) })
            entries[i].portText = String(TeleportConfig.nextFreePort(startingAt: TeleportConfig.basePort, used: used))
        }
    }

    func save() {
        var c = saved
        c.tunnels = checked.map { TeleportTunnel(name: $0.name, dbUser: $0.dbUser.trimmed, port: Int($0.portText) ?? 0) }
        do {
            try c.save()
            tp.setupFinished(c)
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
                    Text(m.step == 1 ? "1/2  계정" : "2/2  DB 선택")
                        .font(.system(size: 12 * scale, weight: .semibold)).foregroundStyle(.secondary)
                    if m.step == 1 { account } else { dbs }
                    if let e = m.error { Text(e).font(.system(size: 11 * scale)).foregroundStyle(.red).textSelection(.enabled) }
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
            field("프록시") { TextField("", text: $m.proxy) }
            field("사용자 ID") {
                VStack(alignment: .leading, spacing: 2) {
                    TextField("Teleport 계정 (DB 사용자 developer 아님)", text: $m.user)
                    if let u = TOTP.accountUser(in: m.otpKey), u != m.user.trimmingCharacters(in: .whitespaces) {
                        Text("OTP 키의 계정은 \(u) 이에요").font(.system(size: 10.5 * scale)).foregroundStyle(.orange)
                    }
                }
            }
            field("비밀번호") { SecureField("", text: $m.password) }
            field("OTP 키") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("base32 키 또는 otpauth:// URL", text: $m.otpKey)
                        .onChange(of: m.otpKey) { _, k in
                            if m.user.trimmingCharacters(in: .whitespaces).isEmpty, let u = TOTP.accountUser(in: k) { m.user = u }
                        }
                    HStack {
                        Button("QR 이미지로 읽기") { m.readQR() }.controlSize(.small)
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
            Text("비밀번호와 OTP 키는 키체인에만 저장돼요. 다음을 누르면 실제로 로그인해 확인합니다.")
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
                    if e.isProd { Text("운영").font(.system(size: 10.5 * scale, weight: .semibold)).foregroundStyle(.red) }
                    Spacer()
                    if e.checked, let i = m.entries.firstIndex(where: { $0.id == e.id }) {
                        TextField("DB 사용자", text: $m.entries[i].dbUser).frame(width: 90)
                        TextField("포트", text: $m.entries[i].portText).frame(width: 60)
                            .foregroundStyle(dup.contains(Int(e.portText) ?? -1) ? Color.red : Color.primary)
                    }
                }
            }
        }
        .textFieldStyle(.roundedBorder)
    }
}
