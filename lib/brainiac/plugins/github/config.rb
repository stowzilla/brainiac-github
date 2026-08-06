# frozen_string_literal: true

module Brainiac
  module Plugins
    module Github
      module Config
        CONFIG_FILE = File.join(ENV.fetch("BRAINIAC_DIR", File.join(Dir.home, ".brainiac")), "github.json")

        @config = {}
        @last_mtime = nil

        class << self
          attr_reader :config

          def load!
            @config = load_config
            @last_mtime = File.exist?(CONFIG_FILE) ? File.mtime(CONFIG_FILE) : nil
          end

          def reload!
            return unless file_changed?

            @config = load_config
            @last_mtime = File.exist?(CONFIG_FILE) ? File.mtime(CONFIG_FILE) : nil
            AppClient.reset! if defined?(AppClient)
            LOG.info "[GitHub] Reloaded configuration"
          end

          def webhook_secret
            @config["webhook_secret"] || ENV.fetch("GITHUB_WEBHOOK_SECRET", nil)
          end

          # Per-agent app credentials from the "apps" hash.
          # Falls back to the shared "app" config if no per-agent entry exists.

          def app_id(agent_key = nil)
            per_agent_value(agent_key, "id") ||
              @config.dig("app", "id")&.to_s ||
              ENV.fetch("GITHUB_APP_ID", nil)
          end

          def private_key_path(agent_key = nil)
            path = per_agent_value(agent_key, "private_key_path") ||
                   @config.dig("app", "private_key_path") ||
                   ENV.fetch("GITHUB_APP_PRIVATE_KEY_PATH", nil)
            return nil unless path

            expanded = File.expand_path(path)
            File.exist?(expanded) ? expanded : nil
          end

          def installation_id(agent_key = nil, repo_owner: nil)
            # Check per-agent config first
            if agent_key
              agent_conf = @config.dig("apps", agent_key)
              if agent_conf
                # Per-agent may have multiple installations keyed by owner
                if repo_owner && agent_conf["installations"]
                  return agent_conf.dig("installations", repo_owner)&.to_s || agent_conf["installation_id"]&.to_s
                end

                return agent_conf["installation_id"]&.to_s if agent_conf["installation_id"]
              end
            end

            # Shared app config — check installations hash first, then flat installation_id
            if repo_owner && @config.dig("app", "installations")
              found = @config.dig("app", "installations", repo_owner)&.to_s
              return found if found
            end

            @config.dig("app", "installation_id")&.to_s ||
              ENV.fetch("GITHUB_APP_INSTALLATION_ID", nil)
          end

          # Returns the agent key that should be used for a given context.
          # If per-agent apps are configured and the agent has an entry, returns that key.
          # Otherwise returns nil (use shared app).
          def agent_app_configured?(agent_key)
            return false unless agent_key

            !!@config.dig("apps", agent_key)
          end

          private

          def per_agent_value(agent_key, field)
            return nil unless agent_key

            @config.dig("apps", agent_key, field)&.to_s
          end

          def load_config
            return {} unless File.exist?(CONFIG_FILE)

            JSON.parse(File.read(CONFIG_FILE))
          rescue JSON::ParserError => e
            LOG.error "[GitHub] Failed to parse config: #{e.message}"
            {}
          end

          def file_changed?
            return false unless File.exist?(CONFIG_FILE)

            current_mtime = File.mtime(CONFIG_FILE)
            return false if @last_mtime && current_mtime == @last_mtime

            @last_mtime = current_mtime
            true
          end
        end
      end
    end
  end
end
