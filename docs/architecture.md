# Architecture

## Mobile App

The Flutter app uses feature-first clean architecture:

- `core` contains cross-cutting concerns such as config, bootstrap, routing, network clients, Supabase access, theme, and reusable widgets.
- `features/*/domain` contains entities and repository contracts.
- `features/*/data` contains mock data sources and repository implementations.
- `features/*/application` contains service orchestration for use cases that should not live in widgets.
- `features/*/presentation` contains pages, widgets, and Riverpod providers.

State management is Riverpod. UI state depends on providers, providers depend on services or repositories, and repositories own data-source selection. This keeps screens independent from Supabase, FastAPI, and future local cache choices.

Navigation is handled with GoRouter and a shell route. The bottom navigation maps to:

- Dashboard
- Insights
- Central quick-action `+`
- Notifications
- More

## Backend

Supabase owns authentication, PostgreSQL persistence, and row-level security. The initial schema separates raw behavioral events, daily lifestyle entries, generated skillset profiles, recommendations, and notification preferences.

The FastAPI service is an independent AI boundary. It currently returns mock recommendations, but it already exposes versioned endpoints and a service class where future model inference, feature extraction, and ranking logic can be added.

## Security Posture

- Supabase RLS is enabled on all user-owned tables.
- User-facing tables scope access with `auth.uid()`.
- FastAPI service role secrets are kept out of the mobile app.
- Mobile config uses Dart defines so secrets are not hard-coded in source.
- Production AI endpoints should validate Supabase JWTs before reading user data.

## Scalability Notes

- Feature modules can be added without changing global app structure.
- Repository contracts allow switching from mock data to Supabase, REST, cache, or hybrid data sources.
- AI service can scale separately from mobile and database workloads.
- PostgreSQL indexes are present for user/time query patterns used by dashboards and recommendation generation.
