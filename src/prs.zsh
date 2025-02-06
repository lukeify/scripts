#!/usr/bin/env zsh

##
# For the given current directory, open the current directory's GitHub repository in a browser, defaulting to the pull
# requests tab. The current directory must be a git repository, and must have an origin on GitHub. Future improvements
# could be support for different remote git origins like GitLab, etc.
#
repo_url=$(gh repo view --json url -q .url)

if [[ -z "$repo_url" ]]; then
  echo "Failed to get repository URL. Make sure you're in a Git repository and logged into GitHub CLI."
  exit 1
fi

# Open the PRs tab in the default browser
open "${repo_url}/pulls"