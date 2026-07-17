# WebTerm iOS Wrapper

Minimal SwiftUI + WKWebView wrapper that opens a self-hosted web terminal (e.g. ttyd)
as a fullscreen iOS app.

The terminal URL is injected at build time from the `TERMINAL_URL` GitHub Actions
secret — it is not stored in this repository. To build your own: fork, set the
secret to your terminal's URL, run the workflow, download the unsigned IPA from
Artifacts and sideload it (SideStore / AltStore).
