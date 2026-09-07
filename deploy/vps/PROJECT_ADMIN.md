# MyLifeGraph project maintainer

This role lets Matthias maintain the project and edit/test its code on the VPS
without the `ops` password. It is prepared separately from SSH enrollment and
requires one initial, reviewed installation by `ops`. Current installation and
test evidence belongs in [Verification](../../docs/verification.md#current-verified-baseline).

## Scope

The personal `mylifegraph-matthias` login keeps its own keys and primary/work
groups. A narrow `NOPASSWD:NOSETENV` sudo rule permits only the installed,
root-owned `/usr/local/sbin/mylifegraph-project` command and `sudoedit` of exactly
`api.env`, `executor.env` and `caddy.env` under `/etc/mylifegraph`. The editor runs
as Matthias. No general root shell, package manager, host Docker group/socket,
unit-file editor, SSH administration or permission to other users' projects is
included. This is Unix account separation, not a private VM.

Matthias is a trusted **project release operator**. Upload checksums prove byte
consistency; they do not independently prove GitHub main/tag/CI provenance. He
must follow the existing protected-main, reviewed-tag and CI workflow before
uploading a release. Allowing application deployment and configuration editing
also entrusts him with project secrets/data through deployed code and with the
shared provider's operation. This is not a claim that an arbitrary backend
maintainer is isolated from runtime credentials. Codex OAuth files must still
never be copied, printed or read by agents; use native login/capability status.

The existing rootful Docker and Coach rootless Docker remain separate. Matthias
gets his own rootless daemon/socket and development files. The default bridge
and new user-defined bridge networks default to loopback port bindings, following
[Docker's published-port configuration](https://docs.docker.com/engine/network/port-publishing/#setting-the-default-bind-address-for-containers).
Explicit host-IP overrides can still change that; inspect published ports and
keep development services on loopback. His systemd user slice
is capped at 4 GiB RAM, two CPUs and 2,048 tasks. Heavy full-stack/Android checks
can use GitHub CI when this shared host's budget is insufficient. Do not prune
other users' images, stop unrelated services, or publish development ports on
all network interfaces.

Local SSH forwarding to loopback is allowed for IDEs and browser previews.
Remote forwarding, agent forwarding and X11 forwarding remain off. A shell user
can already initiate network connections; these SSH options are not a network
isolation boundary. SSH keys and root helper/OS upgrades remain `ops` work. Once
this sudo role is active, the original access bootstrap intentionally refuses
further enrollment; do not weaken that guard to add another key.

## First installation by ops

The administrator installs a reviewed, checksum-sealed package at
`/root/mylifegraph-maintainer` and runs its `install_project_admin.py` with system
Python in isolated mode. The package contains the fixed helpers/policies,
a Git source bundle and the already reviewed initial RC4 setup archive.
It preserves an existing MyLifeGraph checkout rather than overwriting work.

The installer seals RC4 without starting the app, sets up Matthias's development
files and user Docker, checks effective SSH policy and resource limits, then
installs the narrow sudo rule last. SSH and sudoers publication is atomic and
validation failures remove only this invocation's policy files. It is an
initial-only operation: a failure can leave prepared helpers or development
files. Inspect its reported phase before retrying; do not blindly delete files
or rerun a first-stage bootstrap. No database, model, or application deployment
is performed by the role installation.

## Working checkout and development

After installation, the editable checkout is `~/MyLifeGraph`. A new checkout
starts on the prepared source bundle's working branch; the origin points to
`https://github.com/MyLifeGraph/MyLifeGraph.git`. No GitHub or provider credentials
are copied. Existing checkouts and their work are preserved. Matthias uses his
own GitHub login for fetch/push; normal repository main confirmations and checks
apply in his agent session too.

Start a development shell with:

```bash
source ~/.config/mylifegraph/development.env
cd ~/MyLifeGraph
```

This selects only his Docker socket and uses development API port **8001**;
production keeps **8000**. Both the local-stack and browser-test port variables
are set. Run the normal [local-development commands](../../docs/local-dev.md#complete-local-stack).
The role installs no Flutter, Android, browser or Supabase SDK binary. Matthias
and his agent can install missing user-space tools in his home, following the
repository's existing version pins and checks; never into the repository and
never by sharing production credentials. Git, Node/npm, Python and the rootless
Docker prerequisites are checked before installation. OS package changes still
need an administrator; a development container can supply its own packages.

Docker commands must select the development environment above. To manage its
daemon:

```bash
systemctl --user status docker --no-pager
systemctl --user restart docker
```

For a private browser preview, from Matthias's own device (select its SSH key
as usual):

```bash
ssh -N -L 7357:127.0.0.1:7357 -L 8001:127.0.0.1:8001 \
  -L 54321:127.0.0.1:54321 mylifegraph-matthias@178.104.87.50
```

Then use `http://127.0.0.1:7357` locally while the development stack runs. Tests
use a separate local Supabase database on his Docker daemon, not the hosted
pilot. Migrations, reset/backup guards and fake-provider defaults remain as in
the repository. Agents must not turn a failing real account read into demo data.

## Initial application activation

After the role is installed, Matthias can finish the prepared RC4 himself:

```bash
sudo /usr/local/sbin/mylifegraph-project setup
```

Use an interactive SSH terminal. The sealed setup asks for the API hostname and
accepts the backend key with hidden input, checks the existing database contract,
then starts and verifies HTTPS/API/Coach. It is initial-only and stops on existing
configuration. Complete this before using `sudoedit`; creating configuration
files early would correctly block the first-install checks. The initial setup
retains its existing failure cleanup and does not undo database reconciliation
or already handled traffic. See the [handoff](../../docs/vps-matthias-handoff.md)
for the DNS/key prerequisites and separate Vercel/browser acceptance.

## Day-to-day project operations

```bash
sudo /usr/local/sbin/mylifegraph-project status
sudo /usr/local/sbin/mylifegraph-project check
sudo /usr/local/sbin/mylifegraph-project logs api
sudo /usr/local/sbin/mylifegraph-project restart api
sudo /usr/local/sbin/mylifegraph-project stop api
```

Unit arguments are exactly `api`, `coach`, `socket` or `web`. The same fixed
units also support `start`, `enable` and `disable` for explicit boot management. Logs are bounded to
the last 100 entries without a pager; they may contain project data and must not
be pasted unfiltered. `status` reports process state, while `check` verifies the
current immutable release, loopback/public API health and database readiness,
host permissions and Coach capability without sending a model request. After a
restart, wait for startup and run `check`; a systemctl success alone is not
application readiness.

After initial setup, edit only the required project configuration:

```bash
sudoedit /etc/mylifegraph/api.env
sudoedit /etc/mylifegraph/executor.env
sudoedit /etc/mylifegraph/caddy.env
```

Keep one assignment per line and the documented API hostname unquoted in
`MYLIFEGRAPH_API_HOST=...` form. Restart the affected fixed unit and check it.
Preserve immutable release identity, the existing journal directory, runtime
UID/socket bindings and provider compatibility. Do not put production settings
or keys into the development checkout. Environment-file editing does not permit
editing service definitions or executing a root editor.

## Release preparation and deployment

Build a reviewed annotated RC source bundle using the existing
[release procedure](README.md#build-and-release-flow). These commands run in the
folder containing its two files; substitute the exact tag and computed hashes:

```bash
release_tag=v0.1.0-pilot.1-rc.5  # Replace with the exact reviewed tag.
archive="mylifegraph-${release_tag}.tar.gz"
manifest="mylifegraph-${release_tag}.source.json"
archive_sha=$(sha256sum "$archive" | cut -d ' ' -f 1)
manifest_sha=$(sha256sum "$manifest" | cut -d ' ' -f 1)
sudo /usr/local/sbin/mylifegraph-project upload "$release_tag" archive "$archive_sha" < "$archive"
sudo /usr/local/sbin/mylifegraph-project upload "$release_tag" manifest "$manifest_sha" < "$manifest"
sudo /usr/local/sbin/mylifegraph-project prepare "$release_tag"
sudo /usr/local/sbin/mylifegraph-project promote "$release_tag"
```

Select the actual reviewed tag before execution. Uploads read stdin,
never root-read a caller-selected path. They are size-bounded, hash-checked,
root-sealed, preserve existing inputs and reserve free disk. `prepare` uses the
installed build helper, which runs candidate build code as the locked build
identity. The analysis image is built as the Coach runtime user and checked
against the sealed revision label. `image <rc-tag>` can repeat this step.

`promote` uses the existing immutable-tree, HTTPS, database-compatibility and
rollback helper and checks Coach capability afterward. A later Coach failure
is reported explicitly as **release promoted, Coach not ready**; it does not
claim core promotion was undone. Diagnose it with the project logs/check command.
An already prepared compatible earlier release can be promoted explicitly for
rollback; database migrations are never rolled back by this operation.
