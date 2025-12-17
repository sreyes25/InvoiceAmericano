# Pre-Launch Checklist

- [ ] Add tenant/user scoping to all Supabase queries to avoid cross-tenant data leaks.
- [ ] Capture and surface checkout URLs returned by `create_checkout` to provide payment links immediately after invoice creation.
- [ ] Improve onboarding state handling to avoid forcing returning users through onboarding when network issues occur (cache last-known onboarding status or separate error states).
- [ ] Expand automated tests for authentication, invoice creation/filtering, profile updates, and realtime notifications.
- [ ] Perform end-to-end testing covering invoice creation, payment link sharing, client management, and authentication flows on real devices.
- [ ] Verify Supabase Row Level Security policies and storage permissions match the expected tenant isolation model.
- [ ] Review error handling and user messaging for offline scenarios across Home, Invoices, and Account flows.
- [ ] Audit analytics/logging to ensure no sensitive data is sent and events cover core funnel steps.
- [ ] Validate App Store metadata (privacy nutrition labels, screenshots, app description) and comply with App Tracking Transparency requirements.
- [ ] Run App Store preflight checks: archiving in Release mode, symbol upload, and TestFlight distribution smoke tests.
