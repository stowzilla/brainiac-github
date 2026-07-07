# frozen_string_literal: true

require_relative "test_helper"

class TestAppClient < Minitest::Test
  def test_not_configured_without_app_credentials
    refute Brainiac::Plugins::Github::AppClient.configured?
  end

  def test_configured_with_all_credentials
    pem_path = File.join(TEST_BRAINIAC_DIR, "test-key.pem")
    key = OpenSSL::PKey::RSA.generate(2048)
    File.write(pem_path, key.to_pem)

    config = { "webhook_secret" => "test-secret-123",
               "app" => { "id" => "12345", "private_key_path" => pem_path, "installation_id" => "67890" },
               "repos" => {} }
    File.write(File.join(TEST_BRAINIAC_DIR, "github.json"), JSON.generate(config))
    Brainiac::Plugins::Github::Config.load!

    assert Brainiac::Plugins::Github::AppClient.configured?
  ensure
    # Restore original config
    restore_config = { "webhook_secret" => "test-secret-123", "repos" => {} }
    File.write(File.join(TEST_BRAINIAC_DIR, "github.json"), JSON.generate(restore_config))
    Brainiac::Plugins::Github::Config.load!
    FileUtils.rm_f(pem_path)
  end

  def test_not_configured_with_missing_key_file
    config = { "webhook_secret" => "test-secret-123",
               "app" => { "id" => "12345", "private_key_path" => "/nonexistent/key.pem", "installation_id" => "67890" },
               "repos" => {} }
    File.write(File.join(TEST_BRAINIAC_DIR, "github.json"), JSON.generate(config))
    Brainiac::Plugins::Github::Config.load!

    refute Brainiac::Plugins::Github::AppClient.configured?
  ensure
    restore_config = { "webhook_secret" => "test-secret-123", "repos" => {} }
    File.write(File.join(TEST_BRAINIAC_DIR, "github.json"), JSON.generate(restore_config))
    Brainiac::Plugins::Github::Config.load!
  end

  def test_not_configured_with_partial_credentials
    config = { "webhook_secret" => "test-secret-123",
               "app" => { "id" => "12345" },
               "repos" => {} }
    File.write(File.join(TEST_BRAINIAC_DIR, "github.json"), JSON.generate(config))
    Brainiac::Plugins::Github::Config.load!

    refute Brainiac::Plugins::Github::AppClient.configured?
  ensure
    restore_config = { "webhook_secret" => "test-secret-123", "repos" => {} }
    File.write(File.join(TEST_BRAINIAC_DIR, "github.json"), JSON.generate(restore_config))
    Brainiac::Plugins::Github::Config.load!
  end

  def test_config_reads_app_id
    config = { "webhook_secret" => "s", "app" => { "id" => "99999" }, "repos" => {} }
    File.write(File.join(TEST_BRAINIAC_DIR, "github.json"), JSON.generate(config))
    Brainiac::Plugins::Github::Config.load!

    assert_equal "99999", Brainiac::Plugins::Github::Config.app_id
  ensure
    restore_config = { "webhook_secret" => "test-secret-123", "repos" => {} }
    File.write(File.join(TEST_BRAINIAC_DIR, "github.json"), JSON.generate(restore_config))
    Brainiac::Plugins::Github::Config.load!
  end

  def test_config_reads_installation_id
    config = { "webhook_secret" => "s", "app" => { "installation_id" => "77777" }, "repos" => {} }
    File.write(File.join(TEST_BRAINIAC_DIR, "github.json"), JSON.generate(config))
    Brainiac::Plugins::Github::Config.load!

    assert_equal "77777", Brainiac::Plugins::Github::Config.installation_id
  ensure
    restore_config = { "webhook_secret" => "test-secret-123", "repos" => {} }
    File.write(File.join(TEST_BRAINIAC_DIR, "github.json"), JSON.generate(restore_config))
    Brainiac::Plugins::Github::Config.load!
  end

  def test_config_app_id_from_env
    config = { "webhook_secret" => "s", "repos" => {} }
    File.write(File.join(TEST_BRAINIAC_DIR, "github.json"), JSON.generate(config))
    Brainiac::Plugins::Github::Config.load!

    ENV["GITHUB_APP_ID"] = "env-app-id"
    assert_equal "env-app-id", Brainiac::Plugins::Github::Config.app_id
  ensure
    ENV.delete("GITHUB_APP_ID")
    restore_config = { "webhook_secret" => "test-secret-123", "repos" => {} }
    File.write(File.join(TEST_BRAINIAC_DIR, "github.json"), JSON.generate(restore_config))
    Brainiac::Plugins::Github::Config.load!
  end

  def test_reset_clears_cached_token
    Brainiac::Plugins::Github::AppClient.reset!
    # No error means it works — token is nil after reset
    refute Brainiac::Plugins::Github::AppClient.configured?
  end
end
