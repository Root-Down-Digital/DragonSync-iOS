//
//  OnboardingView.swift
//  WarDragon
//
//  Created on 5/7/26.
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var hasScrolledToBottom = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.15),
                    Color(red: 0.1, green: 0.1, blue: 0.2)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(.top, 40)
                    
                    Text("Welcome to WarDragon")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Drone Remote ID Detection")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.bottom, 30)
                
                // Scrollable disclaimer content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        disclaimerContent
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: ViewOffsetKey.self,
                                value: geo.frame(in: .named("scroll")).maxY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .frame(maxHeight: 400)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 20)
                .onPreferenceChange(ViewOffsetKey.self) { maxY in
                    if maxY <= 400 && !hasScrolledToBottom {
                        hasScrolledToBottom = true
                    }
                }
                
                Spacer().frame(height: 20)
                
                // Continue button
                Button {
                    UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding1")
                    isPresented = false
                } label: {
                    Text("Continue")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(hasScrolledToBottom ? Color.green : Color.gray)
                        .cornerRadius(16)
                }
                .disabled(!hasScrolledToBottom)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                
                if !hasScrolledToBottom {
                    Text("Scroll to the bottom to continue")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.bottom, 12)
                }
            }
        }
    }
}

struct ViewOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
    
    private var disclaimerContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // What This App Does
            DisclaimerSection(
                icon: "wave.3.right",
                iconColor: .blue,
                title: "What This App Does",
                content: """
                WarDragon receives and displays drone Remote ID broadcast data using open-source protocols. Remote ID is a public broadcast required by aviation authorities for drone identification and tracking.
                """
            )
            
            // Legal Compliance
            DisclaimerSection(
                icon: "checkmark.shield",
                iconColor: .green,
                title: "Legal Use",
                content: """
                Remote ID broadcasts are publicly transmitted signals designed to be received. You must comply with all local aviation, privacy, and telecommunications laws when using this app.
                """
            )
            
            // No Warranty
            DisclaimerSection(
                icon: "exclamationmark.triangle",
                iconColor: .orange,
                title: "No Warranty",
                content: """
                This app is provided "AS IS" without warranty. Detection accuracy is not guaranteed. Do not rely on this app for security, safety, or aviation decision-making.
                """
            )
            
            // Privacy & Data
            DisclaimerSection(
                icon: "lock.shield",
                iconColor: .purple,
                title: "Privacy & Data",
                content: """
                All detection data is stored locally on your device. You are responsible for securing collected data and complying with data protection laws in your jurisdiction.
                """
            )
            
            // User Responsibility
            DisclaimerSection(
                icon: "person.badge.shield.checkmark",
                iconColor: .cyan,
                title: "Your Responsibility",
                content: """
                By continuing, you confirm that you will use this app lawfully and ethically, understand its limitations, and accept full responsibility for your use of this application.
                """
            )
        }
    }


// Reusable disclaimer section component
struct DisclaimerSection: View {
    let icon: String
    let iconColor: Color
    let title: String
    let content: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(iconColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(content)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
                    .lineSpacing(4)
            }
        }
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
