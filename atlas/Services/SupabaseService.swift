//
//  SupabaseService.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/16/25.
//

import Foundation
import Supabase
import Combine

final class SupabaseService: ObservableObject {
    static let shared = SupabaseService()

    let client: SupabaseClient

    @Published var currentUser: User?
    @Published var session: Session?
    @Published var isInitializing = true

    var currentUserId: UUID? {
        session?.user.id
    }

    private init() {
        // Supabase configuration
        let supabaseURL = URL(string: "https://sqchwnbwcnqegwtffxbz.supabase.co")!
        let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNxY2h3bmJ3Y25xZWd3dGZmeGJ6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjU4Njc5ODYsImV4cCI6MjA4MTQ0Mzk4Nn0.9z7Kz4FGh-ncfylV9vK-et_R444D-wEK7vaod5VJOl8"

        client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    // MARK: - Auth Listener

    /// Starts listening to auth state changes
    /// Should be called after UI is initialized to avoid race conditions
    func startAuthListener() {
        BackgroundTask { [weak self] in
            guard let self else { return }

            for await state in await self.client.auth.authStateChanges {
                let session = state.session
                await MainActor.run {
                    self.session = session
                    // Mark initialization as complete after first auth check
                    if self.isInitializing {
                        self.isInitializing = false
                    }
                }

                if let session {
                    await self.fetchUserProfile(userId: session.user.id)
                } else {
                    await MainActor.run {
                        self.currentUser = nil
                    }
                }
            }
        }
    }

    // MARK: - Authentication

    func signUp(email: String, password: String, fullName: String) async throws {
        // Pass full_name in user metadata - trigger will create profile automatically
        try await client.auth.signUp(
            email: email,
            password: password,
            data: ["full_name": .string(fullName)]
        )
    }

    func signIn(email: String, password: String) async throws {
        let response = try await client.auth.signIn(
            email: email,
            password: password
        )

        await fetchUserProfile(userId: response.user.id)
    }

    func signOut() async throws {
        try await client.auth.signOut()
        await MainActor.run {
            self.currentUser = nil
            self.session = nil
        }
    }

    // MARK: - User Profile

    private func fetchUserProfile(userId: UUID) async {
        do {
            let profile: Profile = try await client
                .from("profiles")
                .select()
                .eq("user_id", value: userId.uuidString)
                .single()
                .execute()
                .value

            await MainActor.run {
                self.currentUser = User(
                    id: userId,
                    email: session?.user.email ?? "",
                    fullName: profile.fullName,
                    createdAt: profile.createdAt
                )
            }
        } catch {
            print("Error fetching profile: \(error)")
        }
    }

    // MARK: - Check Auth State

    var isAuthenticated: Bool {
        session != nil
    }
}
