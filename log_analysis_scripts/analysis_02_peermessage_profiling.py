import argparse
import os
import pandas as pd
import matplotlib.pyplot as plt
import copy
import numpy as np

class Round:
    def __init__(self, round_number):
        self.round_number = round_number

        self.process_batch_propose_from_peer_start_times = {}
        self.process_batch_propose_from_peer_end_times = {}
        self.process_batch_propose_from_peer_fetching_transmissions_start_times = {}
        self.process_batch_propose_from_peer_fetching_transmissions_end_times = {}

        self.process_batch_signature_from_peer_start_times = {}
        self.process_batch_signature_from_peer_end_times = {}

        self.process_batch_certified_from_peer_start_times = {}
        self.process_batch_certified_from_peer_end_times = {}
        self.process_batch_certified_from_peer_fetching_transmissions_start_times = {}
        self.process_batch_certified_from_peer_fetching_transmissions_end_times = {}

        self.peers_for_completed_batch_processing = set()

    def get_average_duration_in_process_batch_propose_from_peer_fetching_transmissions(self):
        durations = []
        # print warn message if self.peers_for_completed_batch_processing is empty
        if(len(self.peers_for_completed_batch_processing) == 0):
            print(f"Warning: self.peers_for_completed_batch_processing is empty for round {self.round_number}")
        
        # iterate over peer_ips in self.process_batch_propose_from_peer_fetching_transmissions_start_times
        for peer_ip in self.peers_for_completed_batch_processing:
            # check if the peer_ip is in self.process_batch_propose_from_peer_fetching_transmissions_end_times
            if peer_ip in self.process_batch_propose_from_peer_fetching_transmissions_end_times:
                # calculate the duration and append it to durations
                durations.append((self.process_batch_propose_from_peer_fetching_transmissions_end_times[peer_ip] - self.process_batch_propose_from_peer_fetching_transmissions_start_times[peer_ip]).total_seconds())
            else:
                print(f"Error: peer_ip {peer_ip} not found in self.process_batch_propose_from_peer_fetching_transmissions_end_times")
        # return the average of durations
        return np.mean(durations)
    
    def get_average_duration_in_process_batch_propose_from_peer_without_fetching_transmissions(self):
        durations = []
        # iterate over peer_ips in self.process_batch_propose_from_peer_start_times
        for peer_ip in self.process_batch_propose_from_peer_start_times:
            # check if the peer_ip is in self.process_batch_propose_from_peer_end_times
            if peer_ip in self.process_batch_propose_from_peer_end_times:
                # calculate the duration and append it to durations
                durations.append((self.process_batch_propose_from_peer_end_times[peer_ip] - self.process_batch_propose_from_peer_start_times[peer_ip]).total_seconds())
                self.peers_for_completed_batch_processing.add(peer_ip)
            else:
                print(f"Warning: peer_ip {peer_ip} not found in self.process_batch_propose_from_peer_end_times - this might be expected")
        # return the average of durations
        return np.mean(durations) - self.get_average_duration_in_process_batch_propose_from_peer_fetching_transmissions()
    
    def get_average_duration_in_process_batch_signature_from_peer(self):
        durations = []
        # iterate over peer_ips in self.process_batch_signature_from_peer_start_times
        for peer_ip in self.process_batch_signature_from_peer_start_times:
            # check if the peer_ip is in self.process_batch_signature_from_peer_end_times
            if peer_ip in self.process_batch_signature_from_peer_end_times:
                # calculate the duration and append it to durations
                durations.append((self.process_batch_signature_from_peer_end_times[peer_ip] - self.process_batch_signature_from_peer_start_times[peer_ip]).total_seconds())
            else:
                print(f"Warning: peer_ip {peer_ip} not found in self.process_batch_signature_from_peer_end_times, round {self.round_number} - this might be expected")
        # return the average of durations
        return np.mean(durations)
    
    def get_average_duration_in_process_batch_certified_from_peer_fetching_transmissions(self):
        durations = []
        # iterate over peer_ips in self.process_batch_certified
        for peer_ip in self.process_batch_certified_from_peer_fetching_transmissions_start_times:
            # check if the peer_ip is in self.process_batch_certified_from_peer_fetching_transmissions_end_times
            if peer_ip in self.process_batch_certified_from_peer_fetching_transmissions_end_times:
                # calculate the duration and append it to durations
                durations.append((self.process_batch_certified_from_peer_fetching_transmissions_end_times[peer_ip] - self.process_batch_certified_from_peer_fetching_transmissions_start_times[peer_ip]).total_seconds())
            else:
                print(f"Error: peer_ip {peer_ip} not found in self.process_batch_certified_from_peer_fetching_transmissions_end_times, round {self.round_number}")
        # return the average of durations
        return np.mean(durations)

    def get_average_duration_in_process_batch_certified_from_peer_without_fetching_transmissions(self):
        durations = []
        # iterate over peer_ips in self.process_batch_certified_from_peer_start_times
        for peer_ip in self.process_batch_certified_from_peer_start_times:
            # check if the peer_ip is in self.process_batch_certified_from_peer_end_times
            if peer_ip in self.process_batch_certified_from_peer_end_times:
                # calculate the duration and append it to durations
                a = (self.process_batch_certified_from_peer_end_times[peer_ip] - self.process_batch_certified_from_peer_start_times[peer_ip]).total_seconds()
                durations.append((self.process_batch_certified_from_peer_end_times[peer_ip] - self.process_batch_certified_from_peer_start_times[peer_ip]).total_seconds())
            else:
                print(f"Error: peer_ip {peer_ip} not found in self.process_batch_certified_from_peer_end_times, round {self.round_number}")
        # return the average of durations
        return np.mean(durations) - self.get_average_duration_in_process_batch_certified_from_peer_fetching_transmissions()

