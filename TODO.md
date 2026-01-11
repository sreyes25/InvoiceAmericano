# Pre-Launch Checklist
- [ ] Validate App Store metadata (privacy nutrition labels, screenshots, app description) and comply with App Tracking Transparency requirements.
- [ ] Run App Store preflight checks: archiving in Release mode, symbol upload, and TestFlight distribution smoke tests.
- [ ] Confirm production configuration toggles (Supabase project/keys, Stripe live mode, feature flags) and remove any debug-only paths before build.
- [ ] Verify PDF generation and share sheet output on device for a real invoice and logo (sanity check formatting and accessibility).

---

# Release Workflow (v1 → TestFlight → Launch)

## 1) Code & Environment Readiness
- [ ] Ensure all pre-launch checklist items above are complete.
- [ ] Verify release branch/build number and semantic version for v1.
- [ ] Confirm build settings for Release configuration.

## 2) Archive & Upload
- [ ] Archive in Xcode (Release).
- [ ] Upload build to App Store Connect.
- [ ] Confirm symbols/dSYM upload succeeded.

## 3) TestFlight
- [ ] Add internal testers; run smoke test on physical devices.
- [ ] Validate core flows: onboarding, invoice creation, payment link, PDF share, client management.
- [ ] Address any crash reports or blocking issues.

## 4) App Store Submission
- [ ] Confirm App Store metadata, privacy labels, and screenshots.
- [ ] Submit for review and monitor status.

## 5) Launch
- [ ] Resolve any App Review feedback.
- [ ] Release v1 to the App Store.
