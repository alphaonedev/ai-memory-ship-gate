# Reproducing a campaign

You need:

1. A **DigitalOcean account** + API token.
2. An **SSH key registered with DO** + the matching private key
   locally.
3. A **GitHub account** that can fork this repo.

## Step 1 — Fork

```sh
gh repo fork alphaonedev/ai-memory-ship-gate --clone
cd ai-memory-ship-gate
```

## Step 2 — Secrets

The CI workflow reads four secrets:

| Secret | Contents |
|---|---|
| `DIGITALOCEAN_TOKEN` | DO personal access token with droplet create/delete + ssh_key read |
| `DIGITALOCEAN_SSH_KEY_FINGERPRINT` | SHA-256 fingerprint of the key you want cloud-init to authorise |
| `DIGITALOCEAN_SSH_PRIVATE_KEY` | The matching private key (PEM), used by the runner to ssh into droplets |

Set them:

```sh
# Generate a DO token at https://cloud.digitalocean.com/account/api/tokens
# Scopes needed: droplet: create/delete/read, ssh_key: read
gh secret set DIGITALOCEAN_TOKEN

# Get the fingerprint (substitute your actual key id / email)
doctl compute ssh-key list
gh secret set DIGITALOCEAN_SSH_KEY_FINGERPRINT

# Paste the matching private key
gh secret set DIGITALOCEAN_SSH_PRIVATE_KEY < ~/.ssh/id_ed25519
```

!!! warning "Never commit secrets"
    `.env` is gitignored. `.env.example` is the template. If you
    accidentally commit a token, **rotate it immediately** in the DO
    console. Token material pasted into a git commit is considered
    compromised even after force-push; GitHub may cache blobs.

## Step 3 — Trigger a run

Via the web UI: Actions → Ship-gate campaign → Run workflow.

Via CLI:

```sh
gh workflow run campaign.yml \
  -f ai_memory_git_ref=release/v0.6.0 \
  -f campaign_id=my-validation-run \
  -f region=nyc3
```

The workflow provisions infrastructure, runs all four phases, tears
down infrastructure, commits artefacts to `runs/my-validation-run/`,
and publishes the site.

## Step 4 — Verify the teardown

The workflow runs `terraform destroy -auto-approve` in an
`if: always()` step, so infrastructure tears down even if a phase
fails. Verify on your DO dashboard: no droplets tagged
`campaign-<your-id>` should remain.

If something pathological happened and droplets survive the
workflow, the in-droplet dead-man switch powers them off after
`DEAD_MAN_SWITCH_HOURS` (default 8). They still cost you until
terminated, so clean up manually with:

```sh
doctl compute droplet list --tag-name campaign-<your-id>
doctl compute droplet delete --tag-name campaign-<your-id> --force
```

## Step 5 — Read the report

The committed `runs/<campaign-id>/campaign-summary.json` has the
headline verdict; `runs/<campaign-id>/phase*.json` has per-phase
detail. The Pages site renders them at
`https://<your-org>.github.io/ai-memory-ship-gate/runs/<campaign-id>/`.

## Customising the campaign

- **Different size droplets**: edit `terraform/main.tf` `peer_size`
  default.
- **Different region**: pass `-f region=<slug>` at workflow run
  time.
- **More chaos cycles**: set `CYCLES` / `WRITES` env in the
  `phase4_chaos.sh` invocation in the workflow.
- **Add a fault class**: new `case` branch in
  `packaging/chaos/run-chaos.sh` (in ai-memory-mcp repo), then
  add to the loop in `scripts/phase4_chaos.sh`.

## Expected cost

~$0.65 per clean run. The campaign-cost discussion with receipts
lives in [Security & cost](security.md#cost-guardrails).

## Non-goals of the reproducing flow

- **Production grade**. This campaign validates ai-memory-mcp's
  release candidate. It is not a production-hardening suite.
  Operators deploying ai-memory in production should run
  their own security review.
- **Performance benchmarks**. Throughput + latency belong in
  `BACKEND-COMPARISON.md` (ai-memory-mcp v0.7.1 track).
