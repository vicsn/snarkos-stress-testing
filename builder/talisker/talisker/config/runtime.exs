import Config

config :talisker, Talisker.Ardbeg.Supervisor,
  enabled: System.get_env("ARDBEG_ENABLED", "false") |> String.to_existing_atom()

if config_env() == :prod do
  ardbeg_secret =
    System.get_env("ARDBEG_SECRET") ||
      raise """
      environment variable ARDBEG_SECRET is missing.
      """

  staging_repo_token =
    System.get_env("STAGING_REPO_TOKEN") ||
      raise """
      environment variable STAGING_REPO_TOKEN is missing.
      """

  config :github_tracker_ex,
    repositories: [
      %{
        github_path: "ProvableHQ/snarkOS",
        tracking: [
          %{
            type: :new_branch,
            matcher: [~r/^[A-Za-z][A-Za-z0-9]+\-v(\d+\.\d+\.\d+)$/, ~r/^v(\d+\.\d+\.\d+)$/]
          }
        ]
      },
      %{
        github_path: "meddle0x53/snarkOS",
        tracking: [
          %{
            type: :new_branch,
            matcher: [~r/^test[0-9]+$/]
          }
        ]
      },
      %{
        github_path: "kpandl/snarkOS",
        tracking: [
          %{
            type: :new_branch,
            matcher: [~r/^[A-Za-z][A-Za-z0-9]+\-v(\d+\.\d+\.\d+)$/, ~r/^v(\d+\.\d+\.\d+)$/]
          }
        ]
      },
      %{
        github_path: "ProvableHQ/snarkOS-staging",
        tracking: [
          %{
            token: staging_repo_token,
            type: :new_branch,
            matcher: [~r/^[A-Za-z][A-Za-z0-9]+\-v(\d+\.\d+\.\d+)$/, ~r/^v(\d+\.\d+\.\d+)$/]
          }
        ]
      }
    ]

  config :talisker, :ardbeg_hash, :crypto.hash(:sha256, ardbeg_secret)
end
