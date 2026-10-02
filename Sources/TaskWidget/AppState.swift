import SwiftUI
import TaskWidgetCore

@MainActor
final class AppState: ObservableObject {
    @Published var todos: [Todo]
    let todoStore: TodoStore

    init(todoStore: TodoStore = TodoStore()) {
        self.todoStore = todoStore
        self.todos = todoStore.load()
    }
}
