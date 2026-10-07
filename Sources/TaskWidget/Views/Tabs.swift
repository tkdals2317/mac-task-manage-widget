import SwiftUI

struct TabDef {
    let id: String
    let title: String
}

/// 탭 레지스트리. 새 탭은 여기 한 줄 + RootView.content(for:) 에 case 하나.
let allTabs: [TabDef] = [
    TabDef(id: "tasks", title: "할 일"),
    TabDef(id: "summary", title: "요약"),
]
