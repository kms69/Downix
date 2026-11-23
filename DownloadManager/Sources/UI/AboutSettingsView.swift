//
//  AboutSettingsView.swift
//  Settings > About: version + "Check for Updates".
//

import SwiftUI
import AppKit

enum UpdateOutcome {
    case latest(version: String, page: URL)
    case none
    case failed(String)
}

enum UpdateChecker {
    static let repo = "kms69/Downex"

    /// Newest published release (or, when there are no releases, the newest tag).
    static func latest() async -> UpdateOutcome {
        for endpoint in ["releases/latest", "tags"] {
            guard let url = URL(string: "https://api.github.com/repos/\(repo)/\(endpoint)") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Downix", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await ProxySession.makeSession().data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }
                if http.statusCode == 404 { continue }
                guard http.statusCode == 200 else { return .failed("GitHub answered HTTP \(http.statusCode).") }
                let json = try JSONSerialization.jsonObject(with: data)
                if let o = json as? [String: Any], let tag = o["tag_name"] as? String {
                    let page = (o["html_url"] as? String).flatMap { URL(string: $0) }
                        ?? URL(string: "https://github.com/\(repo)/releases")!
                    return .latest(version: tag, page: page)
                }
                if let list = json as? [[String: Any]], let tag = list.first?["name"] as? String {
                    return .latest(version: tag, page: URL(string: "https://github.com/\(repo)/tags")!)
                }
            } catch {
                return .failed(error.localizedDescription)
            }
        }
        return .none
    }

    static func isNewer(_ remote: String, than local: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: ".")
                .map { Int($0.filter { $0.isNumber }) ?? 0 }
        }
        let a = parts(remote), b = parts(local)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

struct AboutSettingsView: View {
    @State private var checking = false
    @State private var status = ""
    @State private var pageURL: URL?

    private var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
    private var build: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 8)
            Image(nsImage: DownixLogo.mark)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 120, height: 104)
            Text("Downix Download Manager")
                .font(.title2.weight(.bold))
            Text("Version \(version) (build \(build))")
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    check()
                } label: {
                    if checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(checking)

                if let pageURL {
                    Button("Open Download Page") { NSWorkspace.shared.open(pageURL) }
                }
            }
            .padding(.top, 4)

            if !status.isEmpty {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            Spacer()
            Link("github.com/\(UpdateChecker.repo)",
                 destination: URL(string: "https://github.com/\(UpdateChecker.repo)")!)
                .font(.caption)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func check() {
        checking = true
        status = ""
        pageURL = nil
        Task {
            let outcome = await UpdateChecker.latest()
            await MainActor.run {
                checking = false
                switch outcome {
                case .latest(let remote, let page):
                    if UpdateChecker.isNewer(remote, than: version) {
                        status = "A new version is available: \(remote). You have \(version)."
                        pageURL = page
                    } else {
                        status = "You're up to date (version \(version))."
                    }
                case .none:
                    status = "No published releases were found, so there is nothing newer to install."
                case .failed(let message):
                    status = "Couldn't check for updates: \(message)"
                }
            }
        }
    }
}
