//
//  StatCardView.swift
//  To do App
//
//  Created by Oleksandr Pushkarov on 12/15/25.
//

import SwiftUI

struct StatCardView: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(count)")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    HStack(spacing: 12) {
        StatCardView(title: "Total", count: 10, color: .blue)
        StatCardView(title: "Active", count: 5, color: .orange)
    }
    .padding()
}
