defmodule Talisker.Builder.Worker do
  use GenServer

  defstruct [:configuration]

  alias Talisker.Ardbeg

  require Logger

  @snarkos_version_regex ~r/^snarkos\s(\d+\.\d+\.\d+)\s.+?\s([0-9a-fA-F]+)\s.*?$/

  def start_link(configuration) do
    GenServer.start_link(__MODULE__, configuration, name: configuration.name)
  end

  @impl true
  def init(configuration) do
    GithubTrackerEx.subscribe(:new_branch, {:github_path, configuration.github_path})

    {:ok, %__MODULE__{configuration: configuration}}
  end

  @impl true
  def handle_info({:new_branch, %{ref_name: branch_name, ref_hash: hash} = branch_info}, state) do
    configuration = state.configuration
    settings = Map.get(branch_info, :settings, %{})

    branch_filter =
      if Map.get(settings, :force, false) do
        fn _ -> true end
      else
        Map.get(configuration, :branch_filter, fn _ -> true end)
      end

    tests_to_run = Map.get(configuration, :tests_to_run, "all")

    if branch_filter.(branch_name) do
      should_run_tests? = Map.get(settings, :should_run_tests, true)

      with false <- check_exist_on_s3("#{hash}/snarkos"),
           {:ok, path_to_release} <- build_branch(branch_name, hash, state.configuration),
           {:ok, release_version} <- check_release_ready(path_to_release),
           {:ok, _} <- upload_to_s3(path_to_release, hash, release_version),
           {:ok, _} <- File.rm_rf(absolute_build_dir_path(branch_name, state.configuration)) do
        log_info("We uploaded a new release to S3, #{release_version}", configuration)

        log_info("Triggering all tests for the new build", configuration)

        if should_run_tests? do
          Talisker.trigger_test_run(hash, tests_to_run)
        end
      else
        {:error, reason} ->
          log_error("Error building release, will retry, reason=#{inspect(reason)}")

          Process.send_after(self(), {:new_branch, branch_name}, 60_000)

        true ->
          log_info("Triggering tests for already existing build for hash #{hash}", configuration)

          if should_run_tests? do
            Talisker.trigger_test_run(hash, tests_to_run)
          end
      end
    else
      log_info(
        "Skipping build/testrun for branch #{branch_name} as it doesn't match the filter configured.",
        configuration
      )
    end

    {:noreply, state}
  end

  def build_branch(branch_name, hash, configuration) do
    configured_token = Map.get(configuration, :github_token, :public)

    repo_prefix =
      if configured_token == :public do
        ""
      else
        "#{configured_token}@"
      end

    github_url = "https://#{repo_prefix}github.com/#{configuration.github_path}"
    dest = "#{String.replace(configuration.github_path, "/", "_")}_#{branch_name}"

    repo =
      case Git.clone([github_url, dest]) do
        {:ok, repo} ->
          repo

        {:error, %Git.Error{code: 128}} ->
          Git.new(dest)
      end

    {:ok, _} = Git.checkout(repo, branch_name)

    log_info("Checking build status for #{branch_name}@#{hash}", configuration)

    work_folder = Path.join(File.cwd!(), dest)
    path_to_release = Path.join([work_folder, "target", "release", "snarkos"])

    case check_release_ready(path_to_release) do
      {:ok, _version} ->
        {:ok, path_to_release}

      _ ->
        log_info("Will build #{inspect(repo)}", configuration)

        output = File.stream!(Path.join(work_folder, "build.log"), [:delayed_write])

        case MuonTrap.cmd(Path.join([work_folder, "build_ubuntu.sh"]), [],
               cd: dest,
               stderr_to_stdout: true,
               into: output
             ) do
          {_, 0} ->
            {:ok, path_to_release}

          error ->
            {:error, error}
        end
    end
  end

  def check_release_ready(path_to_release) do
    with {:exists, true} <- {:exists, File.exists?(path_to_release)},
         {:executable, {release_output, 0}} <-
           {:executable, MuonTrap.cmd(path_to_release, ["--version"], stderr_to_stdout: true)},
         [[_, version, _hash]] <- Regex.scan(@snarkos_version_regex, release_output) do
      {:ok, version}
    else
      {:exists, false} ->
        {:error, "Release does not exist"}

      {:executable, result} ->
        Logger.error("Release is not executable : #{inspect(result)}")
        {:error, "Release is not executable"}

      any ->
        log_error("Release bad output #{inspect(any)}")
        {:ok, "unknown"}
    end
  end

  # We can use the version and the hash (see check_release_ready) to name the destination.
  def upload_to_s3(path_to_release, hash, _version) do
    releases_for_testing_bucket = System.get_env("RELEASES_FOR_TESTING_BUCKET", "snarkos-releases-for-testing")

    path_to_release
    |> ExAws.S3.Upload.stream_file()
    |> ExAws.S3.upload(releases_for_testing_bucket, "#{hash}/snarkos")
    |> ExAws.request()
  end

  def check_exist_on_s3(path_to_release) do
    releases_for_testing_bucket = System.get_env("RELEASES_FOR_TESTING_BUCKET", "snarkos-releases-for-testing")

    releases_for_testing_bucket
    |> ExAws.S3.list_objects(prefix: path_to_release)
    |> ExAws.request()
    |> case do
      {:ok, %{status_code: 200, body: %{contents: []}}} ->
        false

      {:ok, %{status_code: 200, body: %{contents: [_]}}} ->
        true

      any ->
        Logger.error("Unexpected S3 check result : #{inspect(any)}")
        false
    end
  end

  defp build_destination(branch_name, configuration) do
    "#{String.replace(configuration.github_path, "/", "_")}_#{branch_name}"
  end

  defp absolute_build_dir_path(branch_name, configuration) do
    Path.join(File.cwd!(), build_destination(branch_name, configuration))
  end

  defp log_info(msg, configuration) do
    Ardbeg.update_central("talisker/builder", %{level: :info, msg: msg})
    Logger.info("[Talisker.Builder.Worker #{configuration.name}] #{msg}")
  end

  defp log_error(msg) do
    Ardbeg.update_central("talisker/builder", %{level: :error, msg: msg})
    Logger.error(msg)
  end
end
