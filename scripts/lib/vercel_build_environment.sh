#!/usr/bin/env bash

# This file is sourced by scripts/vercel_build.sh. It deliberately exposes only
# public hosted-build inputs; no inherited project secret reaches Node, Flutter,
# Dart, Git, curl, pub, or a package build hook.

vercel_run_clean() {
  /usr/bin/env -i \
    HOME="${VERCEL_BUILD_HOME:?}" \
    TMPDIR=/tmp \
    LANG=C.UTF-8 \
    TZ=UTC \
    CI=1 \
    PATH="${VERCEL_BUILD_PATH:?}" \
    "$@"
}

vercel_run_public() {
  /usr/bin/env -i \
    HOME="${VERCEL_BUILD_HOME:?}" \
    TMPDIR=/tmp \
    LANG=C.UTF-8 \
    TZ=UTC \
    CI=1 \
    PATH="${VERCEL_BUILD_PATH:?}" \
    PUB_CACHE="${VERCEL_PUB_CACHE:?}" \
    APP_ENV="${APP_ENV-}" \
    USE_MOCK_DATA="${USE_MOCK_DATA-}" \
    COACH_SURFACE_ENABLED="${COACH_SURFACE_ENABLED-}" \
    APP_BUILD_SHA="${APP_BUILD_SHA-}" \
    APP_RELEASE_TAG="${APP_RELEASE_TAG-}" \
    STAGING_SUPABASE_PROJECT_REF="${STAGING_SUPABASE_PROJECT_REF-}" \
    PILOT_SUPABASE_PROJECT_REF="${PILOT_SUPABASE_PROJECT_REF-}" \
    SUPABASE_URL="${SUPABASE_URL-}" \
    SUPABASE_PUBLISHABLE_KEY="${SUPABASE_PUBLISHABLE_KEY-}" \
    SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY-}" \
    PILOT_CONTACT_EMAIL="${PILOT_CONTACT_EMAIL-}" \
    APP_PUBLIC_ORIGIN="${APP_PUBLIC_ORIGIN-}" \
    TURNSTILE_SITE_KEY="${TURNSTILE_SITE_KEY-}" \
    AI_SERVICE_BASE_URL="${AI_SERVICE_BASE_URL-}" \
    VERCEL="${VERCEL-}" \
    VERCEL_ENV="${VERCEL_ENV-}" \
    VERCEL_GIT_REPO_OWNER="${VERCEL_GIT_REPO_OWNER-}" \
    VERCEL_GIT_REPO_SLUG="${VERCEL_GIT_REPO_SLUG-}" \
    VERCEL_GIT_COMMIT_SHA="${VERCEL_GIT_COMMIT_SHA-}" \
    VERCEL_GIT_COMMIT_REF="${VERCEL_GIT_COMMIT_REF-}" \
    "$@"
}