def main():
    # Setup argument parser
    parser = argparse.ArgumentParser(description='Process log files and filter them by time.')
    parser.add_argument('--logpath', required=True, help='The relative path to the log file or folder for averaging across validators.')
    parser.add_argument('--round_start_avg', required=False, help='The start round for the averages', default=1)
    parser.add_argument('--round_limit', required=False, help='The end round for the averages and the plot')

    # Parse the arguments
    args = parser.parse_args()
    
    logpath = args.logpath
    absolute_log_path = os.path.join(os.getcwd(), logpath)

    # Check if the log file.path exists
    if not os.path.exists(absolute_log_path):
        print(f"Log file/path {absolute_log_path} does not exist.")
        print(f"Absolute path: {os.path.abspath(absolute_log_path)}")
        print("Exiting...")
        return
    
    log_file_list = []
    log_file_indices = []
    
    # check is the absolute_log_path is a file or a folder
    if os.path.isdir(absolute_log_path):
        # get all files in the folder
        i = 0
        for file in os.listdir(absolute_log_path):
            if file.endswith(".log") or file.endswith(".txt"):
                log_file_list.append(os.path.join(absolute_log_path, file))
                log_file_indices.append(i)
                i += 1
    else:
        log_file_list.append(absolute_log_path)
        log_file_indices.append(0)

    dict_list_avg_propose_no_fetch = {}
    dict_list_avg_propose_fetch = {}
    dict_list_avg_signature = {}
    dict_list_avg_certified_no_fetch = {}
    dict_list_avg_certified_fetch = {}

    max_rounds = 0

    for i in range(len(log_file_list)):
        log_file_index = log_file_indices[i]
        absolute_log_path = log_file_list[i]

        list_avg_propose_no_fetch, list_avg_propose_fetch, list_avg_signature, list_avg_certified_no_fetch, list_avg_certified_fetch = load_validator_file(absolute_log_path)

        dict_list_avg_propose_no_fetch[log_file_index] = list_avg_propose_no_fetch
        dict_list_avg_propose_fetch[log_file_index] = list_avg_propose_fetch
        dict_list_avg_signature[log_file_index] = list_avg_signature
        dict_list_avg_certified_no_fetch[log_file_index] = list_avg_certified_no_fetch
        dict_list_avg_certified_fetch[log_file_index] = list_avg_certified_fetch

        max_rounds = max(max_rounds, len(list_avg_propose_no_fetch), len(list_avg_propose_fetch), len(list_avg_signature), len(list_avg_certified_no_fetch), len(list_avg_certified_fetch))


    avg_list_avg_propose_no_fetch = []
    avg_list_avg_propose_fetch = []
    avg_list_avg_signature = []
    avg_list_avg_certified_no_fetch = []
    avg_list_avg_certified_fetch = []

    for i in range(max_rounds):
        list_avg_propose_no_fetch = []
        list_avg_propose_fetch = []
        list_avg_signature = []
        list_avg_certified_no_fetch = []
        list_avg_certified_fetch = []

        for log_file_index in log_file_indices:
            if i < len(dict_list_avg_propose_no_fetch[log_file_index]):
                list_avg_propose_no_fetch.append(dict_list_avg_propose_no_fetch[log_file_index][i])
            if i < len(dict_list_avg_propose_fetch[log_file_index]):
                list_avg_propose_fetch.append(dict_list_avg_propose_fetch[log_file_index][i])
            if i < len(dict_list_avg_signature[log_file_index]):
                list_avg_signature.append(dict_list_avg_signature[log_file_index][i])
            if i < len(dict_list_avg_certified_no_fetch[log_file_index]):
                list_avg_certified_no_fetch.append(dict_list_avg_certified_no_fetch[log_file_index][i])
            if i < len(dict_list_avg_certified_fetch[log_file_index]):
                list_avg_certified_fetch.append(dict_list_avg_certified_fetch[log_file_index][i])

        avg_list_avg_propose_no_fetch.append(np.mean([x for x in list_avg_propose_no_fetch if not np.isnan(x)]))
        avg_list_avg_propose_fetch.append(np.mean([x for x in list_avg_propose_fetch if not np.isnan(x)]))
        avg_list_avg_signature.append(np.mean([x for x in list_avg_signature if not np.isnan(x)]))
        avg_list_avg_certified_no_fetch.append(np.mean([x for x in list_avg_certified_no_fetch if not np.isnan(x)]))
        avg_list_avg_certified_fetch.append(np.mean([x for x in list_avg_certified_fetch if not np.isnan(x)]))
        
    plot_sync_times(avg_list_avg_propose_no_fetch, avg_list_avg_propose_fetch, avg_list_avg_signature, avg_list_avg_certified_no_fetch, avg_list_avg_certified_fetch, args.round_start_avg, args.round_limit, logpath)

