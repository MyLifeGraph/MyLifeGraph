# Product Polish Follow-up

Status: implemented on 2026-07-18. The manual five-student usability study was
subsequently skipped/deferred and remains not run. The runnable protocol is in
`docs/student-usability-test-script.md`; recruitment, facilitation, notes, and
synthesis templates are in `docs/student-usability-study/`. A five-agent
compressed persona walkthrough is documented separately in
`docs/synthetic-student-persona-simulation-2026-07-18.md` and is not participant
evidence.

## 6. Remove Or Finish Unproven Product Promises

Implemented:

- Real accounts no longer fetch or show the unproduced Skillset card. Local
  demo mode labels the card as example data only.
- Notification settings, Inbox rows, and foreground banners consistently say
  that delivery is in-app while MyLifeGraph is open. They explicitly disclaim
  browser, phone-system, email, push, background-mobile, and deployed delivery.
- Setup's reminder preference says that it stores a preference only. Enabling
  foreground banners requires separate consent in Settings.
- The Coach route is hard-disabled in release builds and whenever
  `APP_ENV=production`; a Flutter define cannot override that boundary. In a
  non-production debug/profile build it remains an explicit development
  preview whose fake and local-Codex provider truth is visible.
- Real accounts no longer see an empty Skillset promise. Rule-based plans,
  reviews, reminders, and suggestions use plain provenance such as
  `rule-based`, `fixed text`, `example`, or `preview` instead of implying that
  they were learned or AI-generated.

Automated acceptance coverage proves production Coach gating, real-account
Skillset absence without a data-source read, notification non-claims, and
separate reminder preference versus foreground consent.

## 7. Plain-language And Localization Pass

Implemented:

- The supported V1 interface language is explicitly English. German is not yet
  advertised as supported, so the app does not intentionally mix two UI
  languages. See `docs/ui-language-and-copy-contract.md`.
- Primary surface names are standardized: `Today`, `Quick actions`, `Evening
  check-in`, `Morning check-in`, `Focus`, `Preparation plans`, `Weekly review`,
  `Calendar`, `Inbox`, `Insights`, `Coach`, and `Settings`.
- Primary controls no longer expose terms such as calibration,
  controllability, deterministic, provenance, projection, revision, bounded,
  or backend. Technical Coach provider/model detail is secondary and
  expandable.
- Ambiguous-save messages state what could not be confirmed, what was retained,
  and the two safe choices: `Retry unchanged` or load the latest saved state.
- Existing 320 px and 200% text-scale tests now cover Settings dialogs,
  notification surfaces, Insights, and the compact main navigation. The main
  student journeys remain scrollable rather than shrinking or clipping text.

The remaining acceptance activity is a real moderated think-aloud usability
study with five relevant students. It uses a second short contact after a real
confirmed block has passed so missed-block recovery is observed without a fake
state. It must not be reported as complete until participant evidence and
results are recorded in the study templates.
