//
//  GoalViewModel.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//  Refactored on 12/26/25 for Supabase and flat structure
//

import Foundation
import Combine

final class GoalViewModel: ObservableObject {
    // Flat structure: separate arrays for goals, milestones, tasks
    @Published var goals: [Goal] = []
    @Published var milestonesByGoal: [UUID: [Milestone]] = [:]
    @Published var tasksByMilestone: [UUID: [Task]] = [:]

    init() {
        BackgroundTask {
            await migrateIfNeeded()
            await loadGoals()
        }
    }

    // MARK: - Migration from UserDefaults to Supabase

    private func migrateIfNeeded() async {
        // Проверяем флаг миграции
        guard !UserDefaults.standard.bool(forKey: "goals_migrated_to_supabase") else {
            print("✅ Goals already migrated to Supabase")
            return
        }

        // Загружаем старые цели из UserDefaults
        guard let data = UserDefaults.standard.data(forKey: "goals") else {
            print("ℹ️ No old goals to migrate")
            UserDefaults.standard.set(true, forKey: "goals_migrated_to_supabase")
            return
        }

        // Пытаемся декодировать старые данные (nested structure)
        let decoder = JSONDecoder()
        guard let oldGoals = try? decoder.decode([OldGoal].self, from: data) else {
            print("ℹ️ Failed to decode old goals format")
            UserDefaults.standard.set(true, forKey: "goals_migrated_to_supabase")
            return
        }

        print("🔄 Migrating \(oldGoals.count) goals to Supabase...")

        guard let userId = SupabaseService.shared.currentUserId else {
            print("❌ No user logged in, skipping migration")
            return
        }

        do {
            for oldGoal in oldGoals {
                // 1. Создать или получить Goal
                var goalToUse: Goal
                do {
                    let newGoal = Goal(
                        id: oldGoal.id,
                        userId: userId,
                        title: oldGoal.title,
                        description: oldGoal.description,
                        deadline: oldGoal.deadline,
                        createdAt: oldGoal.createdAt
                    )
                    goalToUse = try await GoalsSupabaseService.shared.createGoal(newGoal)
                } catch {
                    // Если цель уже существует, пропускаем её полностью
                    let errorString = error.localizedDescription
                    if errorString.contains("23505") {
                        print("⏭️ Goal \(oldGoal.title) already exists, skipping entire goal migration")
                        continue
                    } else {
                        throw error
                    }
                }

                // 2. Создать Milestones (ранее Topics)
                for (index, oldTopic) in oldGoal.topics.enumerated() {
                    do {
                        let milestone = Milestone(
                            id: oldTopic.id,
                            goalId: goalToUse.id,
                            title: oldTopic.title,
                            description: oldTopic.description,
                            orderIndex: index,
                            createdAt: oldTopic.createdAt
                        )
                        let createdMilestone = try await GoalsSupabaseService.shared.createMilestone(milestone)

                        // 3. Создать Tasks
                        for (taskIndex, oldTask) in oldTopic.tasks.enumerated() {
                            do {
                                let task = Task(
                                    id: oldTask.id,
                                    milestoneId: createdMilestone.id,
                                    title: oldTask.title,
                                    description: oldTask.description,
                                    isCompleted: oldTask.isCompleted,
                                    dependsOn: oldTask.dependsOn,
                                    orderIndex: taskIndex,
                                    deadline: oldTask.deadline,
                                    estimatedMinutes: oldTask.estimatedMinutes,
                                    completedAt: oldTask.isCompleted ? Date() : nil,
                                    createdAt: oldTask.createdAt
                                )
                                _ = try await GoalsSupabaseService.shared.createTask(task)
                            } catch {
                                // Пропускаем дубликаты задач
                                let errorString = error.localizedDescription
                                if errorString.contains("23505") {
                                    print("⏭️ Task \(oldTask.title) already exists, skipping")
                                } else {
                                    throw error
                                }
                            }
                        }
                    } catch {
                        // Пропускаем дубликаты milestone
                        let errorString = error.localizedDescription
                        if errorString.contains("23505") {
                            print("⏭️ Milestone \(oldTopic.title) already exists, skipping")
                        } else {
                            throw error
                        }
                    }
                }
            }

            // Пометить миграцию завершенной
            UserDefaults.standard.set(true, forKey: "goals_migrated_to_supabase")
            print("✅ Migration completed successfully")

        } catch {
            print("❌ Migration failed: \(error)")
            // Пометить миграцию завершенной даже при ошибке, чтобы не повторять бесконечно
            UserDefaults.standard.set(true, forKey: "goals_migrated_to_supabase")
        }
    }

