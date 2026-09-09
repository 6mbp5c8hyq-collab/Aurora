# AURORA TestFlight setup

The AURORA TestFlight workflow is manual by design. It creates a signed
Release archive, exports an IPA, uploads the IPA as a GitHub Actions artifact,
and sends it to App Store Connect TestFlight.

Before running it, add these repository secrets under Settings → Secrets and
variables → Actions:

| Secret | Required value |
|---|---|
| APPLE_TEAM_ID | Apple Developer Team ID |
| IOS_CERTIFICATE_P12_BASE64 | Base64-encoded Apple Distribution .p12 certificate |
| IOS_CERTIFICATE_PASSWORD | Password for the .p12 certificate |
| IOS_PROVISIONING_PROFILE_BASE64 | Base64-encoded App Store distribution profile for com.auroraindustrial.native |
| ASC_KEY_ID | App Store Connect API key ID |
| ASC_ISSUER_ID | App Store Connect issuer ID |
| ASC_PRIVATE_KEY_P8_BASE64 | Base64-encoded App Store Connect API .p8 private key |

The bundle identifier is fixed to com.auroraindustrial.native and must match
the App ID and provisioning profile in the Apple Developer account.

After adding the secrets, open Actions → AURORA TestFlight → Run workflow.
The workflow validates that every required secret exists before importing any
signing material.
