# frozen_string_literal: true

require_relative "test_helper"

class TestGithubPlugin < Minitest::Test
  def test_register_method_exists
    assert_respond_to Brainiac::Plugins::Github, :register
  end

  def test_version_format
    version = Brainiac::Plugins::Github::VERSION
    assert_match(/\A\d+\.\d+\.\d+\z/, version)
  end

  def test_config_loads
    config = Brainiac::Plugins::Github::Config.config
    assert_kind_of Hash, config
    assert_equal "test-secret-123", config["webhook_secret"]
  end

  def test_webhook_secret
    assert_equal "test-secret-123", Brainiac::Plugins::Github::Config.webhook_secret
  end

  def test_prompts_defined
    assert_kind_of String, Brainiac::Plugins::Github::Prompts::CHANNEL
    assert_kind_of String, Brainiac::Plugins::Github::Prompts::PR_COMMENT
    assert_kind_of String, Brainiac::Plugins::Github::Prompts::PR_REVIEW
    assert_kind_of String, Brainiac::Plugins::Github::Prompts::UAT
  end

  def test_channel_prompt_includes_formatting_rules
    assert_includes Brainiac::Plugins::Github::Prompts::CHANNEL, "GitHub-Flavored Markdown"
  end

  def test_configured_returns_true_with_secret
    assert Brainiac::Plugins::Github.configured?
  end

  def test_help_text
    assert_includes Brainiac::Plugins::Github.help_text, "brainiac github"
  end

  def test_completions
    completions = Brainiac::Plugins::Github.completions
    assert_includes completions, "setup"
    assert_includes completions, "config"
    assert_includes completions, "status"
  end

  def test_handle_issue_opened
    payload = {
      "issue" => { "html_url" => "https://github.com/test/1", "title" => "Bug", "number" => 1 },
      "repository" => { "full_name" => "stowzilla/marketplace" }
    }
    status, body = Brainiac::Plugins::Github::Handler.handle_issue_opened(payload)
    assert_equal 200, status
    parsed = JSON.parse(body)
    assert_equal "logged", parsed["status"]
    assert_equal 1, parsed["issue"]
  end

  def test_handle_pr_merged_no_project
    payload = {
      "pull_request" => { "head" => { "ref" => "feature-x" }, "base" => { "ref" => "main" },
                          "html_url" => "https://github.com/x/1", "title" => "Fix" },
      "repository" => { "full_name" => "unknown/repo", "default_branch" => "main" }
    }
    status, body = Brainiac::Plugins::Github::Handler.handle_pr_merged(payload)
    assert_equal 200, status
    assert_includes body, "no matching project"
  end

  def test_handle_pr_merged_wrong_branch
    payload = {
      "pull_request" => { "head" => { "ref" => "feature-x" }, "base" => { "ref" => "develop" },
                          "html_url" => "https://github.com/x/1", "title" => "Fix" },
      "repository" => { "full_name" => "stowzilla/marketplace", "default_branch" => "main" }
    }
    status, body = Brainiac::Plugins::Github::Handler.handle_pr_merged(payload)
    assert_equal 200, status
    assert_includes body, "not merged into main"
  end
end
