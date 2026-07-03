# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "fileutils"
require "tmpdir"
require "open3"
require "openssl"
require "rack/utils"

# --- Stub core constants and functions that the plugin expects ---

TEST_BRAINIAC_DIR = Dir.mktmpdir("brainiac-github-test")

BRAINIAC_DIR = TEST_BRAINIAC_DIR unless defined?(BRAINIAC_DIR)
ENV["BRAINIAC_DIR"] = TEST_BRAINIAC_DIR

unless defined?(LOG)
  LOG = Class.new do
    def info(_msg) = nil
    def warn(_msg) = nil
    def error(_msg) = nil
    def debug(_msg) = nil
    def debug? = false
  end.new
end

AI_AGENT_NAME = "Galen" unless defined?(AI_AGENT_NAME)

# Stub core Brainiac module with hooks
module Brainiac
  @hooks = Hash.new { |h, k| h[k] = [] }
  @channel_prompts = {}
  @channel_pre_post_checks = {}

  class << self
    def on(event, &block) = @hooks[event] << block

    def emit(event, **ctx)
      @hooks[event].filter_map do |h|
        h.call(ctx)
      rescue StandardError
        nil
      end
    end

    def register_channel_prompt(channel, prompt, pre_post_check: nil)
      @channel_prompts[channel] = prompt
      @channel_pre_post_checks[channel] = pre_post_check if pre_post_check
    end
    attr_reader :hooks, :channel_prompts, :channel_pre_post_checks

    def reset_hooks!
      @hooks = Hash.new { |h, k| h[k] = [] }
      @channel_prompts = {}
      @channel_pre_post_checks = {}
    end
  end

  module Plugins; end
end

# Stub core constants
AGENT_REGISTRY = {
  "galen" => { "display_name" => "Galen", "local" => true, "env" => { "FIZZY_TOKEN" => "tok_galen" } },
  "glados" => { "display_name" => "GLaDOS", "local" => true, "env" => {} }
}.freeze

PROJECTS = {
  "marketplace" => { "repo_path" => "/tmp/test-repo", "tags" => %w[marketplace mp],
                     "github_repo" => "stowzilla/marketplace",
                     "allowed_models" => { "opus" => "claude-opus-4.6" } },
  "brainiac" => { "repo_path" => "/tmp/test-brainiac", "tags" => ["brainiac"],
                  "github_repo" => "stowzilla/brainiac" }
}.freeze

# Stub core functions
def identify_project_by_repo(repo_name)
  PROJECTS.find { |_k, v| v["github_repo"] == repo_name }
end

def find_work_item_by_branch(_branch) = nil
def load_work_item_map = {}
def save_work_item_map(_map) = nil
def mark_work_item_merged(_num) = nil
def cleanup_work_item_worktrees(_num, **) = nil
def session_active?(_key) = false
def register_session(_key, _pid, **) = nil
def agent_name_for(_config) = "Galen"
def render_prompt(_template, _vars, brain_context: "", agent_name: nil, channel: :github) = "rendered prompt"
def build_brain_context(agent_name:, card_number: nil, project_key: nil, comment_body: nil) = ""
def detect_model(_config, text: "") = nil
def detect_effort(_config, text: "") = nil
def run_agent(_prompt, **) = [12_345, "/tmp/test.log"]
def run_cmd(*_cmd, chdir:, env: {}) = ""
def reload_projects! = nil
def reload_agent_registry!(**) = nil
def send_notification(_type, _msg, **) = nil

# Write github.json for tests
github_config = { "webhook_secret" => "test-secret-123", "repos" => {} }
File.write(File.join(TEST_BRAINIAC_DIR, "github.json"), JSON.generate(github_config))

require_relative "../lib/brainiac_github"

# Load config
Brainiac::Plugins::Github::Config.load!

# Cleanup
Minitest.after_run { FileUtils.rm_rf(TEST_BRAINIAC_DIR) }
