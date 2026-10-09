import AppKit
import Foundation

enum UpdateError: Error {
    case message(String)
}

/// Writes a new password into the Exchange account Mail already has.
enum MailPassword {
    @MainActor
    static func update(_ account: ExchangeAccount, password: String) async throws -> String {
        try validate(password)
        let started = try await apply(account, password: password)
        try await ensureStored(since: started)
        return confirmation(account)
    }

    private static func validate(_ password: String) throws {
        guard !password.isEmpty else { throw UpdateError.message("Enter a password.") }
        guard !password.contains(where: \.isNewline) else {
            throw UpdateError.message("The password cannot contain a line break.")
        }
    }

    @MainActor
    private static func apply(_ account: ExchangeAccount, password: String) async throws -> Date {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mail.app"))
        _ = try? Script.run(dismissSheet)
        try await waitUntilReady()
        let started = Date()
        do {
            try submit(account, password: password)
        } catch let UpdateError.message(text) {
            throw UpdateError.message(explain(text))
        }
        return started
    }

    /// Gives Mail the password, then fails if the stuck dialog comes back.
    private static func submit(_ account: ExchangeAccount, password: String) throws {
        let chosen = try Script.run(setPassword(account, password: password))
        _ = try? Script.run(checkMail(chosen))
        guard (try? Script.run(dismissSheet))?.trimmingCharacters(in: .whitespacesAndNewlines) != "cancelled" else {
            throw UpdateError.message(
                "Mail asked for the password again, so it was not stored. Check the password and try again."
            )
        }
    }

    /// Mail’s first save is often rejected. A later credential change means the password was stored.
    private static func ensureStored(since start: Date) async throws {
        var refused = false
        for attempt in 0..<4 {
            let output = logOutput(since: start)
            if output.contains("property credential changed") { return }
            refused = refused || output.contains("Code=5")
            if !refused { return }
            if attempt < 3 { try await Task.sleep(for: .seconds(4)) }
        }
        throw UpdateError.message("The system refused to store the password on the existing account.")
    }

    private static func confirmation(_ account: ExchangeAccount) -> String {
        let server = account.host.isEmpty ? "Exchange" : account.host
        return "Password updated for \(account.username) on \(server). Mail is reconnecting."
    }

    private static func waitUntilReady() async throws {
        let deadline = Date().addingTimeInterval(20)
        var last = "Mail is not responding."
        while Date() < deadline {
            do {
                _ = try Script.run(mailAccounts)
                return
            } catch let UpdateError.message(text) {
                last = text
                _ = try? Script.run(dismissSheet)
                try await Task.sleep(nanoseconds: 400_000_000)
            }
        }
        throw UpdateError.message(explain(last))
    }
}

enum Script {
    static func run(_ source: String) throws -> String {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw UpdateError.message("Could not build the Mail command.")
        }
        let result = script.executeAndReturnError(&error)
        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Mail command failed."
            throw UpdateError.message(message)
        }
        return result.stringValue ?? ""
    }
}

/// AppleScript string literal. Embedded quotes are doubled.
func appleQuote(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

private let mailAccounts = """
with timeout of 5 seconds
    tell application "Mail" to get name of every account
end timeout
"""

private let dismissSheet = """
with timeout of 5 seconds
    tell application "System Events"
        if not (exists process "Mail") then return "no-mail"
        tell process "Mail"
            repeat with mailWindow in windows
                try
                    repeat with mailSheet in sheets of mailWindow
                        set labelText to ""
                        repeat with lineText in static texts of mailSheet
                            set labelText to labelText & (name of lineText) & " "
                        end repeat
                        if labelText contains "already exists" or labelText contains "connect to the account" then
                            click button "Cancel" of mailSheet
                            return "cancelled"
                        end if
                    end repeat
                end try
            end repeat
        end tell
    end tell
    return "no-sheet"
end timeout
"""

private func setPassword(_ account: ExchangeAccount, password: String) -> String {
    """
    with timeout of 30 seconds
        tell application "Mail"
            set chosen to missing value
            repeat with mailAccount in accounts
                if user name of mailAccount is \(appleQuote(account.username)) then
                    set password of mailAccount to \(appleQuote(password))
                    set chosen to name of mailAccount
                    exit repeat
                end if
            end repeat
            if chosen is missing value then error "Mail has no account for this user name."
            return chosen
        end tell
    end timeout
    """
}

private func checkMail(_ accountName: String) -> String {
    """
    with timeout of 20 seconds
        tell application "Mail" to check for new mail for account \(appleQuote(accountName))
    end timeout
    """
}

private func logOutput(since start: Date) -> String {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    task.arguments = ["show", "--style", "compact", "--start", logStamp(start), "--predicate", logPredicate]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()
    guard (try? task.run()) != nil else { return "" }
    waitForExit(task)
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

private let logPredicate = "(process == \"accountsd\" AND eventMessage CONTAINS \"Code=5\") OR eventMessage CONTAINS \"property credential changed\""

private func logStamp(_ start: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: start.addingTimeInterval(-1))
}

private func waitForExit(_ task: Process) {
    let deadline = Date().addingTimeInterval(8)
    while task.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.2)
    }
    if Date() >= deadline, task.isRunning { task.terminate() }
}

func explain(_ message: String) -> String {
    if message.contains("not authorized") || message.contains("-1743") {
        return "Allow Exchange Password to control Mail and System Events in System Settings → Privacy & Security → Automation, then try again."
    }
    return redactStuckDialog(message)
}

private func redactStuckDialog(_ message: String) -> String {
    if message.contains("timed out") || message.contains("-1712") {
        return "Mail is still showing a password dialog. Click Cancel there, then try again."
    }
    return message
}
