//
//  DashboardView.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//

import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = TodoViewModel()
    @State private var showingAddTodo = false
    @State private var newTodoTitle = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statsSection
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                    filterSection
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    if viewModel.filteredTodos.isEmpty {
                        emptyStateView
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(viewModel.filteredTodos) { todo in
                            TodoRowView(todo: todo) {
                                viewModel.toggleComplete(todo)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    withAnimation {
                                        viewModel.deleteTodo(todo)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("My Tasks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddTodo = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAddTodo) {
                addTodoSheet
            }
        }
    }

    private var statsSection: some View {
        HStack(spacing: 12) {
            StatCardView(
                title: "Total",
                count: viewModel.totalCount,
                color: .blue
            )

            StatCardView(
                title: "Active",
                count: viewModel.activeCount,
                color: .orange
            )

            StatCardView(
                title: "Done",
                count: viewModel.completedCount,
                color: .green
            )
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var filterSection: some View {
        Picker("Filter", selection: $viewModel.filter) {
            Text("All").tag(TodoViewModel.TodoFilter.all)
            Text("Active").tag(TodoViewModel.TodoFilter.active)
            Text("Completed").tag(TodoViewModel.TodoFilter.completed)
        }
        .pickerStyle(.segmented)
        .onChange(of: viewModel.filter) { _ in
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: emptyStateIcon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(emptyStateText)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var emptyStateIcon: String {
        switch viewModel.filter {
        case .all:
            return "tray"
        case .active:
            return "checkmark.circle"
        case .completed:
            return "checkmark.circle.fill"
        }
    }

    private var emptyStateText: String {
        switch viewModel.filter {
        case .all:
            return "No tasks yet"
        case .active:
            return "No active tasks"
        case .completed:
            return "No completed tasks"
        }
    }

    private var addTodoSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Task title", text: $newTodoTitle, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button("Add Task") {
                        viewModel.addTodo(title: newTodoTitle)
                        newTodoTitle = ""
                        showingAddTodo = false
                    }
                    .disabled(newTodoTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newTodoTitle = ""
                        showingAddTodo = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    DashboardView()
}
