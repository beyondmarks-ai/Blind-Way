# Login recovery — November 10, 2026

The real phone error was captured before restarting the app: Google OTP verification completed, then `/v1/profile` failed with `Network is unreachable, errno = 101` against the Azure Functions host. The previous controller responded by logging out of Google, deleting saved metadata, and returning to Send OTP.

## Network fix

The vivo Y51A's active Jio data connection had IPv6 internet access without an IPv4 route. Azure Functions was configured with `ipMode: IPv4`. Enabled `IPv4AndIPv6` through Azure CLI and recorded the same setting in `infra/main.bicep` using the 2024-11-01 sites API.

Azure DNS now publishes an AAAA record. After refreshing the phone's mobile-data connection, the API hostname resolved on the phone and IPv6 ping succeeded in approximately 66–71 ms. No private-DNS, carrier/APN, phone hotspot, or authentication-verification settings were changed.

## App fix

- Successful Google phone verification is retained when account registration or connection recovery fails.
- **Retry sign-in** refreshes the native Google token and retries the authenticated account request without another OTP.
- The sign-in form stays locked during recovery; **Change number or cancel** explicitly discards the pending login.
- Restoring an existing login uses the same recovery path. Revoked/expired native credentials require a new login.
- Friendly connection and role-conflict messages replace raw Dio exceptions.
- The app grants no dashboard session until the backend accepts the account. Server token validation and immutable roles remain unchanged.

## Validation

16 targeted authentication, recovery and sign-in widget tests passed. They cover connection failure after OTP, retry, server rejection, cancellation during a pending request, token-refresh failure, expiry and recovery controls. Flutter analysis passed. Bicep compilation passed with an existing unrelated warning about the optional Web PubSub resource.

The earlier apparent recovery was a successful OTP/restart attempt; it did not establish the cause of the intermittent failure. This change addresses the subsequently captured network error and the controller's destructive failure behavior.

Build **11** was installed through ADB. The ARM64 debug APK is saved as `D:\Blind Way\Blind-Way-Camera-Fix.apk`; signature verification passed. SHA-256: `AB70DEF6E10D65ABA0293AAFF33D9A9A474D3F7CD7B0155F0DD52433C535CA7D`.

The installed update reached OTP entry on the real phone. USB/ADB disconnected before final verification, so the post-fix completed login and deliberate offline/retry device test remain unverified. The regression tests above exercise the retry behavior without another OTP; they are not a substitute for that final physical-device check.