def load_validator_file(absolute_log_path):

    # Load the log file
    with open(absolute_log_path, 'r') as file:
        lines = file.readlines()

    # Split each line into a timestamp and a message, filtering out invalid lines
    data = []
    for line in lines:
        parts = line.strip().split('  INFO ', 1)
        if len(parts) == 2:
            try:
                timestamp = pd.to_datetime(parts[0], format='%Y-%m-%dT%H:%M:%S.%f%z')
                data.append(parts)
            except ValueError:
                continue
        else:
            parts = line.strip().split(' DEBUG ', 1)
            if len(parts) == 2:
                try:
                    timestamp = pd.to_datetime(parts[0], format='%Y-%m-%dT%H:%M:%S.%f%z')
                    data.append(parts)
                except ValueError:
                    continue

    # Convert to DataFrame
    df = pd.DataFrame(data, columns=['Timestamp', 'Message'])
    df['Timestamp'] = pd.to_datetime(df['Timestamp'])

    # Filter specific events
    events = [
        "profiling - received BatchPropose for round",
        "profiling - fetching transmissions from BatchPropose for round",
        "profiling - fetched transmissions from BatchPropose for round",
        "profiling - broadcast signature for BatchPropose for round",
        "profiling - received BatchSignature for round",
        "profiling - processed BatchSignature for round",
        "profiling - received BatchCertified for round",
        "profiling - processed BatchCertified for round",
        "profiling - received PrimaryPing for round",
        "profiling - fetching transmissions from BatchCertificate for round",
        "profiling - fetched transmissions from BatchCertificate for round",
    ]

    event_df = df[df['Message'].str.contains('|'.join(events), na=False)]
    rounds = {}

    # for debugging
    # store the event_df in a csv file
    # event_df.to_csv(f'event_df_val{val_index}.csv', index=False)

    for i, row in event_df.iterrows():
        # if message format: info!("profiling - received BatchPropose for round {}, peer_ip {}", batch_propose.round, peer_ip);
        if "profiling - received BatchPropose for round" in row['Message']:
            round_number = int(row['Message'].split('profiling - received BatchPropose for round ')[1].split(',')[0])
            peer_ip = row['Message'].split('peer_ip ')[1]

            if round_number not in rounds:
                rounds[round_number] = Round(round_number)

            if(not peer_ip in rounds[round_number].process_batch_propose_from_peer_start_times):
                rounds[round_number].process_batch_propose_from_peer_start_times[peer_ip] = row['Timestamp']
            else:
                print(f"Warning: peer_ip {peer_ip} already found in self.process_batch_propose_from_peer_start_times, round {round_number} - this might be expected")
        
        # if message format: info!("profiling - broadcast signature for BatchPropose for round {}, peer_ip {}", batch_round, peer_ip);
        if "profiling - broadcast signature for BatchPropose for round" in row['Message']:
            round_number = int(row['Message'].split('profiling - broadcast signature for BatchPropose for round ')[1].split(',')[0])
            peer_ip = row['Message'].split('peer_ip ')[1]

            if round_number not in rounds:
                rounds[round_number] = Round(round_number)

            rounds[round_number].process_batch_propose_from_peer_end_times[peer_ip] = row['Timestamp']

        # if message format: info!("profiling - fetching transmissions from BatchPropose for round {} and peer_ip {}", batch_propose.round, peer_ip);
        if "profiling - fetching transmissions from BatchPropose for round" in row['Message']:
            round_number = int(row['Message'].split('profiling - fetching transmissions from BatchPropose for round ')[1].split(' and')[0])
            peer_ip = row['Message'].split('peer_ip ')[1]

            if round_number not in rounds:
                rounds[round_number] = Round(round_number)

            rounds[round_number].process_batch_propose_from_peer_fetching_transmissions_start_times[peer_ip] = row['Timestamp']

        # if message format: info!("profiling - fetched transmissions from BatchPropose for round {} and peer_ip {}", batch_propose.round, peer_ip);
        if "profiling - fetched transmissions from BatchPropose for round" in row['Message']:
            round_number = int(row['Message'].split('profiling - fetched transmissions from BatchPropose for round ')[1].split(' and')[0])
            peer_ip = row['Message'].split('peer_ip ')[1]

            if round_number not in rounds:
                rounds[round_number] = Round(round_number)

            # check if the peer_ip is already in rounds[round_number].process_batch_propose_from_peer_fetching_transmissions_end_times
            if peer_ip not in rounds[round_number].process_batch_propose_from_peer_fetching_transmissions_end_times:
                rounds[round_number].process_batch_propose_from_peer_fetching_transmissions_end_times[peer_ip] = row['Timestamp']

        # if message format: info!("profiling - received BatchSignature for round {}, peer_ip {}", batch_signature.round, peer_ip);
        if "profiling - received BatchSignature for round" in row['Message']:
            round_number = int(row['Message'].split('profiling - received BatchSignature for round ')[1].split(',')[0])
            peer_ip = row['Message'].split('peer_ip ')[1]

            if round_number not in rounds:
                rounds[round_number] = Round(round_number)

            rounds[round_number].process_batch_signature_from_peer_start_times[peer_ip] = row['Timestamp']

        # if message format: info!("profiling - processed BatchSignature for round {}, peer_ip {}", round, peer_ip);
        if "profiling - processed BatchSignature for round" in row['Message']:
            round_number = int(row['Message'].split('profiling - processed BatchSignature for round ')[1].split(',')[0])
            peer_ip = row['Message'].split('peer_ip ')[1]

            if round_number not in rounds:
                rounds[round_number] = Round(round_number)

            rounds[round_number].process_batch_signature_from_peer_end_times[peer_ip] = row['Timestamp']

        # if message format: info!("profiling - received BatchCertified for round {}, peer_ip {}", batch_certified.round, peer_ip);
        if "profiling - received BatchCertified for round" in row['Message']:
            round_number = int(row['Message'].split('profiling - received BatchCertified for round ')[1].split(',')[0])
            peer_ip = row['Message'].split('peer_ip ')[1]

            if round_number not in rounds:
                rounds[round_number] = Round(round_number)

            if peer_ip not in rounds[round_number].process_batch_certified_from_peer_start_times:
                rounds[round_number].process_batch_certified_from_peer_start_times[peer_ip] = row['Timestamp']
            else:
                print(f"Warning: peer_ip {peer_ip} already found in self.process_batch_certified_from_peer_start_times, round {round_number} - this might be expected")


        # if message format: info!("profiling - received PrimaryPing for round {}, peer_ip {}", round, peer_ip);
        if "profiling - received PrimaryPing for round" in row['Message']:
            round_number = int(row['Message'].split('profiling - received PrimaryPing for round ')[1].split(',')[0])
            peer_ip = row['Message'].split('peer_ip ')[1]

            if round_number not in rounds:
                rounds[round_number] = Round(round_number)

            if peer_ip not in rounds[round_number].process_batch_certified_from_peer_start_times:
                rounds[round_number].process_batch_certified_from_peer_start_times[peer_ip] = row['Timestamp']
            else:
                print(f"Warning: peer_ip {peer_ip} already found in self.process_batch_certified_from_peer_start_times, round {round_number} - this might be expected")

        # if message format: info!("profiling - processed BatchCertified for round {}, peer_ip {}", certificate_round, peer_ip);
        if "profiling - processed BatchCertified for round" in row['Message']:
            round_number = int(row['Message'].split('profiling - processed BatchCertified for round ')[1].split(',')[0])
            peer_ip = row['Message'].split('peer_ip ')[1]

            if round_number not in rounds:
                rounds[round_number] = Round(round_number)

            if peer_ip not in rounds[round_number].process_batch_certified_from_peer_end_times:
                rounds[round_number].process_batch_certified_from_peer_end_times[peer_ip] = row['Timestamp']
            else:
                print(f"Warning: peer_ip {peer_ip} already found in self.process_batch_certified_from_peer_end_times, round {round_number} - this might be expected")

        # if message format: info!("profiling - fetching transmissions from BatchCertificate for round {} and peer_ip {}", certificate_round, peer_ip);
        if "profiling - fetching transmissions from BatchCertificate for round" in row['Message']:
            round_number = int(row['Message'].split('profiling - fetching transmissions from BatchCertificate for round ')[1].split(' and')[0])
            peer_ip = row['Message'].split('peer_ip ')[1]

            if round_number not in rounds:
                rounds[round_number] = Round(round_number)

            if peer_ip not in rounds[round_number].process_batch_certified_from_peer_fetching_transmissions_start_times:
                rounds[round_number].process_batch_certified_from_peer_fetching_transmissions_start_times[peer_ip] = row['Timestamp']
            else:
                print(f"Warning: peer_ip {peer_ip} already found in self.process_batch_certified_from_peer_fetching_transmissions_start_times, round {round_number} - this might be expected")

        # if message format: info!("profiling - fetched transmissions from BatchCertificate for round {} and peer_ip {}", certificate_round, peer_ip);
        if "profiling - fetched transmissions from BatchCertificate for round" in row['Message']:
            round_number = int(row['Message'].split('profiling - fetched transmissions from BatchCertificate for round ')[1].split(' and')[0])
            peer_ip = row['Message'].split('peer_ip ')[1]

            if round_number not in rounds:
                rounds[round_number] = Round(round_number)

            if peer_ip not in rounds[round_number].process_batch_certified_from_peer_fetching_transmissions_end_times:
                rounds[round_number].process_batch_certified_from_peer_fetching_transmissions_end_times[peer_ip] = row['Timestamp']
            else:
                print(f"Warning: peer_ip {peer_ip} already found in self.process_batch_certified_from_peer_fetching_transmissions_end_times, round {round_number} - this might be expected")

    list_avg_propose_no_fetch = []
    list_avg_propose_fetch = []
    list_avg_signature = []
    list_avg_certified_no_fetch = []
    list_avg_certified_fetch = []

    # Iterate over rounds and plot the stacked bar chart
    for round_number in rounds:
        round = rounds[round_number]
        
        # Get the average duration of each event
        avg_propose_no_fetch = round.get_average_duration_in_process_batch_propose_from_peer_without_fetching_transmissions()
        avg_propose_fetch = round.get_average_duration_in_process_batch_propose_from_peer_fetching_transmissions()
        avg_signature = round.get_average_duration_in_process_batch_signature_from_peer() # only one working for 53
        avg_certified_no_fetch = round.get_average_duration_in_process_batch_certified_from_peer_without_fetching_transmissions()
        avg_certified_fetch = round.get_average_duration_in_process_batch_certified_from_peer_fetching_transmissions()

        list_avg_propose_no_fetch.append(avg_propose_no_fetch)
        list_avg_propose_fetch.append(avg_propose_fetch)
        list_avg_signature.append(avg_signature)
        list_avg_certified_no_fetch.append(avg_certified_no_fetch)
        list_avg_certified_fetch.append(avg_certified_fetch)

    return list_avg_propose_no_fetch, list_avg_propose_fetch, list_avg_signature, list_avg_certified_no_fetch, list_avg_certified_fetch

