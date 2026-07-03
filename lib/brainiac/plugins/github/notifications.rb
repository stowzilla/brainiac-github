# frozen_string_literal: true

module Brainiac
  module Plugins
    module Github
      module Notifications
        class << self
          def send_deploy(project_key, closed_cards)
            card_lines = closed_cards.map { |c| "• [##{c[:number]} — #{c[:title]}](#{c[:url]})" }.join("\n")
            message = "🚀 **#{project_key.capitalize}** deployed to production\nClosed UAT cards:\n#{card_lines}"
            send_notification(:deploy, message, metadata_project: project_key)
          end

          def send_uat_deploy(project_key)
            message = "✅ **#{project_key.capitalize}** deployed to UAT successfully"
            send_notification(:deploy, message, metadata_project: project_key)
          end

          def send_workflow_failure(project_key, workflow_name, run_url)
            message = "❌ **#{project_key.capitalize}** — #{workflow_name} failed\n[View run](#{run_url})"
            send_notification(:ci_failure, message, metadata_project: project_key)
          end
        end
      end
    end
  end
end