    // MARK: - Loading

    func loadGoals() async {
        do {
            let fetchedGoals = try await GoalsSupabaseService.shared.fetchGoals()

            await MainActor.run {
                self.goals = fetchedGoals
            }

            // Загрузить milestones и tasks для каждой цели
            for goal in fetchedGoals {
                await loadMilestones(for: goal.id)
            }
        } catch {
            print("❌ Failed to load goals: \(error)")
        }
    }

    func loadMilestones(for goalId: UUID) async {
        do {
            let milestones = try await GoalsSupabaseService.shared.fetchMilestones(goalId: goalId)

            await MainActor.run {
                self.milestonesByGoal[goalId] = milestones
            }

            // Загрузить tasks для каждого milestone
            for milestone in milestones {
                await loadTasks(for: milestone.id)
            }
        } catch {
            print("❌ Failed to load milestones: \(error)")
        }
    }

    func loadTasks(for milestoneId: UUID) async {
        do {
            let tasks = try await GoalsSupabaseService.shared.fetchTasks(milestoneId: milestoneId)

            await MainActor.run {
                self.tasksByMilestone[milestoneId] = tasks
            }
        } catch {
            print("❌ Failed to load tasks: \(error)")
        }
    }

    // MARK: - Goal CRUD

    func addGoal(title: String, description: String? = nil, deadline: Date? = nil) async -> Goal? {
        guard let userId = SupabaseService.shared.currentUserId else {
            print("❌ No user logged in")
            return nil
        }

        let newGoal = Goal(
            userId: userId,
            title: title,
            description: description,
            deadline: deadline
        )

        do {
            let created = try await GoalsSupabaseService.shared.createGoal(newGoal)
            await MainActor.run {
                self.goals.insert(created, at: 0)
            }
            return created
        } catch {
            print("❌ Failed to create goal: \(error)")
            return nil
        }
    }

    func updateGoal(_ goal: Goal) async {
        do {
            try await GoalsSupabaseService.shared.updateGoal(goal)
            await loadGoals()
        } catch {
            print("❌ Failed to update goal: \(error)")
        }
    }

    func deleteGoal(_ goal: Goal) async {
        do {
            try await GoalsSupabaseService.shared.deleteGoal(id: goal.id)
            await MainActor.run {
                self.goals.removeAll { $0.id == goal.id }
                self.milestonesByGoal.removeValue(forKey: goal.id)
            }
        } catch {
            print("❌ Failed to delete goal: \(error)")
        }
    }

    func updateGoalDescription(goalId: UUID, description: String) async {
        guard let goalIndex = goals.firstIndex(where: { $0.id == goalId }) else { return }

        var goal = goals[goalIndex]
        goal.description = description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description
        await updateGoal(goal)
    }

    func updateGoalDeadline(goalId: UUID, deadline: Date) async {
        guard let goalIndex = goals.firstIndex(where: { $0.id == goalId }) else { return }

        var goal = goals[goalIndex]
        goal.deadline = deadline
        await updateGoal(goal)
    }

    // MARK: - Milestone CRUD (ранее Topic)

    func addMilestone(to goalId: UUID, title: String, description: String = "") async -> Milestone? {
        let currentMilestones = milestonesByGoal[goalId] ?? []
        let orderIndex = currentMilestones.count

        let milestone = Milestone(
            goalId: goalId,
            title: title,
            description: description,
            orderIndex: orderIndex
        )

        do {
            let created = try await GoalsSupabaseService.shared.createMilestone(milestone)
            await MainActor.run {
                if self.milestonesByGoal[goalId] != nil {
                    self.milestonesByGoal[goalId]?.append(created)
                } else {
                    self.milestonesByGoal[goalId] = [created]
                }
            }
            return created
        } catch {
            print("❌ Failed to create milestone: \(error)")
            return nil
        }
    }

    func updateMilestone(_ milestone: Milestone) async {
        do {
            try await GoalsSupabaseService.shared.updateMilestone(milestone)
            await loadMilestones(for: milestone.goalId)
        } catch {
            print("❌ Failed to update milestone: \(error)")
        }
    }

