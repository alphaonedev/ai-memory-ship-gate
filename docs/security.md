# Security & cost

## Secrets posture

Every secret used by this repo lives in exactly **two** places:

1. **GitHub Actions secrets** on the repository (encrypted at rest).
2. **Runtime environment** of the workflow job (ephemeral; GitHub
   masks values in logs by default).

Secrets **never** appear in:

- the repository tree (`.gitignore` blocks `.env`, `*.pem`, `*.key`,
  `*.tfstate*`, `id_*`),
- commit messages, PR descriptions, or issue bodies,
- README / docs markdown,
- Terraform state (state files are gitignored; CI uses local state
  only for the duration of a run).

If you suspect a token was committed by accident:

1. **Rotate it immediately** — don't wait for cleanup.
2. Purge from GitHub's blob cache by contacting GitHub Support
   (force-push alone does not expunge cached blobs from search).
3. Open a post-mortem issue in this repo.

## Token scope

The DO token for this workflow needs only:

- `droplet: create, delete, read`
- `ssh_key: read`

It does **NOT** need:

- domain, spaces, kubernetes, billing, app platform, or any write
  scopes beyond droplet lifecycle.

Audit your DO token's scope at
<https://cloud.digitalocean.com/account/api/tokens>. If in doubt,
generate a scoped token rather than a full-access one.

## Workflow isolation

- The campaign workflow runs in a fresh GitHub-hosted runner
  (Ubuntu 24.04). No cached state between runs.
- Terraform state lives only inside the runner's working directory.
  It is NOT checked in. Each campaign provisions and destroys
  infrastructure from scratch.
- SSH keys are never written to disk outside the runner (`~/.ssh/`
  on the ephemeral runner), and the runner is destroyed when the
  job completes.

## Droplet hardening

cloud-init applies:

- `ufw allow 22/tcp` + `ufw allow 9077/tcp` + `ufw --force enable`.
  No other ports.
- Root SSH only via the pre-authorised key (no passwords).
- Docker runs with default restricted privileges (no
  `--privileged`).
- The dead-man switch self-destructs the droplet after N hours
  regardless of workflow state.

## Cost guardrails

Three independent safeguards keep a runaway campaign under ~$2:

1. **Terraform tear-down in `if: always()` step.** Workflow failure
   still triggers destroy.
2. **In-droplet dead-man switch.** 8-hour hard cap on uptime.
3. **GitHub Actions timeout (300 min).** Workflow itself can't run
   longer than 5 hours.

If all three fail simultaneously, the monthly bill ceiling for a
forgotten campaign is ~$130 (3 × `s-2vcpu-4gb` + 1 × `s-1vcpu-2gb`
× 720 hours). Set up DO billing alerts at $5 to catch this early.

## Responsible disclosure

Vulnerability in this repo's infrastructure? Email
**security@alphaone.dev**. Don't open public issues for security
problems. We commit to acknowledge within 72 hours.
