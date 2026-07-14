-- Account Export V1 includes the legacy-but-canonical lifestyle_entries
-- product table. Unlike the later schema tables, the initial migration did
-- not grant the backend service role a Data API table privilege, which made
-- even an empty export fail while obtaining its owner-scoped watermark.
--
-- The authenticated owner policy remains unchanged; this is the smallest
-- backend-only privilege required after FastAPI has verified the bearer token.
grant select on table public.lifestyle_entries to service_role;
