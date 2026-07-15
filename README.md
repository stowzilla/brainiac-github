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
  "app": {
    "id": "123456",
    "private_key_path": "~/.brainiac/github-app-private-key.pem",
    "installation_id": "78901234"
  },
  "repos": {}
}
```

Generate a webhook secret:

```bash
ruby -rsecurerandom -e 'puts SecureRandom.hex(20)'
```

### GitHub App Setup (Recommended)

Using a GitHub App makes PR comments and reactions appear as the app's bot user
(e.g. "brainiac-bot") instead of your personal account. This gives each agent a
distinct identity in PR conversations.

1. Go to **Settings → Developer settings → GitHub Apps → New GitHub App**
2. Set the following:
   - **Name**: e.g. `brainiac-bot`
   - **Homepage URL**: your Brainiac instance URL
   - **Webhook URL**: leave blank (webhook is handled by the plugin directly)
   - **Permissions**:
     - Pull requests: Read & Write
     - Issues: Read & Write
     - Contents: Read (for fetching PR diffs)
   - **Events**: uncheck everything (events come via the repo webhook, not the app)
3. Create the app and note the **App ID** from the app's settings page
4. Generate a private key (`.pem` file) and save it to `~/.brainiac/github-app-private-key.pem`
5. Install the app on your org/repos and note the **Installation ID** from the URL:
   `https://github.com/settings/installations/INSTALLATION_ID`
6. Add the credentials to your `github.json`:
   ```json
   {
     "app": {
       "id": "123456",
       "private_key_path": "~/.brainiac/github-app-private-key.pem",
       "installation_id": "78901234"
     }
   }
   ```

If app credentials are not configured, the plugin falls back to using the `gh` CLI
(which authenticates as your personal GitHub account).

### Environment Variables

As an alternative to config file values, you can set:

- `GITHUB_WEBHOOK_SECRET` — webhook signature secret
- `GITHUB_APP_ID` — GitHub App ID
- `GITHUB_APP_PRIVATE_KEY_PATH` — path to the `.pem` private key file
- `GITHUB_APP_INSTALLATION_ID` — installation ID

### GitHub Webhook Setup

1. Go to your repo → Settings → Webhooks → Add webhook
2. Payload URL: `https://your-ngrok.ngrok-free.app/github`
3. Content type: `application/json`
4. Secret: paste your `webhook_secret`
5. Events: Pull requests, Pull request reviews, Issue comments, Issues, Workflow runs

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
