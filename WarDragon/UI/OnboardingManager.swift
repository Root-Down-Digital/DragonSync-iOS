//
//  OnboardingManager.swift
//  WarDragon
//
//  Created on 5/7/26.
//

import SwiftUI

/// Manager to control onboarding display from anywhere in the app
@MainActor
class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()
    
    @Published var shouldShowOnboarding = false
    
    private init() {}
    
    /// Shows the onboarding screen
    func showOnboarding() {
        shouldShowOnboarding = true
    }
    
    /// Dismisses the onboarding screen
    func dismissOnboarding() {
        shouldShowOnboarding = false
    }
    
    /// Check if user has completed onboarding
    static var HasCompletedOnboarding1: Bool {
        UserDefaults.standard.bool(forKey: "HasCompletedOnboarding1")
    }
    
    /// Reset onboarding status (for testing or user request)
    static func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: "HasCompletedOnboarding1")
    }
}

/// A button that can be added to settings to review disclaimers
struct ReviewDisclaimersButton: View {
    @StateObject private var onboardingManager = OnboardingManager.shared
    
    var body: some View {
        Button(action: {
            onboardingManager.showOnboarding()
        }) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.body)
                    .foregroundColor(.blue)
                
                Text("Review Legal Disclaimers")
                    .font(.appDefault)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $onboardingManager.shouldShowOnboarding) {
            OnboardingView(isPresented: $onboardingManager.shouldShowOnboarding)
        }
    }
}
// MARK: - Debug Helper
#if DEBUG
/// Debug button to reset onboarding status (only available in debug builds)
struct ResetOnboardingButton: View {
    @State private var showConfirmation = false
    
    var body: some View {
        Button(action: {
            showConfirmation = true
        }) {
            HStack {
                Image(systemName: "arrow.counterclockwise")
                    .font(.body)
                    .foregroundColor(.orange)
                
                Text("Reset Onboarding (Debug)")
                    .font(.appDefault)
                
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alert("Reset Onboarding?", isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                OnboardingManager.resetOnboarding()
            }
        } message: {
            Text("The onboarding screen will appear again on next launch.")
        }
    }
}
#endif

