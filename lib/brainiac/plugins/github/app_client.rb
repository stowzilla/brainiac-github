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
      # Falls back to `gh` CLI when app credentials are not configured.
      module AppClient
        GITHUB_API = "https://api.github.com"
        TOKEN_EXPIRY_BUFFER = 60 # refresh token 60s before expiry

        @token = nil
        @token_expires_at = nil
        @mutex = Mutex.new

        class << self
          # Returns true if GitHub App credentials are fully configured.
          def configured?
            !!(Config.app_id && Config.private_key_path && Config.installation_id)
          end

          # POST a comment on an issue or PR.
          #
          # @param repo [String] "owner/repo"
          # @param pr_number [Integer]
          # @param body [String] comment markdown
          # @return [Hash] parsed response
          def create_comment(repo, pr_number, body)
            post("/repos/#{repo}/issues/#{pr_number}/comments", { body: body })
          end

          # POST a reaction on an issue comment.
          #
          # @param repo [String] "owner/repo"
          # @param comment_id [Integer]
          # @param reaction [String] e.g. "eyes", "+1", "rocket"
          # @return [Hash] parsed response
          def create_comment_reaction(repo, comment_id, reaction)
            post("/repos/#{repo}/issues/comments/#{comment_id}/reactions", { content: reaction })
          end

          # POST a reaction on a PR review.
          #
          # @param repo [String] "owner/repo"
          # @param review_id [Integer]
          # @param reaction [String]
          # @return [Hash] parsed response
          def create_review_reaction(repo, review_id, reaction)
            post("/repos/#{repo}/pulls/reviews/#{review_id}/reactions", { content: reaction })
          end

          # GET request to GitHub API.
          #
          # @param path [String] API path (e.g. "/repos/owner/repo/pulls/1")
          # @return [Hash] parsed response
          def get(path)
            request(:get, path)
          end

          # POST request to GitHub API.
          #
          # @param path [String] API path
          # @param body [Hash] request body
          # @return [Hash] parsed response
          def post(path, body)
            request(:post, path, body)
          end

          # Reset cached token (useful for testing or when credentials change).
          def reset!
            @mutex.synchronize do
              @token = nil
              @token_expires_at = nil
            end
          end

          private

          def request(method, path, body = nil)
            token = installation_token
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

          # Generate a short-lived JWT signed with the App's private key.
          # Used to request an installation access token.
          def generate_jwt
            private_key = OpenSSL::PKey::RSA.new(File.read(Config.private_key_path))
            now = Time.now.to_i

            payload = {
              iat: now - 60, # issued at (60s clock drift allowance)
              exp: now + (10 * 60), # expires in 10 minutes (max allowed)
              iss: Config.app_id
            }

            JWT.encode(payload, private_key, "RS256")
          end

          # Fetch or return a cached installation access token.
          # Tokens are valid for 1 hour; we refresh 60s early.
          def installation_token
            @mutex.synchronize do
              return @token if @token && @token_expires_at && Time.now.to_i < @token_expires_at

              jwt = generate_jwt
              uri = URI("#{GITHUB_API}/app/installations/#{Config.installation_id}/access_tokens")

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
              @token = data["token"]
              # Parse expiry, subtract buffer
              expires_at = Time.parse(data["expires_at"]).to_i
              @token_expires_at = expires_at - TOKEN_EXPIRY_BUFFER
              @token
            end
          end
        end
      end
    end
  end
end
