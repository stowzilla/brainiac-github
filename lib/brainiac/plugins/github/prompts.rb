# frozen_string_literal: true

module Brainiac
  module Plugins
    module Github
      module Prompts
        CHANNEL = <<~PROMPT
          ## GitHub Channel Rules

          ### Formatting
          Use GitHub-Flavored Markdown for all comments:
          - `## Heading` for sections
          - `**bold**` for emphasis
          - ``` ```language ``` for code blocks
          - `- item` for lists

          ### Scope
          You are responding to activity on a GitHub PR. Focus on the code changes and review feedback.
          When posting comments, post on the PR unless specifically asked to update the card.

        PROMPT

        PR_COMMENT = <<~'PROMPT'
          There's a new comment from @{{COMMENT_CREATOR}} on your PR #{{PR_NUMBER}} for card #{{CARD_NUMBER}}.

          Comment:
          {{COMMENT_BODY}}

          Please:
          1. Read the comment and understand what's being requested
          2. Make any necessary changes
          3. Commit and push your updates
          4. Reply on the PR summarizing what you changed

          You are in the worktree at {{WORKTREE_PATH}}.
        PROMPT

        PR_REVIEW = <<~'PROMPT'
          A code review has been submitted on your PR #{{PR_NUMBER}} for card #{{CARD_NUMBER}}.

          {{REVIEW_CONTEXT}}

          Please:
          1. Read the review comments carefully
          2. Address each piece of feedback
          3. Make the necessary code changes
          4. Commit and push your updates
          5. Post a comment on the PR summarizing the changes

          You are in the worktree at {{WORKTREE_PATH}}.
        PROMPT

        UAT = <<~'PROMPT'
          PR #{{PR_NUMBER}} has been merged into main for card #{{CARD_NUMBER}}: "{{CARD_TITLE}}"

          The card has been moved to the UAT column. The changes are now deployed to the UAT environment.

          Your job: post a comment on card #{{CARD_NUMBER}} with clear, specific steps for how to manually test this feature in UAT. Include:
          1. What URL(s) or screen(s) to visit
          2. Step-by-step actions to verify the feature works
          3. What the expected behavior should be
          4. Any edge cases worth checking
          5. Links to relevant pages if applicable (use the UAT/staging URL, not localhost)

          Base your testing steps on the card title, the PR diff, and any card context provided. Be specific — "verify it works" is not a testing step.

          Do NOT make any code changes. This is a read-only review task.
        PROMPT

        PRE_POST_CHECK = <<~PROMPT
          ## Pre-Post Comment Check (MANDATORY — do this BEFORE posting your comment)

          Your session may have been running for a while. Before you post your final comment,
          re-check the PR for new comments that arrived while you were working:

          ```bash
          gh pr view {{PR_NUMBER}} --comments --json comments
          ```

          If there are **new comments** that weren't in your original context:

          1. **Read them carefully** — a reviewer may have added feedback or changed direction
          2. **Adjust your work or response** to account for the new information
          3. **Do NOT ignore new comments** — avoid posting a response that's already outdated

          If no new comments appeared, proceed normally.

        PROMPT
      end
    end
  end
end