    func deleteMilestone(_ milestone: Milestone) async {
        do {
            try await GoalsSupabaseService.shared.deleteMilestone(id: milestone.id)
            await MainActor.run {
                self.milestonesByGoal[milestone.goalId]?.removeAll { $0.id == milestone.id }
                self.tasksByMilestone.removeValue(forKey: milestone.id)
            }
        } catch {
            print("❌ Failed to delete milestone: \(error)")
        }
    }

    // MARK: - Task CRUD

    func addTask(to milestoneId: UUID, title: String, description: String = "", dependsOn: [UUID] = []) async -> Task? {
        let currentTasks = tasksByMilestone[milestoneId] ?? []
        let orderIndex = currentTasks.count

        let task = Task(
            milestoneId: milestoneId,
            title: title,
            description: description,
            dependsOn: dependsOn,
            orderIndex: orderIndex
        )

        do {
            let created = try await GoalsSupabaseService.shared.createTask(task)
            await MainActor.run {
                if self.tasksByMilestone[milestoneId] != nil {
                    self.tasksByMilestone[milestoneId]?.append(created)
                } else {
                    self.tasksByMilestone[milestoneId] = [created]
                }
            }
            return created
        } catch {
            print("❌ Failed to create task: \(error)")
            return nil
        }
    }

    func toggleTask(_ task: Task) async {
        var updatedTask = task
        updatedTask.isCompleted.toggle()
        updatedTask.completedAt = updatedTask.isCompleted ? Date() : nil

        do {
            try await GoalsSupabaseService.shared.updateTask(updatedTask)

            await MainActor.run {
                if let index = self.tasksByMilestone[task.milestoneId]?.firstIndex(where: { $0.id == task.id }) {
                    self.tasksByMilestone[task.milestoneId]?[index] = updatedTask
                }
            }

            // ✅ НОВАЯ МЕХАНИКА: отправить карточку в чат
            if updatedTask.isCompleted {
                await sendTaskCompletionCard(task: updatedTask)
            }
        } catch {
            print("❌ Failed to toggle task: \(error)")
        }
    }

    func updateTask(_ task: Task) async {
        do {
            try await GoalsSupabaseService.shared.updateTask(task)
            await loadTasks(for: task.milestoneId)
        } catch {
            print("❌ Failed to update task: \(error)")
        }
    }

    func deleteTask(_ task: Task) async {
        do {
            try await GoalsSupabaseService.shared.deleteTask(id: task.id)
            await MainActor.run {
                self.tasksByMilestone[task.milestoneId]?.removeAll { $0.id == task.id }
            }
        } catch {
            print("❌ Failed to delete task: \(error)")
        }
    }

    // MARK: - Task Availability

    func isTaskAvailable(_ task: Task, in goalId: UUID) -> Bool {
        // Собираем все completed task IDs для этого goal
        guard let milestones = milestonesByGoal[goalId] else { return false }

        var completedTaskIds = Set<UUID>()
        for milestone in milestones {
            if let tasks = tasksByMilestone[milestone.id] {
                completedTaskIds.formUnion(tasks.filter { $0.isCompleted }.map { $0.id })
            }
        }

        return task.isAvailable(completedTaskIds: completedTaskIds)
    }

    // MARK: - Task Completion Card

    private func sendTaskCompletionCard(task: Task) async {
        // Форматируем дату
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale(identifier: "en_US")

        let completionMessage = """
        ✅ Task completed: \(task.title)
        Completion date: \(task.completedAt.map { dateFormatter.string(from: $0) } ?? "now")
        """

        print("📋 Sending task completion card to AI chat")

        // Отправить через AIService
        await AIService.shared.sendTaskCompletionNotification(message: completionMessage)
    }
}

// MARK: - Old Data Structures (для migration)

private struct OldGoal: Codable {
    let id: UUID
    var title: String
    var description: String?
    var deadline: Date?
    var topics: [OldTopic]
    var createdAt: Date
}

private struct OldTopic: Codable {
    let id: UUID
    var title: String
    var description: String
    var order: Int
    var tasks: [OldTask]
    var createdAt: Date
}

private struct OldTask: Codable {
    let id: UUID
    var title: String
    var description: String
    var isCompleted: Bool
    var dependsOn: [UUID]
    var order: Int
    var deadline: Date?
    var estimatedMinutes: Int?
    var createdAt: Date
}
