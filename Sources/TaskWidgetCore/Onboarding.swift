import Foundation

/// 설정 도우미(첫 실행 온보딩)의 순수 로직. UI 는 OnboardingView.
public enum Onboarding {
    /// 도우미를 띄울지. 이미 쓰던 흔적(할 일·Jira 이메일·Teleport·노트)이 있으면 업데이트로 들어온 기존 사용자이므로 띄우지 않는다.
    public static func shouldShow(done: Bool, todosExists: Bool, jiraEmail: String, teleportExists: Bool, notesExists: Bool) -> Bool {
        if done { return false }
        let usedBefore = todosExists || !jiraEmail.trimmingCharacters(in: .whitespaces).isEmpty || teleportExists || notesExists
        return !usedBefore
    }

    /// 입력한 주소 정리: 공백·끝 슬래시 제거, 스킴이 없으면 https://. 비면 그대로 비움.
    public static func normalizedURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        if !s.contains("://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// 고른 기능 → `enabledTabs` 저장 문자열 (할 일은 항상, 순서는 앱 탭 순서와 같다).
    public static func enabledTabs(summary: Bool, notes: Bool, teleport: Bool, pr: Bool = false) -> String {
        (["tasks"] + (summary ? ["summary"] : []) + (notes ? ["notes"] : []) + (pr ? ["pr"] : []) + (teleport ? ["teleport"] : [])).joined(separator: ",")
    }
}
