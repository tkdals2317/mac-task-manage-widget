import Foundation

public enum SettingsKey {
    public static let opacity = "opacity"
    public static let hoverOpaque = "hoverOpaque"
    public static let theme = "theme"
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
    public static let lastTab = "lastTab"
    public static let enabledTabs = "enabledTabs"
    public static let todoSectionCollapsed = "todoSectionCollapsed"
    public static let jiraSectionCollapsed = "jiraSectionCollapsed"
    public static let jiraVersionFilter = "jiraVersionFilter"
    public static let jiraGroupByVersion = "jiraGroupByVersion"
    public static let sortTodosByTag = "sortTodosByTag"
    public static let globalHotKeyEnabled = "globalHotKeyEnabled"
}

public final class Settings {
    public static let shared = Settings()
    public static let defaultJiraBaseURL = "https://midasitweb-jira.atlassian.net"

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
    public var enabledTabs: String {
        get { string(SettingsKey.enabledTabs, "tasks,summary") }
        set { d.set(newValue, forKey: SettingsKey.enabledTabs) }
    }
}
