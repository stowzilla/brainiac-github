# frozen_string_literal: true

require_relative "lib/brainiac/plugins/github/version"

Gem::Specification.new do |s|
  s.name        = "brainiac-github"
  s.version     = Brainiac::Plugins::Github::VERSION
  s.summary     = "GitHub webhook plugin for Brainiac"
  s.description = "Full GitHub integration for Brainiac — PR reviews, PR comments, PR merges, " \
                  "CI workflow notifications, and issue tracking. Uses Brainiac's hook system for " \
                  "lifecycle integration (PR merge → work item close, deploy → card close)."
  s.authors     = ["Andy Davis"]
  s.homepage    = "https://github.com/stowzilla/brainiac-github"
  s.license     = "MIT"
  s.required_ruby_version = ">= 3.4"

  s.files = Dir["lib/**/*.rb", "templates/**/*", "README.md", "LICENSE"]
  s.require_paths = ["lib"]

  s.add_dependency "brainiac", ">= 0.0.14"
  s.add_dependency "jwt", "~> 2.9"

  s.add_development_dependency "minitest", "~> 5.25"
  s.add_development_dependency "rake", "~> 13.0"
  s.add_development_dependency "rubocop", "~> 1.75"
  s.add_development_dependency "rubocop-performance", "~> 1.25"

  s.metadata["rubygems_mfa_required"] = "true"
end
