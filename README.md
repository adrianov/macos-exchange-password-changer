# macOS Mail Exchange Password Changer

After a company password change, macOS Mail may reject the new Exchange password with “This account already exists.” The usual workaround is to remove and recreate the account.

This utility stores the new password in the macOS keychain for the existing account. Mail can reconnect without removing the account, changing its settings, or downloading its data again.

It does not change your company password. Use it after changing that password through your company.

![Exchange Password window. The account line is a sample.](screenshot.png)

## Install

Download the DMG from [Releases](https://github.com/adrianov/macos-exchange-password-changer/releases), then drag **Exchange Password** to Applications. The app is not notarized, so right-click it and choose **Open** on the first launch.

Choose the Exchange account, enter its new password twice, and click **Update password**. On the first run, allow control of Mail and System Events in **System Settings → Privacy & Security → Automation**.

## Build from source

```sh
./build.sh
open "build/Exchange Password.app"
```

Copyright © 2026 Peter Adrianov. Licensed under the MIT License.
