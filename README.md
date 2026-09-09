# AURORA Native iOS v1

This is a **real native iPhone/iPad application** built with SwiftUI. It does not use Safari, HTML, JavaScript, localStorage, or a WebView.

## Native architecture
- SwiftUI interface
- SwiftData local projects and run history
- URLSession transport
- QuickLook/PDFKit engineering preview
- Swift Charts result visualization
- Native iPhone PDF + CSV generation
- Canonical AURORA server exports (PDF/XLSX/DOCX/CSV/SVG/DXF/PNG/ZIP) are surfaced when returned as HTTPS artifact links

## Canonical AURORA API already wired
The production Railway logs show these real endpoints, and the native client uses them:
- `GET /api/health`
- `POST /api/validate`
- `POST /api/jobs`
- `GET /api/jobs/{job_id}`

Default runtime:
`https://todo-app-production-afcc.up.railway.app`

The native app does not bypass scientific/governance gates. A governed `blocked` result is shown as a blocked result with the returned details.

## Build without owning a Mac
1. Create a GitHub repository.
2. Upload this folder to the repository root.
3. GitHub Actions `ios-ci.yml` uses a macOS runner, generates the Xcode project with XcodeGen, and builds the native app for the iPhone Simulator.
4. For a real iPhone install, Apple requires code signing. Use an Apple Developer account and TestFlight. The included `testflight-template.yml` documents the required secrets.

## Current v1 screens
Dashboard, Projects, Project Basis, Ore & Analyses import, Canonical Execution, structured KPI/results, engine stage trace, Engineering Workspace, Deliverables, Runtime Settings.

## Important next backend integration
For XLSX/DOCX/DXF/SVG/ZIP downloads, the AURORA backend must return **HTTPS download URLs** for generated files instead of server-local filesystem paths. The native app automatically recognizes those URLs when they appear in job results.
