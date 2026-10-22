# frozen_string_literal: true

module Brainiac
  module Plugins
    module Github
      module Cli
        class << self
          def run(args)
            command = args.shift
            case command
            when "setup" then cmd_setup
            when "config" then cmd_config
            when "status" then cmd_status
            when "token" then cmd_token(args)
            else print_help
            end
          end

          private

          # Mint a fresh installation access token and print it to stdout.
          #
          # Designed for long-running agent sessions that outlive the one-hour
          # lifetime of the token baked in at spawn time. Call it right before a
          # GitHub operation:
          #
          #   export GH_TOKEN=$(brainiac github token --agent galen --owner stowzilla)
          #   gh pr create ...
          #
          # Resolution mirrors handler.rb#github_agent_env: try the agent's own
          # app first, fall back to the shared "brainiac" app. The --owner scopes
          # which installation (and thus which token) is minted.
          def cmd_token(args)
            opts = parse_token_args(args)
            Config.load!

            agent = opts[:agent]
            effective_agent = if agent && AppClient.configured?(agent)
                                agent
                              elsif AppClient.configured?("brainiac")
                                "brainiac"
                              end

            unless effective_agent
              warn "No GitHub App configured for agent #{agent.inspect} (and no shared 'brainiac' app fallback)."
              warn "Run: brainiac github config"
              exit 1
            end

            token = AppClient.installation_token_for(effective_agent, repo_owner: opts[:owner])
            unless token
              warn "Failed to mint installation token for agent #{effective_agent.inspect}" \
                   "#{" owner #{opts[:owner]}" if opts[:owner]}."
              warn "Check the private key path and installation ID with: brainiac github config"
              exit 1
            end

            # Token only — nothing else on stdout so `$(...)` capture stays clean.
            puts token
          end

          # Parse `--agent NAME` / `--owner OWNER` (and `=` forms) from token args.
          def parse_token_args(args)
            opts = { agent: nil, owner: nil }
            until args.empty?
              arg = args.shift
              case arg
              when "--agent", "-a" then opts[:agent] = args.shift
              when "--owner", "-o" then opts[:owner] = args.shift
              when /\A--agent=(.+)\z/ then opts[:agent] = Regexp.last_match(1)
              when /\A--owner=(.+)\z/ then opts[:owner] = Regexp.last_match(1)
              end
            end
            opts
          end

          def cmd_setup
            brainiac_dir = ENV.fetch("BRAINIAC_DIR", File.join(Dir.home, ".brainiac"))
            config_file = File.join(brainiac_dir, "github.json")

            if File.exist?(config_file)
              puts "GitHub config already exists at #{config_file}"
              return
            end

            template = File.expand_path("../../../../templates/github.json.example", __dir__)
            if File.exist?(template)
              FileUtils.cp(template, config_file)
              puts "Created #{config_file} from template"
            else
              default_config = { "webhook_secret" => "", "repos" => {} }
              File.write(config_file, JSON.pretty_generate(default_config))
              puts "Created #{config_file}"
            end

            puts "Edit the file to add your GitHub webhook secret."
            puts "Generate one with: ruby -rsecurerandom -e 'puts SecureRandom.hex(20)'"
          end

          def cmd_config
            brainiac_dir = ENV.fetch("BRAINIAC_DIR", File.join(Dir.home, ".brainiac"))
            config_file = File.join(brainiac_dir, "github.json")

            unless File.exist?(config_file)
              puts "No GitHub config found. Run: brainiac github setup"
              return
            end

            config = JSON.parse(File.read(config_file))
            secret = config["webhook_secret"]
            app_config = config["app"] || {}

            puts "GitHub Configuration:"
            puts "  Config file: #{config_file}"
            puts "  Webhook secret: #{secret && !secret.empty? ? "#{secret[0..5]}..." : "(not set)"}"
            puts "  Repos: #{config.fetch("repos", {}).keys.join(", ").then { |s| s.empty? ? "(none)" : s }}"
            puts ""
            puts "  App Authentication:"
            if app_config["id"] && !app_config["id"].to_s.empty?
              puts "    App ID: #{app_config["id"]}"
              puts "    Private key: #{app_config["private_key_path"] || "(not set)"}"
              puts "    Installation ID: #{app_config["installation_id"] || "(not set)"}"
              key_path = app_config["private_key_path"]
              if key_path && File.exist?(File.expand_path(key_path))
                puts "    Status: ✅ configured"
              else
                puts "    Status: ⚠️  private key file not found"
              end
            else
              puts "    Status: not configured (using gh CLI fallback)"
            end
          end

          def cmd_status
            require "net/http"
            uri = URI("http://localhost:4567/api/status")
            res = Net::HTTP.get_response(uri)
            if res.is_a?(Net::HTTPSuccess)
              puts "✅ Brainiac server is running — GitHub webhook endpoint active at POST /github"
            else
              puts "⚠️  Server returned #{res.code}"
            end
          rescue Errno::ECONNREFUSED
            puts "❌ Brainiac server is not running"
          end

          def print_help
            puts "Usage: brainiac github <command>"
            puts ""
            puts "Commands:"
            puts "  setup     Create GitHub config file (~/.brainiac/github.json)"
            puts "  config    Show current GitHub configuration"
            puts "  status    Check if GitHub webhook endpoint is active"
            puts "  token     Mint a fresh installation token (for export GH_TOKEN=$(...))"
            puts ""
            puts "Token options:"
            puts "  --agent, -a NAME   Agent key (falls back to shared 'brainiac' app)"
            puts "  --owner, -o OWNER  Repo owner to scope the installation (e.g. stowzilla)"
            puts ""
            puts "Example:"
            puts "  export GH_TOKEN=$(brainiac github token --agent galen --owner stowzilla)"
          end
        end
      end

      # Plugin CLI entry points
      def self.cli(args)
        Cli.run(args)
      end

      def self.completions
        %w[setup config status token]
      end
    end
  end
end
