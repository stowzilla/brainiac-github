# frozen_string_literal: true

require "cgi"
require "date"
require "json"
require "jwt"
require "net/http"
require "openssl"
require "securerandom"
require "socket"
require "uri"

module Brainiac
  module Plugins
    module Github
      # Provisions a GitHub App for a new brainiac agent (`brainiac agent create`
      # / `brainiac agent setup`) so its `gh pr create` runs as <agent>-brainiac[bot]
      # instead of whoever is logged in to `gh` on the box.
      #
      # GitHub has no API for creating apps outright, but the App Manifest flow
      # gets close: we serve a one-shot page on localhost that posts the manifest
      # to GitHub, the user clicks "Create GitHub App", and GitHub redirects back
      # with a code we exchange for the app ID and private key. The second click
      # is installing the app on each account. The logo can't be set by API.
      module AgentSetup
        GITHUB_API = "https://api.github.com"
        CALLBACK_TIMEOUT = 600 # seconds to wait for the browser round-trip

        # Same permissions as the hand-made agent apps: open PRs, comment, react,
        # read CI. No webhook — the shared brainiac app receives events.
        PERMISSIONS = {
          "contents" => "write",
          "issues" => "write",
          "pull_requests" => "write",
          "actions" => "read",
          "metadata" => "read"
        }.freeze

        DESCRIPTION_LIMIT = 400

        class << self
          def run(agent_key, entry)
            display_name = entry["display_name"] || agent_key.capitalize
            app = config.dig("apps", agent_key)

            if app && installations?(app)
              puts "  [GitHub] ✓ #{display_name} already has a GitHub App (skipping)"
              return
            end

            unless $stdin.tty?
              puts "  [GitHub] ✗ Creating a GitHub App needs a browser — re-run: brainiac agent setup #{agent_key}"
              return
            end

            app ||= create_app(agent_key, display_name, entry)
            return unless app

            install_app(agent_key, app, entry["open_browser"])
            print_logo_step(app, entry["avatar_path"])
          end

          private

          def create_app(agent_key, display_name, entry)
            state = SecureRandom.hex(16)
            server = TCPServer.new("127.0.0.1", 0)
            port = server.addr[1]
            start_url = "http://127.0.0.1:#{port}/"
            manifest = build_manifest(agent_key, display_name, entry["description"], "#{start_url}callback")

            puts ""
            puts "  [GitHub] Create #{display_name}'s GitHub App (one click):"
            puts "    #{start_url}"
            puts "    → review the form on GitHub → Create GitHub App"
            open_url(start_url) if entry["open_browser"]

            code = await_manifest_code(server, manifest, state)
            unless code
              puts "  [GitHub] ✗ No response from GitHub — re-run: brainiac agent setup #{agent_key}"
              return nil
            end

            data = request(:post, "/app-manifests/#{code}/conversions")
            unless data&.dig("id")
              puts "  [GitHub] ✗ Couldn't exchange the manifest code — re-run: brainiac agent setup #{agent_key}"
              return nil
            end

            save_app(agent_key, data)
          ensure
            server&.close
          end

          def build_manifest(agent_key, display_name, description, redirect_url)
            {
              "name" => "#{agent_key}-brainiac",
              "url" => "https://github.com/stowzilla/brainiac",
              "description" => truncate(description.to_s.sub(/\A---\n.*?\n---\n/m, "")[/\S.*/m] ||
                                         "#{display_name}, a Brainiac agent.", DESCRIPTION_LIMIT),
              "redirect_url" => redirect_url,
              "public" => true, # "Any account", so it can be installed on orgs too
              "hook_attributes" => { "url" => "https://example.com/github", "active" => false },
              "default_permissions" => PERMISSIONS,
              "default_events" => []
            }
          end

          # Tiny one-shot HTTP server: "/" auto-submits the manifest form to GitHub,
          # "/callback" receives GitHub's redirect. Returns the code, or nil on timeout.
          def await_manifest_code(server, manifest, state)
            deadline = Time.now + CALLBACK_TIMEOUT
            loop do
              remaining = deadline - Time.now
              return nil if remaining <= 0
              next unless server.wait_readable(remaining)

              client = server.accept
              path = client.gets.to_s.split[1].to_s
              while (line = client.gets) && line != "\r\n"; end # drain headers

              uri = URI.parse(path)
              params = URI.decode_www_form(uri.query.to_s).to_h
              if uri.path == "/callback" && params["state"] == state && params["code"]
                respond(client, "<p>GitHub App created. Back to the terminal to install it.</p>")
                return params["code"]
              end

              respond(client, manifest_form(manifest, state))
            rescue URI::InvalidURIError
              respond(client, "")
            ensure
              client&.close
            end
          end

          def manifest_form(manifest, state)
            owner = config["agent_app_owner"].to_s
            base = owner.empty? ? "https://github.com/settings/apps/new" : "https://github.com/organizations/#{owner}/settings/apps/new"
            <<~HTML
              <form id="f" method="post" action="#{base}?state=#{state}">
                <input type="hidden" name="manifest" value="#{CGI.escapeHTML(JSON.generate(manifest))}">
                <button type="submit">Continue to GitHub</button>
              </form>
              <script>document.getElementById("f").submit()</script>
            HTML
          end

          def respond(client, html)
            client.write("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\n" \
                         "Content-Length: #{html.bytesize}\r\nConnection: close\r\n\r\n#{html}")
          end

          def save_app(agent_key, data)
            key_path = File.join(brainiac_dir, "#{data["slug"]}.#{Date.today}.private-key.pem")
            File.write(key_path, data["pem"])
            File.chmod(0o600, key_path)

            app = { "id" => data["id"].to_s, "slug" => data["slug"], "private_key_path" => key_path,
                    "installations" => {} }
            update_config { |c| (c["apps"] ||= {})[agent_key] = app }
            puts "  [GitHub] ✓ Created #{data["html_url"]} (key: #{key_path})"
            app
          end

          def install_app(agent_key, app, browser)
            url = "https://github.com/apps/#{app["slug"]}/installations/new"
            owners = Array(config["allowed_owners"])
            puts ""
            puts "  [GitHub] Install it on #{owners.any? ? owners.join(" and ") : "each account with your repos"}:"
            puts "    #{url}"
            open_url(url) if browser
            print "  Press Enter once it's installed (repeat the link per account)… "
            $stdin.gets

            installations = fetch_installations(app)
            if installations.empty?
              puts "  [GitHub] ✗ No installations found — install it, then re-run: brainiac agent setup #{agent_key}"
              return
            end

            update_config { |c| c["apps"][agent_key]["installations"] = installations }
            puts "  [GitHub] ✓ Installed on #{installations.keys.join(", ")} — PRs will open as #{app["slug"]}[bot]"
            missing = owners - installations.keys
            puts "  [GitHub] ⚠ Not installed on #{missing.join(", ")} yet — re-run setup after installing" if missing.any?
          end

          # { "account_login" => "installation_id" } for every place the app is installed.
          def fetch_installations(app)
            key = OpenSSL::PKey::RSA.new(File.read(File.expand_path(app["private_key_path"])))
            now = Time.now.to_i
            jwt = JWT.encode({ iat: now - 60, exp: now + 540, iss: app["id"].to_s }, key, "RS256")
            Array(request(:get, "/app/installations", jwt)).to_h do |inst|
              [inst.dig("account", "login"), inst["id"].to_s]
            end
          rescue StandardError => e
            puts "  [GitHub] ⚠ Couldn't list installations: #{e.message}"
            {}
          end

          def print_logo_step(app, avatar_path)
            return unless avatar_path

            owner = config["agent_app_owner"].to_s
            base = owner.empty? ? "https://github.com/settings/apps" : "https://github.com/organizations/#{owner}/settings/apps"
            puts "  [GitHub] GitHub has no API for app logos — upload #{avatar_path} at:"
            puts "    #{base}/#{app["slug"]} → Display information → Upload a logo"
          end

          def installations?(app)
            (app["installations"] || {}).any? || !app["installation_id"].to_s.empty?
          end

          def request(method, path, token = nil)
            uri = URI("#{GITHUB_API}#{path}")
            req = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
            req["Accept"] = "application/vnd.github+json"
            req["X-GitHub-Api-Version"] = "2022-11-28"
            req["User-Agent"] = "Brainiac-GitHub-App"
            req["Authorization"] = "Bearer #{token}" if token
            res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
              http.request(req)
            end
            res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body) : nil
          rescue StandardError
            nil
          end

          def truncate(text, limit)
            flat = text.to_s.gsub(/\s+/, " ").strip
            flat.length > limit ? "#{flat[0, limit - 1]}…" : flat
          end

          # Best-effort: launch the default browser without blocking on it.
          def open_url(url)
            launcher = RUBY_PLATFORM.include?("darwin") ? "open" : "xdg-open"
            Process.detach(Process.spawn(launcher, url, %i[out err] => File::NULL))
            true
          rescue SystemCallError
            false
          end

          def brainiac_dir
            ENV.fetch("BRAINIAC_DIR", File.join(Dir.home, ".brainiac"))
          end

          def config_file
            File.join(brainiac_dir, "github.json")
          end

          def config
            File.exist?(config_file) ? JSON.parse(File.read(config_file)) : {}
          rescue JSON::ParserError
            {}
          end

          # Read-modify-write so we never clobber edits made since we last read.
          def update_config
            current = config
            yield current
            File.write(config_file, JSON.pretty_generate(current))
          end
        end
      end
    end
  end
end
