//
//  LoginView.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/16/25.
//

import SwiftUI

struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var email = ""
    @State private var password = ""
    @State private var showingSignUp = false
    @FocusState private var focusedField: Field?

    enum Field {
        case email, password
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "target")
                            .font(.system(size: 80))
                            .foregroundStyle(Theme.primaryGradient)
                            .padding(.top, 60)

                        Text("Atlas")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Achieve goals step by step")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 40)

                    // Form
                    VStack(spacing: 16) {
                        // Email
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            TextField("john@example.com", text: $email)
                                .textContentType(.emailAddress)
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                                .focused($focusedField, equals: .email)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }

                        // Password
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)

                            SecureField("Enter password", text: $password)
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(12)
                        }

                        if let error = authViewModel.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal)

                    // Login Button
                    Button {
                        BackgroundTask { @MainActor in
                            await authViewModel.signIn(email: email, password: password)
                        }
                    } label: {
                        if authViewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Sign In")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(isFormValid ? Theme.primaryGradient : LinearGradient(colors: [.gray], startPoint: .leading, endPoint: .trailing))
                    .foregroundStyle(.white)
                    .cornerRadius(12)
                    .disabled(!isFormValid || authViewModel.isLoading)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Sign Up Link
                    Button {
                        showingSignUp = true
                    } label: {
                        HStack(spacing: 4) {
                            Text("Don't have an account?")
                                .foregroundStyle(.secondary)
                            Text("Sign Up")
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.primaryBlue)
                        }
                        .font(.subheadline)
                    }
                    .padding(.top, 8)

                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingSignUp) {
                SignUpView(authViewModel: authViewModel)
            }
        }
    }

    private var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty &&
        email.contains("@")
    }
}

#Preview {
    LoginView(authViewModel: AuthViewModel())
}
