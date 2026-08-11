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

class TestMentionDetection < Minitest::Test
  def test_configured_rejects_empty_string_app_id
    # Set up config with empty app ID
    config_path = File.join(TEST_BRAINIAC_DIR, "github.json")
    config = {
      "webhook_secret" => "test-secret-123",
      "apps" => {
        "avon" => { "id" => "", "private_key_path" => "/tmp/fake.pem", "installations" => { "stowzilla" => "12345" } }
      }
    }
    File.write(config_path, JSON.generate(config))
    Brainiac::Plugins::Github::Config.load!

    refute Brainiac::Plugins::Github::AppClient.configured?("avon")
  ensure
    File.write(config_path, JSON.generate({ "webhook_secret" => "test-secret-123", "repos" => {} }))
    Brainiac::Plugins::Github::Config.load!
  end

  def test_configured_rejects_empty_installation_id
    config_path = File.join(TEST_BRAINIAC_DIR, "github.json")
    config = {
      "webhook_secret" => "test-secret-123",
      "apps" => {
        "avon" => { "id" => "12345", "private_key_path" => "/tmp/fake.pem", "installations" => { "stowzilla" => "" } }
      }
    }
    File.write(config_path, JSON.generate(config))
    Brainiac::Plugins::Github::Config.load!

    refute Brainiac::Plugins::Github::AppClient.configured?("avon")
  ensure
    File.write(config_path, JSON.generate({ "webhook_secret" => "test-secret-123", "repos" => {} }))
    Brainiac::Plugins::Github::Config.load!
  end

  def test_mention_detection_in_comment_body
    assert_equal "Robin", detect_mentioned_agent("@Robin please review this PR")
    assert_equal "Sherlock", detect_mentioned_agent("@Sherlock what do you think?")
    assert_nil detect_mentioned_agent("This looks good, no mentions here")
  end
end
