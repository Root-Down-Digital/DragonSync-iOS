//
//  FAAService.swift
//  WarDragon
//
//  Created by Luke on 4/25/25.
//

import Foundation
import Combine

class FAAService: ObservableObject {
    static let shared = FAAService()
    
    @Published var isFetching = false
    @Published var error: String?
    
    private let faaBaseURL = "https://uasdoc.faa.gov"
    private let faaAPIEndpoint = "/api/v1/serialNumbers"
    
    // Create a session with custom headers
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:137.0) Gecko/20100101 Firefox/137.0",
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "en-US,en;q=0.5",
            "Referer": "https://uasdoc.faa.gov/listdocs",
            "client": "external"
        ]
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 30
        
        // Enable cookie handling
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        
        return URLSession(configuration: config)
    }()
    
    // Refresh the FAA cookie by visiting the homepage first
    private func refreshCookie() async throws {
        let homepageURL = URL(string: "\(faaBaseURL)/listdocs")!
        do {
            // Clear existing cookies first
            if let cookies = HTTPCookieStorage.shared.cookies(for: homepageURL) {
                for cookie in cookies {
                    HTTPCookieStorage.shared.deleteCookie(cookie)
                }
            }
            
            // Make request to homepage to get new cookie
            var request = URLRequest(url: homepageURL)
            request.httpMethod = "GET"
            
            let (_, response) = try await session.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                print("FAA homepage response code: \(httpResponse.statusCode)")
                
                // Log cookies for debugging
                if let cookies = HTTPCookieStorage.shared.cookies(for: homepageURL) {
                    print("Got \(cookies.count) cookies from FAA homepage")
                    for cookie in cookies {
                        print("Cookie: \(cookie.name) = \(cookie.value)")
                    }
                }
            }
        } catch {
            print("Error refreshing FAA cookie: \(error)")
            throw error
        }
    }
    
    func queryFAAData(mac: String, remoteId: String) async -> [String: Any]? {
        guard !remoteId.isEmpty else {
            await MainActor.run {
                self.error = "Remote ID is empty"
            }
            return nil
        }
        
        // Check cache first
        if let cachedData = checkCache(mac: mac, remoteId: remoteId) {
            print("FAA Cache Hit")
            return cachedData
        }
        
        await MainActor.run {
            self.isFetching = true
            self.error = nil
        }
        
        var retryCount = 0
        let maxRetries = 3
        
        while retryCount < maxRetries {
            do {
                // Refresh cookie before each attempt
                try await refreshCookie()
                
                // Small delay to ensure cookie is properly set
                try await Task.sleep(nanoseconds: 500_000_000)
                
                // Build the FAA query URL
                var components = URLComponents(string: "\(faaBaseURL)\(faaAPIEndpoint)")!
                components.queryItems = [
                    URLQueryItem(name: "itemsPerPage", value: "8"),
                    URLQueryItem(name: "pageIndex", value: "0"),
                    URLQueryItem(name: "orderBy[0]", value: "updatedAt"),
                    URLQueryItem(name: "orderBy[1]", value: "DESC"),
                    URLQueryItem(name: "findBy", value: "serialNumber"),
                    URLQueryItem(name: "serialNumber", value: remoteId)
                ]
                
                guard let url = components.url else {
                    throw NSError(domain: "FAAService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
                }
                
                print("FAA Request URL: \(url.absoluteString)")
                
                // Create request with proper headers
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                
                // Make the request
                let (data, response) = try await session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    print("FAA Response status: \(httpResponse.statusCode)")
                    
                    switch httpResponse.statusCode {
                    case 502:
                        // Handle 502 Proxy Error specifically
                        if retryCount < maxRetries - 1 {
                            retryCount += 1
                            print("502 Proxy Error, retrying in \(Double(retryCount) * 2) seconds...")
                            try await Task.sleep(nanoseconds: UInt64(Double(retryCount) * 2_000_000_000))
                            continue
                        } else {
                            throw NSError(domain: "FAAService",
                                          code: 502,
                                          userInfo: [NSLocalizedDescriptionKey: "The FAA service is temporarily unavailable (502 Proxy Error). Please try again later."])
                        }
                    case 200:
                        // Success
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            cacheResult(mac: mac, remoteId: remoteId, data: json)
                            await MainActor.run {
                                self.isFetching = false
                            }
                            return json
                        }
                    default:
                        // Other HTTP errors
                        throw NSError(domain: "FAAService",
                                      code: httpResponse.statusCode,
                                      userInfo: [NSLocalizedDescriptionKey: "FAA HTTP error: \(httpResponse.statusCode)"])
                    }
                }
                
            } catch {
                if retryCount < maxRetries - 1 {
                    retryCount += 1
                    print("Error on attempt \(retryCount): \(error.localizedDescription)")
                    try? await Task.sleep(nanoseconds: UInt64(Double(retryCount) * 2_000_000_000))
                    continue
                } else {
                    await MainActor.run {
                        self.isFetching = false
                        self.error = error.localizedDescription
                    }
                    return nil
                }
            }
        }
        
        await MainActor.run {
            self.isFetching = false
        }
        
        return nil
    }
    
    // Cache functions
    private func cacheResult(mac: String, remoteId: String, data: [String: Any]) {
        let key = "\(mac)_\(remoteId)"
        UserDefaults.standard.set(data, forKey: "faa_cache_\(key)")
    }
    
    private func checkCache(mac: String, remoteId: String) -> [String: Any]? {
        let key = "\(mac)_\(remoteId)"
        return UserDefaults.standard.dictionary(forKey: "faa_cache_\(key)")
    }
}