def plot_sync_times(list_avg_propose_no_fetch, list_avg_propose_fetch, list_avg_signature, list_avg_certified_no_fetch, list_avg_certified_fetch, avg_start_rounds, round_limit, logpath):

    # Plotting code cleanup
    fig, ax = plt.subplots(figsize=(10, 7))
    used_labels = {}

    # Define consistent colors for the bars
    colors = {
        "Process batch propose without fetching transmissions": 'tab:blue',
        "Process batch propose fetching transmissions": 'tab:orange',
        "Process batch signature": 'tab:green',
        "Process batch certified without fetching transmissions": 'tab:red',
        "Process batch certified fetching transmissions": 'tab:purple',
    }

    for i in range(len(list_avg_propose_no_fetch)):
        round_number = i + 1

        if(round_limit is not None and round_number > int(round_limit)):
            break

        # Plot each part of the stack with consistent color and proper bottom stacking
        bottom = 0
        if not np.isnan(list_avg_propose_no_fetch[round_number-1]):
            ax.bar(round_number, list_avg_propose_no_fetch[round_number-1], bottom=bottom, color=colors["Process batch propose without fetching transmissions"], 
                label="Process batch propose without fetching transmissions" if "Process batch propose without fetching transmissions" not in used_labels else "_nolegend_")
            bottom += list_avg_propose_no_fetch[round_number-1]
            used_labels["Process batch propose without fetching transmissions"] = True

        if not np.isnan(list_avg_propose_fetch[round_number-1]):
            ax.bar(round_number, list_avg_propose_fetch[round_number-1], bottom=bottom, color=colors["Process batch propose fetching transmissions"], 
                label="Process batch propose fetching transmissions" if "Process batch propose fetching transmissions" not in used_labels else "_nolegend_")
            bottom += list_avg_propose_fetch[round_number-1]
            used_labels["Process batch propose fetching transmissions"] = True

        if not np.isnan(list_avg_signature[round_number-1]):
            ax.bar(round_number, list_avg_signature[round_number-1], bottom=bottom, color=colors["Process batch signature"], 
                label="Process batch signature" if "Process batch signature" not in used_labels else "_nolegend_")
            bottom += list_avg_signature[round_number-1]
            used_labels["Process batch signature"] = True

        if not np.isnan(list_avg_certified_no_fetch[round_number-1]):
            ax.bar(round_number, list_avg_certified_no_fetch[round_number-1], bottom=bottom, color=colors["Process batch certified without fetching transmissions"], 
                label="Process batch certified without fetching transmissions" if "Process batch certified without fetching transmissions" not in used_labels else "_nolegend_")
            bottom += list_avg_certified_no_fetch[round_number-1]
            used_labels["Process batch certified without fetching transmissions"] = True

        if not np.isnan(list_avg_certified_fetch[round_number-1]):
            ax.bar(round_number, list_avg_certified_fetch[round_number-1], bottom=bottom, color=colors["Process batch certified fetching transmissions"], 
                label="Process batch certified fetching transmissions" if "Process batch certified fetching transmissions" not in used_labels else "_nolegend_")
            used_labels["Process batch certified fetching transmissions"] = True

    # Set the title and labels
    ax.set_title(f"Average peer message processing times of path {logpath}")
    ax.set_xlabel("Round index")
    ax.set_ylabel("Time (seconds)")

    # Show the legend
    ax.legend()

    # Display the plot
    plt.show()

    # Save the figure
    fig.savefig(f'1_stacked_bar_chart_sync_times_{logpath}.png')

    if round_limit is None:
        round_limit = len(list_avg_propose_no_fetch)
        print(f"Averages with start index {avg_start_rounds}")
    else:
        print(f"Averages with start index {avg_start_rounds}, end index {round_limit}")

    avg_start_rounds = int(avg_start_rounds)
    round_limit = int(round_limit)

    print(f"Average process batch propose without fetching transmissions: {np.mean(list_avg_propose_no_fetch[avg_start_rounds:round_limit])}")
    print(f"Average process batch propose fetching transmissions: {np.mean(list_avg_propose_fetch[avg_start_rounds:round_limit])}")
    print(f"Average process batch signature: {np.mean(list_avg_signature[avg_start_rounds:round_limit])}")
    print(f"Average process batch certified without fetching transmissions: {np.mean(list_avg_certified_no_fetch[avg_start_rounds:round_limit])}")
    print(f"Average process batch certified fetching transmissions: {np.mean(list_avg_certified_fetch[avg_start_rounds:round_limit])}")

# Run the main function
if __name__ == "__main__":
    main()