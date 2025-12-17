//
//  SplashView.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/16/25.
//

import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "target")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("Atlas")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                ProgressView()
                    .padding(.top, 20)
            }
        }
    }
}

#Preview {
    SplashView()
}
