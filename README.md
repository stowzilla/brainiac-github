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
  "repos": {}
}
```

Generate a webhook secret:

```bash
ruby -rsecurerandom -e 'puts SecureRandom.hex(20)'
```

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
