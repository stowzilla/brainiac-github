# frozen_string_literal: true

# Lightweight metadata for brainiac-github.
# Loaded by `brainiac help` without pulling in the full plugin runtime.

require_relative "version"

module Brainiac
  module Plugins
    module Github
      # Returns true if GitHub webhook secret is configured.
      def self.configured?
        config_file = File.join(ENV.fetch("BRAINIAC_DIR", File.join(Dir.home, ".brainiac")), "github.json")
        return false unless File.exist?(config_file)

        config = JSON.parse(File.read(config_file))
        !config["webhook_secret"].to_s.empty?
      rescue StandardError
        false
      end

      # Help text shown in `brainiac help` when the plugin is installed.
      def self.help_text
        "    brainiac github <command>     Manage GitHub webhooks (setup, config, status)"
      end
    end
  end
end
