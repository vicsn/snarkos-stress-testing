import os
import argparse
from datetime import datetime, timedelta

# Set the variables
val_index = 0

# Define the function to parse and filter logs
def filter_logs_by_time(log_content, time_interval=timedelta(hours=1)):
    log_lines = log_content.splitlines()
    if not log_lines:
        return ""

    # Parse the timestamp of the last log entry with a valid timestamp
    for i in range(len(log_lines) - 1, -1, -1):
        try:
            last_log_time = datetime.fromisoformat(log_lines[i].split(' ')[0][:-1])
            break
        except ValueError:
            continue
    else:
        return ""

    # Calculate the cutoff time
    cutoff_time = last_log_time - time_interval

    # Filter logs
    filtered_logs = []
    for line in log_lines:
        parts = line.split(' ')
        if len(parts) > 0:
            try:
                log_time = datetime.fromisoformat(parts[0][:-1])
                if log_time >= cutoff_time:
                    filtered_logs.append(line)
            except ValueError:
                continue

    return '\n'.join(filtered_logs)

# Main function
def main():
    # Setup argument parser
    parser = argparse.ArgumentParser(description='Process log files and filter them by time.')
    parser.add_argument('--logpath', required=True, help='The relative path to the log folder/file.')
    
    # Parse the arguments
    args = parser.parse_args()

    # check if it is a file or a folder
    if os.path.isdir(args.logpath):
        # extract foldername from logpath
        folder_name = os.path.basename(args.logpath)
        # create a new folder for the prepared log files
        new_log_folder_path = os.path.join(os.getcwd(), "prepared_" + folder_name)
        os.makedirs(new_log_folder_path, exist_ok=True)

        # iterate over all log files in the folder
        for file in os.listdir(args.logpath):
            if file.endswith(".log"):
                log_file_path = os.path.join(args.logpath, file)
                core_logic(log_file_path, os.path.join(new_log_folder_path, "prepared_"+file))
    else:
        log_file_path = args.logpath

        # Check if the log file exists
        if not os.path.exists(log_file_path):
            print(f"Log file {log_file_path} does not exist.")
            print(f"Absolute path: {os.path.abspath(log_file_path)}")
            print("Exiting...")
            return

        core_logic(log_file_path, os.path.join(os.getcwd(), "prepared_" + os.path.basename(log_file_path)))

    #log_folder_path = args.logfile

    #log_file_path = os.path.join(os.getcwd(), log_folder_path)


# function with the core logic
def core_logic(log_file_path, new_log_file_path):

    # Read the file content as a string
    with open(log_file_path, 'r') as file:
        lines = file.read()

    # Replace double newlines to make sure each log stays on one line.
    lines = lines.replace("INFO \n\nAdvanced to block", "INFO Advanced to block")
    lines = lines.replace("\n\nAdvanced to block", "Advanced to block")
    lines = lines.replace("INFO \n\nCommitting a subdag", "INFO Committing a subdag")

    # Filter logs to keep only the last one hour of entries
    filtered_logs = filter_logs_by_time(lines)

    # extract filename and path form log_file_path
    #log_file_name = os.path.basename(log_file_path)
    #log_folder_path = os.path.dirname(log_file_path)

    # Store as a new log file
    #new_log_file_name = "prepared_" + log_file_name
    
    #new_log_file_path = os.path.join(log_folder_path, new_log_file_name)

    # Write the filtered logs to the new file
    with open(new_log_file_path, 'w') as file:
        file.write(filtered_logs)

# Run the main function
if __name__ == "__main__":
    main()