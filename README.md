# brainiac-github

GitHub webhook plugin for [Brainiac](https://github.com/stowzilla/brainiac) — the multi-agent orchestration layer.

## What It Does

- **PR Reviews** — dispatches agents to address review feedback
- **PR Comments** — routes PR conversation to the assigned agent
- **PR Merges** — cleans up worktrees, emits hooks for card management plugins
- **Workflow Runs** — notifies on CI failures and deploy completions
- **Issues** — logs new issues for tracking

## Installation

```bash
brainiac install github
brainiac restart
```

## Configuration

Config lives at `~/.brainiac/github.json`:

```json
{
  "webhook_secret": "your-github-webhook-secret",
  "allowed_owners": ["stowzilla", "ardavis"],
  "apps": {
    "brainiac": {
      "id": "100000",
      "private_key_path": "~/.brainiac/brainiac.pem",
      "installations": {
        "stowzilla": "11111111",
        "ardavis": "22222222"
      }
    },
    "galen": {
      "id": "200000",
      "private_key_path": "~/.brainiac/galen-brainiac.pem",
      "installations": {
        "stowzilla": "33333333",
        "ardavis": "44444444"
      }
    }
  },
  "repos": {}
}
```

The `allowed_owners` array restricts which GitHub accounts/orgs can trigger your
agents. Events from repos not owned by a listed account are rejected with a 403
before any processing occurs. If omitted, all owners are accepted (filtered
downstream by project matching instead).

Generate a webhook secret:

```bash
ruby -rsecurerandom -e 'puts SecureRandom.hex(20)'
```

### GitHub App Setup

The plugin uses GitHub Apps for two purposes:

1. **Inbound events** — a single "Brainiac" app receives webhook events from all repos
2. **Outbound identity** — per-agent apps post comments/reactions with distinct avatars

This mirrors how Discord works: one gateway delivers all messages, each bot responds
with its own token and avatar.

#### Architecture

```
brainiac (app)       → webhook ACTIVE, receives all events
galen-brainiac (app) → webhook DISABLED, Galen's posting identity
glados-brainiac (app)→ webhook DISABLED, GLaDOS's posting identity
```

The "brainiac" agent in the registry also uses the brainiac app as its posting
identity — so the webhook-receiver app doubles as the brainiac agent's identity.

#### Step 1: Create the Brainiac App (Webhook Receiver)

1. Go to **Settings → Developer settings → GitHub Apps → New GitHub App**
2. Set the following:
   - **Name**: `brainiac` (or your preferred orchestrator name)
   - **Homepage URL**: your Brainiac instance URL
   - **Webhook URL**: `https://your-ngrok.ngrok-free.app/github`
   - **Webhook secret**: paste the `webhook_secret` from your `github.json`
3. Under **"Where can this GitHub App be installed?"**, select **"Any account"**
   (allows installation on both personal accounts and organizations)
4. Set **Permissions** (under "Repository permissions"):
   - **Contents**: Read-only
   - **Issues**: Read & Write
   - **Pull requests**: Read & Write
5. **Subscribe to events**:
   - Issue comment
   - Issues
   - Pull request
   - Pull request review
   - Workflow run
6. Create the app and note the **App ID**
7. Generate a private key (see [Private Key Details](#private-key-details) below)
8. Upload an avatar for the app
9. **Install the app** on each account/org where you have repos:
   - Go to the app's settings → "Install App" tab
   - Install on your personal account (e.g. `ardavis`) — note the Installation ID
     from the URL: `https://github.com/settings/installations/INSTALLATION_ID`
   - Install on your org (e.g. `stowzilla`) — note that Installation ID too

#### Step 2: Create Agent Identity Apps (One Per Agent)

For each agent that should have its own avatar on PR comments:

1. Go to **Settings → Developer settings → GitHub Apps → New GitHub App**
2. Set the following:
   - **Name**: `galen-brainiac`, `glados-brainiac`, etc.
   - **Homepage URL**: your Brainiac instance URL
   - **Webhook**: uncheck **"Active"** (these apps don't receive events)
3. Under **"Where can this GitHub App be installed?"**, select **"Any account"**
4. Set **Permissions** (under "Repository permissions"):
   - **Contents**: Read-only
   - **Issues**: Read & Write
   - **Pull requests**: Read & Write
5. **Do NOT subscribe to any events** (webhook is disabled)
6. Create the app and note the **App ID**
7. Generate a private key
8. Upload the agent's **avatar**
9. **Install the app** on each account/org (same as the brainiac app)
10. Repeat for each agent

#### Step 3: Configure `github.json`

```json
{
  "webhook_secret": "your-github-webhook-secret",
  "allowed_owners": ["stowzilla", "ardavis"],
  "apps": {
    "brainiac": {
      "id": "100000",
      "private_key_path": "~/.brainiac/brainiac.pem",
      "installations": {
        "stowzilla": "11111111",
        "ardavis": "22222222"
      }
    },
    "galen": {
      "id": "200000",
      "private_key_path": "~/.brainiac/galen-brainiac.pem",
      "installations": {
        "stowzilla": "33333333",
        "ardavis": "44444444"
      }
    },
    "glados": {
      "id": "300000",
      "private_key_path": "~/.brainiac/glados-brainiac.pem",
      "installations": {
        "stowzilla": "55555555",
        "ardavis": "66666666"
      }
    }
  },
  "repos": {}
}
```

Each key in `apps` matches the agent's registry key (lowercase). The
`installations` hash maps account/org names to their Installation IDs.

#### Private Key Details

The `.pem` file is generated by GitHub — you don't create it yourself. On your
app's settings page (Settings → Developer settings → GitHub Apps → your app):

1. Scroll to the **"Private keys"** section
2. Click **"Generate a private key"**
3. GitHub generates an RSA key pair, keeps the public half, and your browser
   downloads the private half as a `.pem` file (named like
   `your-app-name.2026-08-06.private-key.pem`)
4. Move it to your brainiac config directory and lock down permissions:
   ```bash
   mv ~/Downloads/your-app-name.*.private-key.pem ~/.brainiac/galen-brainiac.pem
   chmod 600 ~/.brainiac/galen-brainiac.pem
   ```

The plugin uses this key to sign JWTs for GitHub API authentication. Never
commit `.pem` files to version control.

#### Fallback

If no app credentials are configured for an agent, the plugin falls back to
using the `gh` CLI (which authenticates as your personal GitHub account).

### Environment Variables

As an alternative to config file values, you can set (applies to single-app mode only):

- `GITHUB_WEBHOOK_SECRET` — webhook signature secret
- `GITHUB_APP_ID` — GitHub App ID
- `GITHUB_APP_PRIVATE_KEY_PATH` — path to the `.pem` private key file
- `GITHUB_APP_INSTALLATION_ID` — installation ID

For per-agent apps, use the config file — env vars don't support multiple apps.

### GitHub Webhook Setup

The webhook is configured on the Brainiac app itself (Step 1 above) — no
per-repo webhook setup is needed. The app-level webhook automatically receives
events from all repos where the app is installed.

If you have legacy per-repo webhooks pointing to `/github`, remove them to
avoid duplicate event deliveries.

## CLI

```bash
brainiac github setup     # Create config file from template
brainiac github config    # Show current configuration
brainiac github status    # Check if webhook endpoint is active
```

## Hooks Emitted

| Hook | When | Payload |
|------|------|---------|
| `:pr_merged` | PR merged to default branch | card_number, pr_url, project_key, ... |
| `:pr_review_received` | Review submitted | card_number, reviewer, agent_name, ... |
| `:pr_synchronized` | PR updated (force push) | card_number, worktree, branch, ... |
| `:production_deployed` | Deploy workflow succeeds | project_key, project_config |

## Development

```bash
git clone https://github.com/stowzilla/brainiac-github.git
cd brainiac-github
bundle install
bundle exec rake test
bundle exec rubocop
```

## License

MIT
