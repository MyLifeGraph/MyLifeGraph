# MyLifeGraph

Mobile-first foundation for an AI-powered personal coach and life graph product.

## Structure

- `apps/mobile` - Flutter app with clean feature modules, Riverpod state, GoRouter navigation, Supabase and FastAPI client boundaries.
- `services/ai_service` - Python FastAPI service for recommendation and future ML workflows.
- `supabase` - PostgreSQL schema, Supabase config, and row-level security policies.
- `docs` - Architecture notes and implementation roadmap.

## Local Setup

Flutter is not installed in this workspace, so platform folders were not generated here. Once Flutter is available:

```bash
cd apps/mobile
flutter create .
flutter pub get
flutter run --dart-define=USE_MOCK_DATA=true
```

Run the AI service:

```bash
cd services/ai_service
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

Apply Supabase migrations with the Supabase CLI:

```bash
supabase start
supabase db reset
```

## Runtime Configuration

Pass mobile config with Dart defines:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://rnylirjfblwgygvgyfzr.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=... \
  --dart-define=AI_SERVICE_BASE_URL=http://localhost:8000 \
  --dart-define=USE_MOCK_DATA=true
```
