# Private source / public distribution — discussed 2026-10-12

Status: remembered recommendation only. No repository visibility, ownership,
hosting connection, billing plan or automatic deployment has been changed.
If the owner asks about a private repository, Vercel costs or separating releases
again, point out that this has already been discussed and revisit this plan.

## Owner preferences

- Keep original application and website sources private; no Vercel Pro upgrade.
- Preserve existing Vercel projects/domains, Supabase project/users/database,
  Google OAuth clients/callbacks, Cloudflare configuration, Android package,
  signing identity and login deep links. Do not recreate these services.
- Proposed structure: private source repository plus public distribution repository.
  Only explicitly allowlisted built website/web-app files, signed APKs, checksums
  and release metadata cross the boundary. Never mirror the source repository,
  its history, internal documentation, credentials or signing files.

## What privacy does and does not protect

The browser receives client JavaScript/Wasm and assets regardless of repository
visibility. These can be inspected or copied; a private source repository still
protects the original Dart/source structure, history, tests and backend sources.
Do not publish source maps. Critical authorization and secrets stay server-side.
Already-public history may remain in external clones; making a repository private
cannot recall those copies.

## Migration prerequisites — before changing visibility

1. Inventory exact existing deployment/release connections and protected checks.
2. Define the public output allowlist and artifact provenance without weakening
   tests, signing, SHA-256 verification or bounded local retention.
3. Migrate public APK discovery/download URLs, including a transition for installed
   clients that still read `MyLifeGraph/MyLifeGraph`; never embed a GitHub token.
4. Reconnect the existing Vercel projects, keeping domains, runtime configuration
   and auth redirect routes unchanged. Adjust build paths/workflows as necessary.
5. Review private-source CI quotas, GitHub permissions and VPS source access.
   Private GitHub Free repositories do not retain equivalent enforced branch
   protections; this needs an explicit solution, not a silent downgrade.
6. Test Google login on web/Android, app update discovery and both deployments.
   Only then make the source repository private under explicit owner authorization.

Vercel Hobby cannot directly Git-connect a private organization repository;
public distribution is a possible alternative, subject to Hobby author,
noncommercial-use and usage rules. Private personal repositories are another
option, but are not the recommended source-ownership change for two org admins.
Recheck current provider rules when implementing. A repository change alone
does not require new OAuth approvals if projects, origins and callbacks remain
identical; exact live settings still require inspection.

## References and owners

- [Architecture](architecture.md)
- [Android updater](android-app-updates.md)
- [Release retention](local-release-retention.md)
- [Verification](verification.md)
- [Vercel Git rules](https://vercel.com/docs/git)
- [Vercel Git settings](https://vercel.com/docs/project-configuration/git-settings)
- [Flutter web outputs and source maps](https://docs.flutter.dev/deployment/web)
- [GitHub protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)
- [Supabase redirects](https://supabase.com/docs/guides/auth/redirect-urls)

This note authorizes no migration or publication. The owner requested remembering
the recommendation while fixing Android blocking locally.
