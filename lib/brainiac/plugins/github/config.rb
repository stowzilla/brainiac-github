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
            LOG.info "[GitHub] Reloaded configuration"
          end

          def webhook_secret
            @config["webhook_secret"] || ENV.fetch("GITHUB_WEBHOOK_SECRET", nil)
          end

          private

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
