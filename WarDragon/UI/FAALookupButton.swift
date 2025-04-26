//
//  FAALookupButton.swift
//  WarDragon
//
//  Created by Luke on 4/25/25.
//

import SwiftUI


struct FAALookupButton: View {
    let mac: String?
    let remoteId: String?
    @StateObject private var faaService = FAAService.shared
    @State private var showingFAAInfo = false
    @State private var showingError = false
    @State private var faaData: [String: Any]?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let mac = mac, let remoteId = remoteId {
                Button(action: {
                    isLoading = true
                    Task {
                        if let data = await faaService.queryFAAData(mac: mac, remoteId: remoteId) {
                            faaData = data
                            showingFAAInfo = true
                        } else if let error = faaService.error {
                            showingError = true
                        }
                        isLoading = false
                    }
                }) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "airplane.departure")
                        }
                        Text(isLoading ? "Loading..." : "FAA Lookup")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isLoading ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .disabled(faaService.isFetching || isLoading)
                .alert("FAA Lookup Error", isPresented: $showingError) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(faaService.error ?? "Unknown error occurred")
                }
            }
        }
        .sheet(isPresented: $showingFAAInfo) {
            if let data = faaData {
                ZStack {
                    Color.clear
                    VStack(spacing: 0) {
                        HStack {
                            Spacer()
                            Button("Done") {
                                showingFAAInfo = false
                            }
                            .padding(.trailing)
                            .padding(.top, 8)
                        }
                        .background(Color.clear)
                        
                        // FAA Info View
                        FAAInfoView(faaData: data)
                            .padding(.horizontal)
                    }
                }
                .background(Color.clear)
                .presentationDetents([.height(350)]) // TODO dont hardcode this 
                .presentationBackground(.clear)
                .presentationDragIndicator(.visible)
            }
        }
    }
}
