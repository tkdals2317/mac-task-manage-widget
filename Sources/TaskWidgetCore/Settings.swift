import Foundation

public enum SettingsKey {
    public static let opacity = "opacity"
    public static let hoverOpaque = "hoverOpaque"
    public static let theme = "theme"
    public static let themePreset = "themePreset"
    public static let customBackground = "customBackground"
    public static let customAccent = "customAccent"
    public static let fontScale = "fontScale"
    public static let alwaysOnTop = "alwaysOnTop"
    public static let allSpaces = "allSpaces"
    public static let jiraBaseURL = "jiraBaseURL"
    public static let jiraEmail = "jiraEmail"
    public static let jiraRefreshMinutes = "jiraRefreshMinutes"
    public static let jiraJQL = "jiraJQL"
    public static let summaryHour = "summaryHour"
    public static let summaryMinute = "summaryMinute"
    public static let summaryNotify = "summaryNotify"
    public static let summaryInstructions = "summaryInstructions"
    public static let claudeModel = "claudeModel"
    public static let claudePath = "claudePath"
    public static let tshPath = "tshPath"
    public static let teleportAutoConnect = "teleportAutoConnect"
    public static let teleportWanted = "teleportWanted"
    public static let teleportCheckSeconds = "teleportCheckSeconds"
    public static let lastTab = "lastTab"
    public static let enabledTabs = "enabledTabs"
    public static let todoSectionCollapsed = "todoSectionCollapsed"
    public static let jiraSectionCollapsed = "jiraSectionCollapsed"
    public static let jiraVersionFilter = "jiraVersionFilter"
    public static let jiraGroupByVersion = "jiraGroupByVersion"
    public static let sortTodosByTag = "sortTodosByTag"
    public static let globalHotKeyEnabled = "globalHotKeyEnabled"
    public static let globalHotKey = "globalHotKey"
    public static let secretStorage = "secretStorage"
    public static let notesTabIntroduced = "notesTabIntroduced"
    public static let notesMemoCollapsed = "notesMemoCollapsed"
    public static let notesLinkCollapsed = "notesLinkCollapsed"
    public static let notesLinkFilter = "notesLinkFilter"
    public static let confluenceBaseURL = "confluenceBaseURL"
    public static let notesTouchID = "notesTouchID"
    public static let onboardingDone = "onboardingDone"
    public static let prTabIntroduced = "prTabIntroduced"
    public static let prGitHubEnabled = "prGitHubEnabled"
    public static let prBitbucketEnabled = "prBitbucketEnabled"
    public static let prBitbucketEmail = "prBitbucketEmail"
    public static let prBitbucketWorkspace = "prBitbucketWorkspace"
    public static let prBitbucketRepos = "prBitbucketRepos"
    public static let prHiddenRepos = "prHiddenRepos"
    public static let prCloneRoots = "prCloneRoots"
    public static let prStaleDays = "prStaleDays"
    public static let prHideDrafts = "prHideDrafts"
    public static let prRefreshMinutes = "prRefreshMinutes"
    public static let prNotifyNewReview = "prNotifyNewReview"
    public static let prNotifyApproved = "prNotifyApproved"
    public static let prNotifyChanges = "prNotifyChanges"
    public static let prNotifyComments = "prNotifyComments"
    public static let prBitbucketNoWrite = "prBitbucketNoWrite"
    public static let prSeenIDs = "prSeenIDs"
    public static let prLastSnapshot = "prLastSnapshot"
    public static let prFilter = "prFilter"
    public static let prReviewCollapsed = "prReviewCollapsed"
    public static let prMineCollapsed = "prMineCollapsed"
}

public final class Settings {
    public static let shared = Settings()
    public static let defaultJiraBaseURL = ""
    public static let defaultConfluenceBaseURL = ""

