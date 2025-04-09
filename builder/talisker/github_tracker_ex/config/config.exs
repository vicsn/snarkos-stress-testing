import Config

if config_env() == :dev do
  # A repository is defined as map:
  # Can include:
  #  1. `github_path`, `local_path`, `url` - for access
  #  2. `token`, `user` and `password` - for auth
  #  3. A list of tracking options : To be defined, but you can track for new PRs, new branches with patterns.

  config :github_tracker_ex,
    repositories: [
      %{
        github_path: "meddle0x53/GitHub_tracker_ex_test",
        tracking: [
          %{
            type: :new_branch
          }
        ]
      }
    ]
end
