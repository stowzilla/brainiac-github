# frozen_string_literal: true

require_relative "test_helper"

# Stubs for brainiac-core Belt helpers. GitHub tests don't load belt.rb.
module BeltConfig
  class << self
    attr_accessor :tracked

    def reset!
      @tracked = []
    end

    def ephemeral_env_for_card(number) = "fizzy-#{number}"
    def ephemeral_env?(name) = Array(@tracked).include?(name)
  end
end

module BeltEnvironment
  class << self
    attr_accessor :deployed, :destroyed, :deploy_calls, :destroy_calls, :belt_app, :configured_envs

    def reset!
      @deployed = false
      @destroyed = false
      @deploy_calls = []
      @destroy_calls = []
      @belt_app = true
      @configured_envs = []
      @frontend_only_args = nil
    end

    def belt_app?(_path) = @belt_app != false

    def environment_configured?(worktree:, env_name:)
      return false unless worktree && env_name && File.directory?(worktree)

      File.directory?(File.join(worktree, "infrastructure", env_name.to_s)) ||
        Array(@configured_envs).include?(env_name)
    end

    def frontend_only_changes?(**kwargs)
      @frontend_only_args = kwargs
      false
    end

    def frontend_only_args
      @frontend_only_args
    end

    def deploy(worktree:, env_name:, frontend_only: false)
      @deploy_calls << { worktree: worktree, env_name: env_name, frontend_only: frontend_only }
      @deployed = true
      true
    end

    def destroy_environment(worktree:, env_name:)
      @destroy_calls << { worktree: worktree, env_name: env_name }
      @destroyed = true
      true
    end
  end
end

class TestEphemeralBeltEnvLifecycle < Minitest::Test
  def setup
    BeltConfig.reset!
    BeltEnvironment.reset!
    @worktree = Dir.mktmpdir("gh-ephemeral-wt")
    FileUtils.mkdir_p(File.join(@worktree, "config"))
    File.write(File.join(@worktree, "config/routes.rb"), "app.get '/x'\n")
  end

  def teardown
    FileUtils.rm_rf(@worktree)
  end

  def test_handler_does_not_define_belt_app
    refute_respond_to Brainiac::Plugins::Github::Handler, :belt_app?
    assert_respond_to BeltEnvironment, :belt_app?
  end

  def test_redeploy_uses_belt_environment_belt_app
    FileUtils.mkdir_p(File.join(@worktree, "infrastructure", "fizzy-1299"))

    result = redeploy(1299)

    assert result
    assert BeltEnvironment.deployed
    assert_equal "fizzy-1299", BeltEnvironment.deploy_calls.first[:env_name]
  end

  def test_redeploy_skips_when_not_belt_app
    FileUtils.mkdir_p(File.join(@worktree, "infrastructure", "fizzy-1299"))
    BeltEnvironment.belt_app = false

    result = redeploy(1299)

    refute result
    refute BeltEnvironment.deployed
  end

  def test_redeploy_when_env_in_worktree_even_if_untracked
    FileUtils.mkdir_p(File.join(@worktree, "infrastructure", "fizzy-1299"))

    result = redeploy(1299)

    assert result
    assert BeltEnvironment.deployed
  end

  def test_redeploy_when_tracked_but_worktree_dir_missing
    BeltConfig.tracked = ["fizzy-1299"]

    result = redeploy(1299)

    assert result
    assert BeltEnvironment.deployed
  end

  def test_redeploy_skips_when_env_missing
    result = redeploy(1299)

    refute result
    refute BeltEnvironment.deployed
  end

  def test_redeploy_passes_pr_base_branch
    FileUtils.mkdir_p(File.join(@worktree, "infrastructure", "fizzy-1299"))

    redeploy(1299, base_branch: "master")

    assert_equal "master", BeltEnvironment.frontend_only_args[:base_branch]
  end

  def test_destroy_when_env_in_worktree
    FileUtils.mkdir_p(File.join(@worktree, "infrastructure", "fizzy-1299"))

    destroy_env(1299)

    assert BeltEnvironment.destroyed
    assert_equal "fizzy-1299", BeltEnvironment.destroy_calls.first[:env_name]
  end

  def test_destroy_skips_when_env_missing
    destroy_env(1299)

    refute BeltEnvironment.destroyed
  end

  private

  def redeploy(card_number, base_branch: nil)
    Brainiac::Plugins::Github::Handler.send(
      :maybe_redeploy_ephemeral_belt_env,
      card_info: { "worktree" => @worktree }, card_number: card_number, worktree: @worktree,
      base_branch: base_branch
    )
  end

  def destroy_env(card_number)
    Brainiac::Plugins::Github::Handler.send(
      :maybe_destroy_ephemeral_belt_env,
      card_info: { "worktree" => @worktree }, card_number: card_number, project_key: "feature-parity"
    )
  end
end
