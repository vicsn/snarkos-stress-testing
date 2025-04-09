defmodule Talisker.Tester.ObservabilityRunner do
  @moduledoc """
  The Observability tests Tester.

  It can be triggered with (for example):

  Phoenix.PubSub.broadcast(Talisker.PubSub, "testers", {:run, "default", "v3.1.0"})
  """
  use GenServer

  defstruct [:configuration, :table]

  alias Phoenix.PubSub

  @broker Talisker.PubSub
  @topic "testers"
  @failed_tests_max_retries 3

  require Logger

  def start_link(configuration) do
    GenServer.start_link(__MODULE__, configuration, name: configuration.name)
  end

  @impl true
  def init(configuration) do
    :ok = PubSub.subscribe(@broker, @topic)

    {:ok, %__MODULE__{configuration: configuration}, {:continue, :setup_table}}
  end

  @impl true
  def handle_continue(:setup_table, %__MODULE__{configuration: configuration} = state) do
    log_path = Path.join(File.cwd!(), "observability_runner.log")
    File.rm_rf(log_path)

    table_name =
      configuration
      |> Map.get_lazy(:runs_cache_table_name, fn ->
        {:registered_name, name} = Process.info(self(), :registered_name)
        "observability_runner_#{name}"
      end)
      |> String.to_atom()

    {:ok, table} =
      :dets.open_file(table_name,
        access: :read_write,
        auto_save: :timer.seconds(40),
        max_no_slots: 256
      )

    :ets.new(table, [:named_table])
    table = :dets.to_ets(table, table)

    table
    |> :ets.tab2list()
    |> Enum.group_by(fn {_, label, _} -> label end)
    |> Enum.each(fn {label, tests} ->
      tests_to_run = Enum.map(tests, fn {test_name, _, _} -> test_name end)
      Logger.info("Pending tests to run for #{label} : #{inspect(tests_to_run)}")

      if tests_to_run != [] do
        [{_, _, time} | _] = tests
        Process.send_after(self(), {:run, tests_to_run, label, time}, :timer.seconds(30))
      end
    end)

    {:noreply, %__MODULE__{state | table: table}}
  end

  @impl true
  def handle_info({:run, "all", label}, state) do
    all_tests = list_all_tests(state.configuration)
    prepare_and_run_tests(all_tests, label, :now, state)

    {:noreply, state}
  end

  @impl true
  def handle_info({:run, test_name, label}, state) when is_binary(test_name) do
    prepare_and_run_tests([test_name], label, :now, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:run, list, label}, state) when is_list(list) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    prepare_and_run_tests(list, label, now, state)

    {:noreply, state}
  end

  @impl true
  def handle_info({:run, list, label, time}, state) when is_list(list) do
    prepare_and_run_tests(list, label, time, state)

    {:noreply, state}
  end

  defp prepare_and_run_tests(test_list, label, time, state) do
    log_info("Triggering a new test run for #{label}, tests: #{inspect(test_list)}")

    case setup_infrastructure(label, state.configuration) do
      {:ok, _} ->
        test_list
        |> Enum.each(fn test_name ->
          :ets.insert_new(state.table, [{test_name, label, time}])
        end)

        test_list
        |> Enum.each(fn test_name ->
          prepare_and_run_test(test_name, label, state.configuration, time)

          :ets.delete(state.table, test_name)
          :ok = :dets.from_ets(state.table, state.table)
        end)

      {:error, _, _} ->
        log_error("Can not run tests, problems, creating the infrastructure, check the logs.")
    end

    cleanup_infrastructure(state.configuration)
    cleanup(label, state.configuration)

    log_info("Test run for #{label} has ended.")
  end

  defp prepare_and_run_test(test_name, label, configuration, time, opts \\ []) do
    time =
      if time == :now do
        DateTime.utc_now() |> DateTime.to_unix()
      else
        time
      end

    timed_label = time |> DateTime.from_unix!() |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)
    results_path = Path.join("#{label}/#{timed_label}", "#{test_name}")

    args = ["test", "-t", test_name, "-v", "#{label}_vars"]
    log_info("Running tests with args #{inspect(args)}")

    with {:ok, output_path} <- run(args, configuration),
         {:ok, _} <- upload_to_s3(output_path, results_path) do
      upload_log_files(results_path, configuration)
      log_info("We uploaded logs for test #{test_name} to s3, path #{results_path}.")

      upload_prometheus_snapshot(results_path, configuration)
      log_info("We uploaded Prometheus snapshot #{test_name} to s3, path #{results_path}.")
    else
      {:error, reason} ->
        log_error("Error testing #{label} : #{inspect(reason)}")

      {:error, reason, output_path} ->
        retries = Keyword.get(opts, :retries, @failed_tests_max_retries)

        if retries <= 1 do
          results_path = "#{results_path}_FAILED"
          upload_to_s3(output_path, results_path)
          upload_log_files(results_path, configuration)
          upload_prometheus_snapshot(results_path, configuration)

          log_error("Error testing #{label} : #{inspect(reason)}")
        else
          log_error("Error testing #{label} : #{inspect(reason)}")

          next_retries = retries - 1
          log_info("Retrying, retries left : #{next_retries}")

          # Removing the central log as it is also used as a lock:
          File.cp(output_path, "#{output_path}_#{timed_label}_#{retries}.bak")
          File.rm_rf(output_path)

          prepare_and_run_test(test_name, label, configuration, time, retries: next_retries)
        end
    end

    log_path = Path.join(File.cwd!(), "observability_runner.log")
    {:ok, _} = File.rm_rf(log_path)
  end

  defp run(args, configuration) do
    tests_path =
      Map.get(
        configuration,
        :tests_path,
        "/home/ubuntu/stress_testing/test_suites/single-region-tests"
      )

    script = Map.get(configuration, :tests_script, "auto_run_test_suite.sh")
    command = Path.join(tests_path, script)

    output = Path.join(File.cwd!(), "observability_runner.log")
    output_stream = File.stream!(output)

    if File.exists?(output) do
      # We don't run the test again
      {:ok, output}
    else
      case MuonTrap.cmd(command, args,
             cd: tests_path,
             stderr_to_stdout: true,
             into: output_stream
           ) do
        {out, 0} ->
          Logger.info(inspect(out))
          {:ok, output}

        error ->
          log_error(inspect(error))

          {:error, error, output}
      end
    end
  end

  defp setup_infrastructure(label, configuration) do
    tests_path =
      Map.get(
        configuration,
        :tests_path,
        "/home/ubuntu/stress_testing/test_suites/single-region-tests"
      )

    script = Map.get(configuration, :tests_script, "auto_run_test_suite.sh")
    command = Path.join(tests_path, script)

    output = Path.join(File.cwd!(), "observability_runner_setup.log")
    output_stream = File.stream!(output)

    args = ["setup", "-v", "#{label}_vars"]

    location = download_executables!(label, configuration)

    run_vars_file = Path.join(tests_path, "playbooks/#{label}_vars.yml")
    :ok = File.cp(Path.join(tests_path, "playbooks/vars.yml"), run_vars_file)

    :ok =
      File.write(run_vars_file, ~s(\nsnarkos_pre_build_location: "#{location}"\n), [:append])

    case MuonTrap.cmd(command, args,
           cd: tests_path,
           stderr_to_stdout: true,
           into: output_stream
         ) do
      {out, 0} ->
        log_info("Infrastructure setup ready for test runs!")
        log_info(inspect(out))
        {:ok, output}

      error ->
        log_error(inspect(error))

        {:error, error, output}
    end
  end

  defp cleanup_infrastructure(configuration) do
    tests_path =
      Map.get(
        configuration,
        :tests_path,
        "/home/ubuntu/stress_testing/test_suites/single-region-tests"
      )

    cleanup_output = Path.join(File.cwd!(), "observability_runner_cleanup.log")
    cleanup_output_stream = File.stream!(cleanup_output)

    terraform_executable =
      Map.get(configuration, :terraform_executable, "/usr/bin/terraform")

    log_info("Cleanup initiated...")

    # Cleanup terraform here if the test didn't do it because of the crash:
    MuonTrap.cmd(terraform_executable, ["destroy", "-auto-approve"],
      cd: Path.join(tests_path, "terraform_tx_cannon"),
      stderr_to_stdout: true,
      env: [{"AWS_REGION", "us-west-2"}],
      into: cleanup_output_stream
    )

    MuonTrap.cmd(terraform_executable, ["destroy", "-auto-approve"],
      cd: Path.join(tests_path, "terraform"),
      stderr_to_stdout: true,
      env: [{"AWS_REGION", "us-west-2"}],
      into: cleanup_output_stream
    )

    log_info("Cleanup done.")
  end

  defp cleanup(label, configuration) do
    binaries_folder = Map.get(configuration, :binaries_folder, "/home/ubuntu/binaries")
    binary_folder = Path.join(binaries_folder, label)

    File.rm_rf(binary_folder)
  end

  defp download_executables!(label, configuration) do
    binaries_folder = Map.get(configuration, :binaries_folder, "/home/ubuntu/binaries")
    binary_folder = Path.join(binaries_folder, label)

    :ok = File.mkdir_p(binary_folder)
    runnable_location = Path.join(binary_folder, "snarkos")

    releases_for_testing_bucket = System.get_env("RELEASES_FOR_TESTING_BUCKET", "snarkos-releases-for-testing")

    log_info("Downloading executable #{label}/snarkos from #{releases_for_testing_bucket}")

    download =
      ExAws.S3.download_file(
        releases_for_testing_bucket,
        "#{label}/snarkos",
        runnable_location
      )

    case ExAws.request(download) do
      {:ok, _} ->
        :noop

      {:error, :eacces} ->
        # Already downloaded
        :noop
    end

    :ok = File.chmod(runnable_location, 0o500)
    runnable_location
  end

  defp log_info(msg) do
    Logger.info("[Talisker.Tester.ObservabilityRunner] #{msg}")
  end

  defp log_error(msg) do
    Logger.error(msg)
  end

  defp upload_to_s3(local_path, s3_prefix) do
    filename = Path.basename(local_path)
    s3_location = Path.join(s3_prefix, filename)

    test_results_and_logs_bucket = System.get_env("TEST_RESULTS_AND_LOGS_BUCKET", "provable-logs-results")
    log_info("Uploading from #{local_path} to #{test_results_and_logs_bucket}")

    local_path
    |> ExAws.S3.Upload.stream_file()
    |> ExAws.S3.upload(test_results_and_logs_bucket, s3_location, acl: :public_read)
    |> ExAws.request()
  end

  defp upload_log_files(results_path, configuration) do
    tests_path =
      Map.get(
        configuration,
        :tests_path,
        "/home/ubuntu/stress_testing/test_suites/single-region-tests"
      )

    tests_log_folder = Path.join(tests_path, "log_files")

    if File.exists?(tests_log_folder) do
      tests_log_folder
      |> File.ls!()
      |> Enum.each(fn log_file ->
        log_file_path = Path.join(tests_log_folder, log_file)

        log_file_path =
          if analyse_log_stream(log_file_path) != [] do
            log_info("Detected an error in the logs #{log_file_path}, renaming the file!")

            log_name = Path.basename(log_file_path, ".log.gz")
            error_log_file = "#{log_name}_ERRORS.log.gz"

            error_log_path = Path.join(tests_log_folder, error_log_file)
            File.cp!(log_file_path, error_log_path)

            error_log_path
          else
            log_file_path
          end

        upload_to_s3(log_file_path, results_path)
      end)
    end

    {:ok, _} = File.rm_rf(tests_log_folder)
  end

  defp upload_prometheus_snapshot(results_path, configuration) do
    tests_path =
      Map.get(
        configuration,
        :tests_path,
        "/home/ubuntu/stress_testing/test_suites/single-region-tests"
      )

    prometheus_snapshot = Path.join(tests_path, "prometheus_server_data/prometheus_snapshot.tar.gz")

    if File.exists?(prometheus_snapshot) do
      upload_to_s3(prometheus_snapshot, results_path)
    end
  end

  defp analyse_log_stream(path) do
    path
    |> File.stream!([{:read_ahead, 65_536}, :compressed])
    |> line_stream_from_binary_stream()
    |> Enum.filter(fn line ->
      String.contains?(line, "ERROR")
    end)
    |> Enum.reject(fn line ->
      String.contains?(line, "ERROR request{method=GET")
    end)
  end

  defp line_stream_from_binary_stream(bin_stream) do
    bin_stream
  end

  @excluded_from_all []
  defp list_all_tests(configuration) do
    tests_path =
      Map.get(
        configuration,
        :tests_path,
        "/home/ubuntu/stress_testing/test_suites/single-region-tests"
      )

    tests_folder = Path.join(tests_path, "tests")

    tests_folder
    |> File.ls!()
    |> Enum.reject(fn test_name -> String.starts_with?(test_name, "_") end)
    |> Enum.reject(fn test_name -> test_name in @excluded_from_all end)
  end
end
