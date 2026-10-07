import Foundation

public enum TabConfig {
    /// 저장 문자열 → 켜진 탭 id 목록. `all` 순서를 따르고, 모르는 id·중복은 버리고, 비면 all 의 첫 번째.
    public static func enabled(from raw: String, all: [String]) -> [String] {
        let wanted = Set(raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let result = all.filter { wanted.contains($0) }
        return result.isEmpty ? Array(all.prefix(1)) : result
    }

    /// id 를 토글한 뒤 저장 문자열. 마지막 하나는 끌 수 없다(그대로 반환).
    public static func toggled(_ id: String, in raw: String, all: [String]) -> String {
        let cur = enabled(from: raw, all: all)
        guard all.contains(id) else { return raw }
        var next = Set(cur)
        if next.contains(id) {
            if cur.count == 1 { return raw }
            next.remove(id)
        } else {
            next.insert(id)
        }
        return all.filter { next.contains($0) }.joined(separator: ",")
    }
}
