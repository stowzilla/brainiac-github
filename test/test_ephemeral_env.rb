# frozen_string_literal: true

require_relative "test_helper"
require "securerandom"

# Stubs for brainiac-core Belt helpers. GitHub tests don't load belt.rb.
module BeltConfig
  class << self
    attr_accessor :tracked, :epic_envs

    def reset!
      @tracked = []
      @epic_envs = {}
    end

    def ephemeral_env_for_card(number) = "fizzy-#{number}"
    def ephemeral_env?(name) = Array(@tracked).include?(name)

    # Register an epic env for the branch/PR lookups. Mirrors the core
    # BeltConfig.epic_env_for_branch / epic_env_for_pr contract:
    # returns [env_name, entry] on match, nil otherwise.
    def track_epic_env(env_name, entry)
      @epic_envs ||= {}
      @epic_envs[env_name] = entry
    end

    def epic_env_for_branch(branch)
      return nil if branch.nil? || branch.empty?

      Array(@epic_envs).find { |_name, entry| entry["epic_branch"] == branch }
    end

    def epic_env_for_pr(pr_url)
      return nil if pr_url.nil? || pr_url.empty?

      Array(@epic_envs).find { |_name, entry| entry["epic_pr"] == pr_url }
    end
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

    attr_reader :frontend_only_args

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

# maybe_redeploy_epic_ephemeral_env — the epic auto-deploy path.
#
# Epic envs aren't keyed by card number; they're tracked with epic_branch /
# epic_pr fields. Two triggers redeploy them:
#   #1 push/synchronize on the epic PR's *head* branch  -> match by `branch:`
#   #2 a child PR merging *into* the epic branch          -> match by `base_branch:`
#
# Both resolve the env via BeltConfig.epic_env_for_branch, verify the worktree
# is a configured Belt app, pull, then deploy.
class TestEpicEphemeralRedeploy < Minitest::Test
  EPIC_BRANCH = "epic/feature-parity-ux-platform-improvements"
  EPIC_PR = "https://github.com/stowzilla/feature_parity/pull/86"

  def setup
    BeltConfig.reset!
    BeltEnvironment.reset!
    @worktree = Dir.mktmpdir("gh-epic-wt")
    FileUtils.mkdir_p(File.join(@worktree, "config"))
    File.write(File.join(@worktree, "config/routes.rb"), "app.get '/x'\n")
  end

  def teardown
    FileUtils.rm_rf(@worktree)
  end

  # Register a tracked epic env pointing at the temp worktree, with the
  # infrastructure/<env>/ dir present so ephemeral_env_present? returns true.
  def track_epic(env_name: "epic-fp-ux", worktree: @worktree, configured: true)
    FileUtils.mkdir_p(File.join(worktree, "infrastructure", env_name)) if configured && worktree
    BeltConfig.track_epic_env(env_name, {
                                "status" => "active",
                                "epic_branch" => EPIC_BRANCH,
                                "epic_pr" => EPIC_PR,
                                "worktree" => worktree
                              })
  end

  def redeploy(branch: nil, base_branch: nil)
    # The handler shells out to `git pull --ff-only` in the worktree; capture the
    # subprocess stdio so a bare temp dir doesn't spew git fatals into test output.
    result = nil
    capture_subprocess_io do
      result = Brainiac::Plugins::Github::Handler.send(
        :maybe_redeploy_epic_ephemeral_env, branch: branch, base_branch: base_branch
      )
    end
    result
  end

  # --- Trigger #1: push/synchronize on the epic head branch ---

  def test_sync_on_epic_branch_redeploys
    track_epic

    result = redeploy(branch: EPIC_BRANCH)

    assert result
    assert BeltEnvironment.deployed
    assert_equal "epic-fp-ux", BeltEnvironment.deploy_calls.first[:env_name]
    assert_equal @worktree, BeltEnvironment.deploy_calls.first[:worktree]
  end

  # --- Trigger #2: child PR merging into the epic branch (base match) ---

  def test_merge_into_epic_branch_redeploys
    track_epic

    result = redeploy(base_branch: EPIC_BRANCH)

    assert result
    assert BeltEnvironment.deployed
    assert_equal "epic-fp-ux", BeltEnvironment.deploy_calls.first[:env_name]
  end

  def test_head_branch_wins_over_base_when_both_match
    # If both branch and base_branch would resolve, the head branch (Trigger #1)
    # is tried first. Only one deploy should fire.
    track_epic

    redeploy(branch: EPIC_BRANCH, base_branch: EPIC_BRANCH)

    assert_equal 1, BeltEnvironment.deploy_calls.size
  end

  # --- Non-epic / no-match cases ---

  def test_no_redeploy_when_branch_is_not_an_epic
    track_epic

    result = redeploy(branch: "fizzy-1299-some-card")

    refute result
    refute BeltEnvironment.deployed
  end

  def test_no_redeploy_when_no_epic_env_tracked
    # Nothing registered — branch matches nothing.
    result = redeploy(branch: EPIC_BRANCH)

    refute result
    refute BeltEnvironment.deployed
  end

  def test_no_redeploy_when_branch_and_base_both_nil
    track_epic

    result = redeploy(branch: nil, base_branch: nil)

    refute result
    refute BeltEnvironment.deployed
  end

  # --- Guard rails: worktree / belt app / configured env ---

  def test_no_redeploy_when_worktree_missing
    missing = File.join(Dir.tmpdir, "does-not-exist-#{SecureRandom.hex(4)}")
    BeltConfig.track_epic_env("epic-fp-ux", {
                                "status" => "active",
                                "epic_branch" => EPIC_BRANCH,
                                "epic_pr" => EPIC_PR,
                                "worktree" => missing
                              })

    result = redeploy(branch: EPIC_BRANCH)

    refute result
    refute BeltEnvironment.deployed
  end

  def test_no_redeploy_when_worktree_nil
    BeltConfig.track_epic_env("epic-fp-ux", {
                                "status" => "active",
                                "epic_branch" => EPIC_BRANCH,
                                "worktree" => nil
                              })

    result = redeploy(branch: EPIC_BRANCH)

    refute result
    refute BeltEnvironment.deployed
  end

  def test_no_redeploy_when_not_a_belt_app
    track_epic
    BeltEnvironment.belt_app = false

    result = redeploy(branch: EPIC_BRANCH)

    refute result
    refute BeltEnvironment.deployed
  end

  def test_no_redeploy_when_env_not_configured_in_worktree
    # Worktree is a belt app but has no infrastructure/<env>/ and isn't tracked.
    track_epic(configured: false)

    result = redeploy(branch: EPIC_BRANCH)

    refute result
    refute BeltEnvironment.deployed
  end

  def test_redeploy_when_env_tracked_even_without_infra_dir
    # ephemeral_env_present? falls back to BeltConfig.ephemeral_env? tracking.
    track_epic(configured: false)
    BeltConfig.tracked = ["epic-fp-ux"]

    result = redeploy(branch: EPIC_BRANCH)

    assert result
    assert BeltEnvironment.deployed
  end

  # --- Deploy detail ---

  def test_frontend_only_flag_is_passed_through_from_diff_check
    # Stub reports frontend_only? false by default; the deploy call should carry
    # whatever frontend_only_changes? returned.
    track_epic

    redeploy(branch: EPIC_BRANCH)

    refute BeltEnvironment.deploy_calls.first[:frontend_only]
  end

  def test_returns_boolean_true_not_deploy_result
    # The method returns true once a redeploy is attempted, regardless of the
    # deploy helper's own return value.
    track_epic

    assert_equal true, redeploy(branch: EPIC_BRANCH)
  end
end
