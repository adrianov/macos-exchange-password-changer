import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Asks Mail to store a new password on the Exchange account that is already set up.
@main
struct ExchangePasswordApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        if CommandLine.arguments.contains("--self-test") {
            SelfTest.run()
            exit(SelfTest.failed ? 1 : 0)
        }
    }

    var body: some Scene {
        WindowGroup {
            PasswordScreen()
        }
        .defaultSize(width: 480, height: 460)
        .windowResizability(.contentSize)
    }
}

struct PasswordScreen: View {
    @State private var accounts: [ExchangeAccount] = []
    @State private var selectedID = ""
    @State private var password = ""
    @State private var repeated = ""
    @State private var status = ""
    @State private var failed = false
    @State private var working = false
    @State private var loadError = ""

    private var selected: ExchangeAccount? {
        accounts.first { $0.id == selectedID }
    }

    private var canUpdate: Bool {
        selected != nil && !password.isEmpty && password == repeated && !working
    }

    var body: some View {
        Form {
            Section {
                Text("Mail’s password window cannot save a new password into an Exchange account that is already on this Mac. Enter the password you set with your company. This stores it on that same account.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                if accounts.isEmpty {
                    Text(loadError.isEmpty ? "Looking for Exchange accounts…" : loadError)
                } else {
                    Picker("Account", selection: $selectedID) {
                        ForEach(accounts) { account in
                            Text(account.host.isEmpty
                                ? "\(account.name) — \(account.username)"
                                : "\(account.name) — \(account.username) — \(account.host)"
                            ).tag(account.id)
                        }
                    }
                }
                SecureField("New password", text: $password)
                SecureField("Repeat password", text: $repeated)
            }

            Section {
                Button(working ? "Updating…" : "Update password") { update() }
                    .disabled(!canUpdate)
                if !status.isEmpty {
                    Text(status)
                        .foregroundStyle(failed ? .red : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !password.isEmpty && password != repeated {
                    Text("The two passwords differ.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 480)
        .task { load() }
    }

    private func load() {
        do {
            accounts = try AccountStore.exchangeAccounts()
            selectedID = accounts.first?.id ?? ""
            if accounts.isEmpty {
                loadError = "Mail has no Exchange account."
            }
        } catch let UpdateError.message(text) {
            loadError = text
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func update() {
        guard let account = selected else { return }
        let newPassword = password
        working = true
        failed = false
        status = "Updating the existing Exchange account…"
        Task { @MainActor in
            do {
                status = try await MailPassword.update(account, password: newPassword)
                password = ""
                repeated = ""
            } catch let UpdateError.message(text) {
                failed = true
                status = text.replacingOccurrences(of: newPassword, with: "••••")
            } catch {
                failed = true
                status = error.localizedDescription.replacingOccurrences(of: newPassword, with: "••••")
            }
            working = false
        }
    }
}

enum SelfTest {
    static var failed = false

    static func run() {
        check(appleQuote("a\"b") == "\"a\"\"b\"", "quote")
        let parsed = accounts(from: "abc\tMail\tuser\tautodiscover.example\n\t\t\n")
        check(parsed.count == 1 && parsed[0].username == "user" && parsed[0].host == "autodiscover.example", "parse")
        do {
            let accounts = try AccountStore.exchangeAccounts()
            check(!accounts.isEmpty, "accounts")
            check(accounts.allSatisfy { !$0.username.isEmpty && !$0.id.isEmpty }, "fields")
        } catch {
            check(false, "load")
        }
    }

    private static func check(_ condition: Bool, _ name: String) {
        if condition {
            print("ok \(name)")
        } else {
            failed = true
            print("fail \(name)")
        }
    }
}
