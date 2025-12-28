//
//  GoalsSupabaseService.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/26/25.
//  Supabase service for CRUD operations on goals, milestones, and tasks
//

import Foundation
import Supabase

final class GoalsSupabaseService {
    static let shared = GoalsSupabaseService()
    private let supabase = SupabaseService.shared.client

    private init() {}

    // MARK: - Goals

    func fetchGoals() async throws -> [Goal] {
        let response: [Goal] = try await supabase
            .from("goals")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
        return response
    }

    func createGoal(_ goal: Goal) async throws -> Goal {
        let response: Goal = try await supabase
            .from("goals")
            .insert(goal)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func updateGoal(_ goal: Goal) async throws {
        try await supabase
            .from("goals")
            .update(goal)
            .eq("id", value: goal.id.uuidString)
            .execute()
    }

    func deleteGoal(id: UUID) async throws {
        try await supabase
            .from("goals")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Milestones

    func fetchMilestones(goalId: UUID) async throws -> [Milestone] {
        let response: [Milestone] = try await supabase
            .from("milestones")
            .select()
            .eq("goal_id", value: goalId.uuidString)
            .order("order_index", ascending: true)
            .execute()
            .value
        return response
    }

    func createMilestone(_ milestone: Milestone) async throws -> Milestone {
        let response: Milestone = try await supabase
            .from("milestones")
            .insert(milestone)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func updateMilestone(_ milestone: Milestone) async throws {
        try await supabase
            .from("milestones")
            .update(milestone)
            .eq("id", value: milestone.id.uuidString)
            .execute()
    }

    func deleteMilestone(id: UUID) async throws {
        try await supabase
            .from("milestones")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Tasks

    func fetchTasks(milestoneId: UUID) async throws -> [Task] {
        let response: [Task] = try await supabase
            .from("tasks")
            .select()
            .eq("milestone_id", value: milestoneId.uuidString)
            .order("order_index", ascending: true)
            .execute()
            .value
        return response
    }

    func createTask(_ task: Task) async throws -> Task {
        let response: Task = try await supabase
            .from("tasks")
            .insert(task)
            .select()
            .single()
            .execute()
            .value
        return response
    }

    func updateTask(_ task: Task) async throws {
        try await supabase
            .from("tasks")
            .update(task)
            .eq("id", value: task.id.uuidString)
            .execute()
    }

    func deleteTask(id: UUID) async throws {
        try await supabase
            .from("tasks")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Composite Queries

    /// Fetches goal with all its milestones and tasks in a single operation
    func fetchGoalWithDetails(goalId: UUID) async throws -> (Goal, [Milestone], [Task]) {
        // Fetch goal
        let goal: Goal = try await supabase
            .from("goals")
            .select()
            .eq("id", value: goalId.uuidString)
            .single()
            .execute()
            .value

        // Fetch milestones for this goal
        let milestones = try await fetchMilestones(goalId: goalId)

        // Fetch all tasks for all milestones
        var allTasks: [Task] = []
        for milestone in milestones {
            let tasks = try await fetchTasks(milestoneId: milestone.id)
            allTasks.append(contentsOf: tasks)
        }

        return (goal, milestones, allTasks)
    }
}
