# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "openssl"
require "jwt"
require "time"

module Brainiac
  module Plugins
    module Github
      # HTTP client that authenticates as a GitHub App (installation).
      #
      # When app credentials are configured (app_id + private_key_path + installation_id),
      # API calls are made as the App's bot user — so PR comments, reactions, etc.
      # appear with the App's identity rather than a personal user.
      #
      # Supports per-agent apps: if "apps" hash in config has an entry for the agent,
      # that agent's app credentials are used (separate avatar/identity per agent).
      # Falls back to shared "app" config, then to `gh` CLI.
      module AppClient
        GITHUB_API = "https://api.github.com"
        TOKEN_EXPIRY_BUFFER = 60 # refresh token 60s before expiry

        # Per-agent token cache: { agent_key_or_nil => { token:, expires_at: } }
        @tokens = {}
        @mutex = Mutex.new

        class << self
          # Returns true if GitHub App credentials are fully configured.
          # Checks per-agent first, then shared app config.
          # Guards against empty-string values (common in template configs).
          def configured?(agent_key = nil)
            id = Config.app_id(agent_key)
            key_path = Config.private_key_path(agent_key)
            inst_id = Config.installation_id(agent_key)

            !!(id && !id.empty? && key_path && inst_id && !inst_id.empty?)
          end

          # POST a comment on an issue or PR.
          #
          # @param repo [String] "owner/repo"
          # @param pr_number [Integer]
          # @param body [String] comment markdown
          # @param agent_key [String, nil] agent key for per-agent app identity
          # @return [Hash] parsed response
          def create_comment(repo, pr_number, body, agent_key: nil)
            post("/repos/#{repo}/issues/#{pr_number}/comments", { body: body }, agent_key: agent_key)
          end

          # POST a reaction on an issue comment.
          #
          # @param repo [String] "owner/repo"
          # @param comment_id [Integer]
          # @param reaction [String] e.g. "eyes", "+1", "rocket"
          # @param agent_key [String, nil] agent key for per-agent app identity
          # @return [Hash] parsed response
          def create_comment_reaction(repo, comment_id, reaction, agent_key: nil)
            post("/repos/#{repo}/issues/comments/#{comment_id}/reactions", { content: reaction }, agent_key: agent_key)
          end

          # POST a reaction on a PR review.
          #
          # @param repo [String] "owner/repo"
          # @param review_id [Integer]
          # @param reaction [String]
          # @param agent_key [String, nil] agent key for per-agent app identity
          # @return [Hash] parsed response
          def create_review_reaction(repo, review_id, reaction, agent_key: nil)
            post("/repos/#{repo}/pulls/reviews/#{review_id}/reactions", { content: reaction }, agent_key: agent_key)
          end

          # GET request to GitHub API.
          #
          # @param path [String] API path (e.g. "/repos/owner/repo/pulls/1")
          # @param agent_key [String, nil] agent key for per-agent app identity
          # @return [Hash] parsed response
          def get(path, agent_key: nil)
            request(:get, path, agent_key: agent_key)
          end

          # POST request to GitHub API.
          #
          # @param path [String] API path
          # @param body [Hash] request body
          # @param agent_key [String, nil] agent key for per-agent app identity
          # @return [Hash] parsed response
          def post(path, body, agent_key: nil)
            request(:post, path, body, agent_key: agent_key)
          end

          # Reset cached tokens (useful for testing or when credentials change).
          def reset!
            @mutex.synchronize do
              @tokens = {}
            end
          end

          # Public accessor for installation tokens (used to inject GH_TOKEN into agent env).
          # Returns the raw token string, or nil on failure.
          def installation_token_for(agent_key = nil, repo_owner: nil)
            installation_token(agent_key, repo_owner: repo_owner)
          rescue StandardError
            nil
          end

          private

          def request(method, path, body = nil, agent_key: nil)
            repo_owner = extract_repo_owner(path)
            token = installation_token(agent_key, repo_owner: repo_owner)
            uri = URI("#{GITHUB_API}#{path}")

            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true
            http.open_timeout = 10
            http.read_timeout = 30

            req = case method
                  when :get
                    Net::HTTP::Get.new(uri.request_uri)
                  when :post
                    Net::HTTP::Post.new(uri.request_uri)
                  end

            req["Authorization"] = "Bearer #{token}"
            req["Accept"] = "application/vnd.github+json"
            req["X-GitHub-Api-Version"] = "2022-11-28"
            req["User-Agent"] = "Brainiac-GitHub-App"
            req.body = JSON.generate(body) if body
            req.content_type = "application/json" if body

            response = http.request(req)

            raise "GitHub API error #{response.code}: #{response.body}" unless response.is_a?(Net::HTTPSuccess)

            JSON.parse(response.body)
          end

          # Extract the repo owner from an API path like "/repos/stowzilla/brainiac/pulls/1"
          def extract_repo_owner(path)
            match = path.match(%r{^/repos/([^/]+)/})
            match&.[](1)
          end

          # Generate a short-lived JWT signed with the App's private key.
          # Used to request an installation access token.
          def generate_jwt(agent_key = nil)
            private_key = OpenSSL::PKey::RSA.new(File.read(Config.private_key_path(agent_key)))
            now = Time.now.to_i

            payload = {
              iat: now - 60, # issued at (60s clock drift allowance)
              exp: now + (10 * 60), # expires in 10 minutes (max allowed)
              iss: Config.app_id(agent_key)
            }

            JWT.encode(payload, private_key, "RS256")
          end

          # Fetch or return a cached installation access token.
          # Tokens are valid for 1 hour; we refresh 60s early.
          # Cache key includes agent_key and repo_owner for proper scoping.
          def installation_token(agent_key = nil, repo_owner: nil)
            inst_id = Config.installation_id(agent_key, repo_owner: repo_owner)
            raise "No installation ID configured#{" for #{repo_owner}" if repo_owner}" unless inst_id

            cache_key = "#{agent_key || "shared"}-#{inst_id}"

            @mutex.synchronize do
              cached = @tokens[cache_key]
              return cached[:token] if cached && Time.now.to_i < cached[:expires_at]

              jwt = generate_jwt(agent_key)
              uri = URI("#{GITHUB_API}/app/installations/#{inst_id}/access_tokens")

              http = Net::HTTP.new(uri.host, uri.port)
              http.use_ssl = true
              http.open_timeout = 10
              http.read_timeout = 30

              req = Net::HTTP::Post.new(uri.request_uri)
              req["Authorization"] = "Bearer #{jwt}"
              req["Accept"] = "application/vnd.github+json"
              req["X-GitHub-Api-Version"] = "2022-11-28"
              req["User-Agent"] = "Brainiac-GitHub-App"

              response = http.request(req)

              raise "Failed to get installation token: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)

              data = JSON.parse(response.body)
              token = data["token"]
              expires_at = Time.parse(data["expires_at"]).to_i - TOKEN_EXPIRY_BUFFER

              @tokens[cache_key] = { token: token, expires_at: expires_at }
              token
            end
          end
        end
      end
    end
  end
end
