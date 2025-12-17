//
//  AuthViewModel.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/16/25.
//

import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var currentUser: User?
    @Published var isInitializing = true

    private let supabase = SupabaseService.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Subscribe to auth changes
        supabase.$session
            .map { $0 != nil }
            .assign(to: \.isAuthenticated, on: self)
            .store(in: &cancellables)

        supabase.$currentUser
            .assign(to: \.currentUser, on: self)
            .store(in: &cancellables)

        supabase.$isInitializing
            .assign(to: \.isInitializing, on: self)
            .store(in: &cancellables)
    }

    func signUp(email: String, password: String, fullName: String) async {
        isLoading = true
        errorMessage = nil

        do {
            try await supabase.signUp(email: email, password: password, fullName: fullName)
            // Auto sign in after signup
            try await supabase.signIn(email: email, password: password)
        } catch {
            errorMessage = "Sign up error: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil

        do {
            try await supabase.signIn(email: email, password: password)
        } catch {
            errorMessage = "Invalid email or password"
        }

        isLoading = false
    }

    func signOut() async {
        do {
            try await supabase.signOut()
        } catch {
            errorMessage = "Sign out error: \(error.localizedDescription)"
        }
    }
}
