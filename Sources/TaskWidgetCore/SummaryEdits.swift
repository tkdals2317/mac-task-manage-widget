import Foundation

/// 직접 고친 요약 표시. 파일 안(front-matter)에 넣으면 프롬프트 입력·주간 합산에 섞이므로
/// 요약 파일 이름 → 수정 시각을 UserDefaults 에 따로 둔다.
public enum SummaryEdits {
    static let key = "summaryEditedAt"

    public static func editedAt(_ file: String, defaults: UserDefaults = .standard) -> Date? {
        (defaults.dictionary(forKey: key) as? [String: Date])?[file]
    }

    public static func mark(_ file: String, at date: Date = Date(), defaults: UserDefaults = .standard) {
        var d = (defaults.dictionary(forKey: key) as? [String: Date]) ?? [:]
        d[file] = date
        defaults.set(d, forKey: key)
    }

    public static func clear(_ file: String, defaults: UserDefaults = .standard) {
        var d = (defaults.dictionary(forKey: key) as? [String: Date]) ?? [:]
        guard d.removeValue(forKey: file) != nil else { return }
        defaults.set(d, forKey: key)
    }
}
