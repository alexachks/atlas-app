//
//  TodoViewModel.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//

import Foundation
import Combine

final class TodoViewModel: ObservableObject {
    @Published var todos: [TodoItem] = []
    @Published var filter: TodoFilter = .all

    enum TodoFilter {
        case all, active, completed
    }

    var filteredTodos: [TodoItem] {
        switch filter {
        case .all:
            return todos
        case .active:
            return todos.filter { !$0.isCompleted }
        case .completed:
            return todos.filter { $0.isCompleted }
        }
    }

    var totalCount: Int {
        todos.count
    }

    var completedCount: Int {
        todos.filter { $0.isCompleted }.count
    }

    var activeCount: Int {
        todos.filter { !$0.isCompleted }.count
    }

    init() {
        loadTodos()
    }

    func addTodo(title: String) {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let newTodo = TodoItem(title: title)
        todos.insert(newTodo, at: 0)
        saveTodos()
    }

    func toggleComplete(_ todo: TodoItem) {
        guard let index = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[index].isCompleted.toggle()
        saveTodos()
    }

    func deleteTodo(_ todo: TodoItem) {
        todos.removeAll { $0.id == todo.id }
        saveTodos()
    }

    func deleteTodos(at offsets: IndexSet) {
        let todosToDelete = offsets.map { filteredTodos[$0] }
        todos.removeAll { todo in
            todosToDelete.contains { $0.id == todo.id }
        }
        saveTodos()
    }

    private func saveTodos() {
        guard let encoded = try? JSONEncoder().encode(todos) else { return }
        UserDefaults.standard.set(encoded, forKey: "todos")
    }

    private func loadTodos() {
        guard let data = UserDefaults.standard.data(forKey: "todos"),
              let decoded = try? JSONDecoder().decode([TodoItem].self, from: data) else {
            return
        }
        todos = decoded
    }
}
