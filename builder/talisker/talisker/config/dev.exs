import Config

config :github_tracker_ex,
  repositories: [
    %{
      github_path: "meddle0x53/snarkOS",
      tracking: [
        %{
          type: :new_branch
        }
      ]
    }
  ]
