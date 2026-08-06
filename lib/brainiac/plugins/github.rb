# frozen_string_literal: true

require_relative "github/version"
require_relative "github/metadata"
require_relative "github/cli"
require_relative "github/config"
require_relative "github/app_client"
require_relative "github/prompts"
require_relative "github/notifications"
require_relative "github/handler"

module Brainiac
  module Plugins
    module Github
      class << self
        # Called by Brainiac plugin system during server startup.
        #
        # @param app [Sinatra::Application] The running Brainiac server
        def register(app)
          Config.load!
          Brainiac.register_channel_prompt(:github, Prompts::CHANNEL, pre_post_check: Prompts::PRE_POST_CHECK)
          register_crash_handler!
          register_agent_lifecycle_hooks!
          setup_routes(app)
          LOG.info "[GitHub] Plugin registered (webhook: /github)"
        end

        # Called after `brainiac install github` — creates config from template.
        def post_install(brainiac_dir)
          config_file = File.join(brainiac_dir, "github.json")
          return if File.exist?(config_file)

          template = File.expand_path("../../../templates/github.json.example", __dir__)
          if File.exist?(template)
            FileUtils.cp(template, config_file)
          else
            default_config = { "webhook_secret" => "", "repos" => {} }
            File.write(config_file, JSON.pretty_generate(default_config))
          end
        end

        private

        def register_agent_lifecycle_hooks!
          Brainiac.on(:agent_added) do |ctx|
            Config.reload!
            LOG.info "[GitHub] Agent added: #{ctx[:display_name]} — config reloaded" if defined?(LOG)
          end

          Brainiac.on(:agent_removed) do |ctx|
            Config.reload!
            LOG.info "[GitHub] Agent removed: #{ctx[:agent_key]} — config reloaded" if defined?(LOG)
          end
        end

        def register_crash_handler!
          Brainiac.on(:agent_crashed) do |ctx|
            next unless ctx[:source] == :github

            source_context = ctx[:source_context] || {}
            pr_number = source_context[:pr_number]
            repo_name = source_context[:repo_name]
            next unless pr_number && repo_name

            work_dir = source_context[:work_dir] || Dir.pwd
            agent_display = ctx[:agent_name] || "Agent"
            snippet = ctx[:snippet]
            snippet_block = snippet ? "\n```\n#{snippet[-1500..]}\n```" : ""
            comment_body = "💥 **#{agent_display} crashed** (exit code #{ctx[:exit_status]})\n\nLog: `#{ctx[:log_file]}`#{snippet_block}"

            begin
              if AppClient.configured?
                AppClient.create_comment(repo_name, pr_number, comment_body)
              else
                run_cmd("gh", "pr", "comment", pr_number.to_s, "--repo", repo_name, "--body", comment_body, chdir: work_dir)
              end
              LOG.info "[GitHub] Posted crash comment on PR ##{pr_number}"
            rescue StandardError => e
              LOG.error "[GitHub] Failed to post crash comment: #{e.message}"
            end

            :github
          end
        end

        def setup_routes(app)
          app.post "/github" do
            content_type :json
            request.body.rewind
            payload_body = request.body.read

            Brainiac::Plugins::Github.verify_signature!(request, payload_body)

            payload = JSON.parse(payload_body)
            event = request.env["HTTP_X_GITHUB_EVENT"]

            reload_projects!
            reload_agent_registry!
            Brainiac::Plugins::Github::Config.reload!

            action = payload["action"]

            case event
            when "pull_request"
              status_code, body = case action
                                  when "closed"
                                    if payload.dig("pull_request", "merged")
                                      Handler.handle_pr_merged(payload)
                                    else
                                      [200, { status: "ignored", reason: "PR closed without merge" }.to_json]
                                    end
                                  when "opened"
                                    Handler.handle_pr_opened(payload)
                                  when "synchronize"
                                    Handler.handle_pr_synchronized(payload)
                                  else
                                    [200, { status: "ignored", reason: "pull_request action: #{action}" }.to_json]
                                  end
              halt status_code, body
            when "pull_request_review"
              if action == "submitted"
                status_code, body = Handler.handle_pr_review_submitted(payload)
                halt status_code, body
              else
                halt 200, { status: "ignored", reason: "pull_request_review action: #{action}" }.to_json
              end
            when "issue_comment"
              if action == "created"
                status_code, body = Handler.handle_issue_comment(payload)
                halt status_code, body
              else
                halt 200, { status: "ignored", reason: "issue_comment action: #{action}" }.to_json
              end
            when "issues"
              if action == "opened"
                status_code, body = Handler.handle_issue_opened(payload)
                halt status_code, body
              else
                halt 200, { status: "ignored", reason: "issues action: #{action}" }.to_json
              end
            when "workflow_run"
              if action == "completed"
                status_code, body = Handler.handle_workflow_run(payload)
                halt status_code, body
              else
                halt 200, { status: "ignored", reason: "workflow_run action: #{action}" }.to_json
              end
            when "ping"
              halt 200, { status: "pong" }.to_json
            else
              halt 200, { status: "ignored", event: event }.to_json
            end
          rescue JSON::ParserError => e
            LOG.error "Invalid JSON: #{e.message}"
            halt 400, { error: "Invalid JSON" }.to_json
          rescue StandardError => e
            LOG.error "Unhandled error: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
            halt 500, { error: e.message }.to_json
          end
        end
      end

      # Verify the X-Hub-Signature-256 header (HMAC-SHA256 of the raw body).
      def self.verify_signature!(request, payload_body)
        signature = request.env["HTTP_X_HUB_SIGNATURE_256"]
        halt 403, { error: "Missing GitHub signature" }.to_json unless signature
        secret = Config.webhook_secret
        halt 500, { error: "GitHub webhook secret not configured" }.to_json unless secret
        computed = "sha256=#{OpenSSL::HMAC.hexdigest("sha256", secret, payload_body)}"
        halt 403, { error: "Invalid GitHub signature" }.to_json unless Rack::Utils.secure_compare(signature, computed)
      end
    end
  end
end