    private let d: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.d = defaults
    }

    private func double(_ k: String, _ def: Double) -> Double { d.object(forKey: k) as? Double ?? def }
    private func bool(_ k: String, _ def: Bool) -> Bool { d.object(forKey: k) as? Bool ?? def }
    private func int(_ k: String, _ def: Int) -> Int { d.object(forKey: k) as? Int ?? def }
    private func string(_ k: String, _ def: String) -> String { d.string(forKey: k) ?? def }

    public var opacity: Double {
        get { double(SettingsKey.opacity, 1.0) }
        set { d.set(newValue, forKey: SettingsKey.opacity) }
    }
    public var hoverOpaque: Bool {
        get { bool(SettingsKey.hoverOpaque, true) }
        set { d.set(newValue, forKey: SettingsKey.hoverOpaque) }
    }
    public var theme: String {
        get { string(SettingsKey.theme, "system") }
        set { d.set(newValue, forKey: SettingsKey.theme) }
    }
    public var themePreset: String {
        get { string(SettingsKey.themePreset, "default") }
        set { d.set(newValue, forKey: SettingsKey.themePreset) }
    }
    public var customBackground: String {
        get { string(SettingsKey.customBackground, ThemePalette.defaultBackground) }
        set { d.set(newValue, forKey: SettingsKey.customBackground) }
    }
    public var customAccent: String {
        get { string(SettingsKey.customAccent, ThemePalette.defaultAccent) }
        set { d.set(newValue, forKey: SettingsKey.customAccent) }
    }
    /// 패널에 적용할 색. nil = 기본(시스템 동작).
    public var themeColors: ThemeColors? {
        ThemePalette.resolve(id: themePreset, customBackground: customBackground, customAccent: customAccent)
    }
    public var fontScale: Double {
        get { double(SettingsKey.fontScale, 1.0) }
        set { d.set(newValue, forKey: SettingsKey.fontScale) }
    }
    public var alwaysOnTop: Bool {
        get { bool(SettingsKey.alwaysOnTop, true) }
        set { d.set(newValue, forKey: SettingsKey.alwaysOnTop) }
    }
    public var allSpaces: Bool {
        get { bool(SettingsKey.allSpaces, true) }
        set { d.set(newValue, forKey: SettingsKey.allSpaces) }
    }
    public var globalHotKeyEnabled: Bool {
        get { bool(SettingsKey.globalHotKeyEnabled, true) }
        set { d.set(newValue, forKey: SettingsKey.globalHotKeyEnabled) }
    }
    /// 저장값이 없거나 깨졌거나 유효하지 않으면 기본값.
    public var globalHotKey: HotKeySpec {
        get {
            guard let data = d.data(forKey: SettingsKey.globalHotKey),
                  let s = try? JSONDecoder().decode(HotKeySpec.self, from: data), s.isValid else { return .default }
            return s
        }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: SettingsKey.globalHotKey) }
    }
    public var jiraBaseURL: String {
        get { string(SettingsKey.jiraBaseURL, Self.defaultJiraBaseURL) }
        set { d.set(newValue, forKey: SettingsKey.jiraBaseURL) }
    }
    public var jiraEmail: String {
        get { string(SettingsKey.jiraEmail, "") }
        set { d.set(newValue, forKey: SettingsKey.jiraEmail) }
    }
    public var jiraRefreshMinutes: Int {
        get { int(SettingsKey.jiraRefreshMinutes, 5) }
        set { d.set(newValue, forKey: SettingsKey.jiraRefreshMinutes) }
    }
    public var jiraJQL: String {
        get { string(SettingsKey.jiraJQL, "") }
        set { d.set(newValue, forKey: SettingsKey.jiraJQL) }
    }
    public var summaryHour: Int {
        get { int(SettingsKey.summaryHour, 18) }
        set { d.set(newValue, forKey: SettingsKey.summaryHour) }
    }
    public var summaryMinute: Int {
        get { int(SettingsKey.summaryMinute, 0) }
        set { d.set(newValue, forKey: SettingsKey.summaryMinute) }
    }
    public var summaryNotify: Bool {
        get { bool(SettingsKey.summaryNotify, true) }
        set { d.set(newValue, forKey: SettingsKey.summaryNotify) }
    }
    /// "" = 기본 지시문 사용
    public var summaryInstructions: String {
        get { string(SettingsKey.summaryInstructions, "") }
        set { d.set(newValue, forKey: SettingsKey.summaryInstructions) }
    }
    public var claudeModel: String {
        get { string(SettingsKey.claudeModel, "") }
        set { d.set(newValue, forKey: SettingsKey.claudeModel) }
    }
    public var claudePath: String {
        get { string(SettingsKey.claudePath, "") }
        set { d.set(newValue, forKey: SettingsKey.claudePath) }
    }
    public var tshPath: String {
        get { string(SettingsKey.tshPath, "") }
        set { d.set(newValue, forKey: SettingsKey.tshPath) }
    }
    public var lastTab: String {
        get { string(SettingsKey.lastTab, "tasks") }
        set { d.set(newValue, forKey: SettingsKey.lastTab) }
    }
    public var jiraVersionFilter: String {
        get { string(SettingsKey.jiraVersionFilter, "") }
        set { d.set(newValue, forKey: SettingsKey.jiraVersionFilter) }
    }
    public var jiraGroupByVersion: Bool {
        get { bool(SettingsKey.jiraGroupByVersion, false) }
        set { d.set(newValue, forKey: SettingsKey.jiraGroupByVersion) }
    }
    public var sortTodosByTag: Bool {
        get { bool(SettingsKey.sortTodosByTag, true) }
        set { d.set(newValue, forKey: SettingsKey.sortTodosByTag) }
    }
    public var teleportAutoConnect: Bool {
        get { bool(SettingsKey.teleportAutoConnect, true) }
        set { d.set(newValue, forKey: SettingsKey.teleportAutoConnect) }
    }
    /// Teleport 터널 확인 주기(초). 30/60/120/300 중 하나, 기본 60.
    public var teleportCheckSeconds: Int {
        get { let v = int(SettingsKey.teleportCheckSeconds, 60); return [30, 60, 120, 300].contains(v) ? v : 60 }
        set { d.set(newValue, forKey: SettingsKey.teleportCheckSeconds) }
    }
    /// "keychain" (기본) | "file"
    public var secretStorage: String {
        get { string(SettingsKey.secretStorage, "keychain") }
        set { d.set(newValue, forKey: SettingsKey.secretStorage) }
    }
    /// 비면 노트 탭의 Confluence 부분을 숨긴다.
    public var confluenceBaseURL: String {
        get { string(SettingsKey.confluenceBaseURL, Self.defaultConfluenceBaseURL) }
        set { d.set(newValue, forKey: SettingsKey.confluenceBaseURL) }
    }
    /// 설정 도우미를 끝냈거나 건너뛴 적이 있는지 (기존 사용자는 첫 실행 때 조용히 true).
    public var onboardingDone: Bool {
        get { bool(SettingsKey.onboardingDone, false) }
        set { d.set(newValue, forKey: SettingsKey.onboardingDone) }
    }
    public var enabledTabs: String {
        get { string(SettingsKey.enabledTabs, "tasks,summary") }
        set { d.set(newValue, forKey: SettingsKey.enabledTabs) }
    }

    // MARK: - PR 탭
    public var prGitHubEnabled: Bool {
        get { bool(SettingsKey.prGitHubEnabled, false) }
        set { d.set(newValue, forKey: SettingsKey.prGitHubEnabled) }
    }
    public var prBitbucketEnabled: Bool {
        get { bool(SettingsKey.prBitbucketEnabled, false) }
        set { d.set(newValue, forKey: SettingsKey.prBitbucketEnabled) }
    }
    public var prBitbucketEmail: String {
        get { string(SettingsKey.prBitbucketEmail, "") }
        set { d.set(newValue, forKey: SettingsKey.prBitbucketEmail) }
    }
    public var prBitbucketWorkspace: String {
        get { string(SettingsKey.prBitbucketWorkspace, "") }
        set { d.set(newValue, forKey: SettingsKey.prBitbucketWorkspace) }
    }
    /// 쉼표로 구분한 slug 목록
    public var prBitbucketRepos: String {
        get { string(SettingsKey.prBitbucketRepos, "") }
        set { d.set(newValue, forKey: SettingsKey.prBitbucketRepos) }
    }
    public var prHiddenRepos: String {
        get { string(SettingsKey.prHiddenRepos, "") }
        set { d.set(newValue, forKey: SettingsKey.prHiddenRepos) }
    }
    public var prStaleDays: Int {
        get { int(SettingsKey.prStaleDays, 2) }
        set { d.set(newValue, forKey: SettingsKey.prStaleDays) }
    }
    public var prHideDrafts: Bool {
        get { bool(SettingsKey.prHideDrafts, false) }
        set { d.set(newValue, forKey: SettingsKey.prHideDrafts) }
    }
    public var prRefreshMinutes: Int {
        get { max(1, int(SettingsKey.prRefreshMinutes, 5)) }
        set { d.set(newValue, forKey: SettingsKey.prRefreshMinutes) }
    }
    public var prNotifyNewReview: Bool {
        get { bool(SettingsKey.prNotifyNewReview, true) }
        set { d.set(newValue, forKey: SettingsKey.prNotifyNewReview) }
    }
    public var prNotifyApproved: Bool {
        get { bool(SettingsKey.prNotifyApproved, true) }
        set { d.set(newValue, forKey: SettingsKey.prNotifyApproved) }
    }
    public var prNotifyChanges: Bool {
        get { bool(SettingsKey.prNotifyChanges, true) }
        set { d.set(newValue, forKey: SettingsKey.prNotifyChanges) }
    }
    public var prNotifyComments: Bool {
        get { bool(SettingsKey.prNotifyComments, true) }
        set { d.set(newValue, forKey: SettingsKey.prNotifyComments) }
    }
    public var prBitbucketRepoList: [String] {
        get { Self.csv(prBitbucketRepos) }
        set { prBitbucketRepos = Self.joinCSV(newValue) }
    }
    /// 숨긴 저장소 키("provider:owner/slug") 목록. JSON 배열 문자열로 저장한다.
    public var prHiddenRepoList: [String] {
        get { Self.decodeList(prHiddenRepos) }
        set { prHiddenRepos = Self.encodeList(newValue) }
    }

    /// Bitbucket 클론을 찾을 폴더(절대 경로). 한 번도 안 고쳤으면 있는 기본 폴더를 보여주고, 고친 뒤에는 저장된 목록 그대로(비어도 됨).
    public var prCloneRootList: [String] {
        get {
            if let raw = d.string(forKey: SettingsKey.prCloneRoots) { return Self.decodeList(raw) }
            return LocalRepos.uniqueDirs(LocalRepos.defaultRoots().map(\.path).filter { FileManager.default.fileExists(atPath: $0) })
        }
        set { d.set(Self.encodeList(LocalRepos.uniqueDirs(newValue)), forKey: SettingsKey.prCloneRoots) }
    }

    public static func decodeList(_ raw: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(raw.utf8))) ?? []
    }
    public static func encodeList(_ items: [String]) -> String {
        String(decoding: (try? JSONEncoder().encode(Array(Set(items)).sorted())) ?? Data("[]".utf8), as: UTF8.self)
    }

    public static func csv(_ raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    /// 중복 제거, 정렬해서 쉼표로.
    public static func joinCSV(_ items: [String]) -> String { Array(Set(items)).sorted().joined(separator: ",") }
}
