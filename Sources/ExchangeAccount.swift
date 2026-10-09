import Foundation

/// An Exchange account Mail already has.
struct ExchangeAccount: Identifiable, Hashable {
    var id: String
    var name: String
    var username: String
    var host: String
}

enum AccountStore {
    /// Exchange accounts Mail can already see. The Internet Accounts database is not readable by this app.
    static func exchangeAccounts() throws -> [ExchangeAccount] {
        do {
            return accounts(from: try Script.run(exchangeListing))
        } catch let UpdateError.message(text) {
            throw UpdateError.message(explain(text))
        }
    }
}

private let exchangeListing = """
with timeout of 8 seconds
    tell application "Mail"
        set output to ""
        repeat with mailAccount in accounts
            try
                set accountKind to account type of mailAccount as string
                if accountKind is "unknown" or accountKind contains "exchange" then
                    set output to output & (id of mailAccount) & tab & (name of mailAccount) & tab ¬
                        & (user name of mailAccount) & tab & (server name of mailAccount) & linefeed
                end if
            end try
        end repeat
        return output
    end tell
end timeout
"""

/// Tab-separated rows: id, name, user name, server.
func accounts(from listing: String) -> [ExchangeAccount] {
    listing.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 3, !fields[0].isEmpty, !fields[2].isEmpty else { return nil }
        return ExchangeAccount(
            id: fields[0],
            name: fields[1].isEmpty ? "Exchange" : fields[1],
            username: fields[2],
            host: fields.count > 3 ? fields[3] : ""
        )
    }
}
