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

    def get_average_duration_in_process_batch_propose_from_peer_fetching_transmissions(self):
        durations = []
        # iterate over peer_ips in self.process_batch_propose_from_peer_fetching_transmissions_start_times
        for peer_ip in self.process_batch_propose_from_peer_fetching_transmissions_start_times:
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
    
    def get_average_duration_in_process_batch_certified_from_peer(self):
        durations = []
        # iterate over peer_ips in self.process_batch_certified_from_peer_start_times
        for peer_ip in self.process_batch_certified_from_peer_start_times:
            # check if the peer_ip is in self.process_batch_certified_from_peer_end_times
            if peer_ip in self.process_batch_certified_from_peer_end_times:
                # calculate the duration and append it to durations
                durations.append((self.process_batch_certified_from_peer_end_times[peer_ip] - self.process_batch_certified_from_peer_start_times[peer_ip]).total_seconds())
            else:
                print(f"Error: peer_ip {peer_ip} not found in self.process_batch_certified_from_peer_end_times, round {self.round_number}")
        # return the average of durations
        return np.mean(durations)


def main():
    # Setup argument parser
    parser = argparse.ArgumentParser(description='Process log files and filter them by time.')
    parser.add_argument('--logfile', required=True, help='The relative path to the log file.')

    # Parse the arguments
    args = parser.parse_args()
    log_folder_path = args.logfile

    log_file_path = os.path.join(os.getcwd(), log_folder_path)
    log_filename = os.path.basename(log_file_path)

    # Check if the log file exists
    if not os.path.exists(log_file_path):
        print(f"Log file {log_file_path} does not exist.")
        print(f"Absolute path: {os.path.abspath(log_file_path)}")
        print("Exiting...")
        return

    # Load the log file
    with open(log_file_path, 'r') as file:
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

            rounds[round_number].process_batch_propose_from_peer_start_times[peer_ip] = row['Timestamp']
        
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

            rounds[round_number].process_batch_certified_from_peer_start_times[peer_ip] = row['Timestamp']

        # if message format: info!("profiling - processed BatchCertified for round {}, peer_ip {}", certificate_round, peer_ip);
        if "profiling - processed BatchCertified for round" in row['Message']:
            round_number = int(row['Message'].split('profiling - processed BatchCertified for round ')[1].split(',')[0])
            peer_ip = row['Message'].split('peer_ip ')[1]

            if round_number not in rounds:
                rounds[round_number] = Round(round_number)

            rounds[round_number].process_batch_certified_from_peer_end_times[peer_ip] = row['Timestamp']


    # Plotting code cleanup
    fig, ax = plt.subplots(figsize=(10, 7))
    used_labels = {}

    # Define consistent colors for the bars
    colors = {
        "Process batch propose without fetching transmissions": 'tab:blue',
        "Process batch propose fetching transmissions": 'tab:orange',
        "Process batch signature": 'tab:green',
        "Process batch certified": 'tab:red'
    }

    # Iterate over rounds and plot the stacked bar chart
    for round_number in rounds:
        round = rounds[round_number]
        
        # Get the average duration of each event
        avg_propose_no_fetch = round.get_average_duration_in_process_batch_propose_from_peer_without_fetching_transmissions()
        avg_propose_fetch = round.get_average_duration_in_process_batch_propose_from_peer_fetching_transmissions()
        avg_signature = round.get_average_duration_in_process_batch_signature_from_peer()
        avg_certified = round.get_average_duration_in_process_batch_certified_from_peer()

        # if values are nan, set them to 0
        if np.isnan(avg_propose_no_fetch):
            avg_propose_no_fetch = 0
        if np.isnan(avg_propose_fetch):
            avg_propose_fetch = 0
        if np.isnan(avg_signature):
            avg_signature = 0
        if np.isnan(avg_certified):
            avg_certified = 0

        # Plot each part of the stack with consistent color and proper bottom stacking
        bottom = 0
        ax.bar(round_number, avg_propose_no_fetch, bottom=bottom, color=colors["Process batch propose without fetching transmissions"], 
            label="Process batch propose without fetching transmissions" if "Process batch propose without fetching transmissions" not in used_labels else "_nolegend_")
        bottom += avg_propose_no_fetch

        ax.bar(round_number, avg_propose_fetch, bottom=bottom, color=colors["Process batch propose fetching transmissions"], 
            label="Process batch propose fetching transmissions" if "Process batch propose fetching transmissions" not in used_labels else "_nolegend_")
        bottom += avg_propose_fetch

        ax.bar(round_number, avg_signature, bottom=bottom, color=colors["Process batch signature"], 
            label="Process batch signature" if "Process batch signature" not in used_labels else "_nolegend_")
        bottom += avg_signature

        ax.bar(round_number, avg_certified, bottom=bottom, color=colors["Process batch certified"], 
            label="Process batch certified" if "Process batch certified" not in used_labels else "_nolegend_")

        # Mark labels as used
        used_labels["Process batch propose without fetching transmissions"] = True
        used_labels["Process batch propose fetching transmissions"] = True
        used_labels["Process batch signature"] = True
        used_labels["Process batch certified"] = True

    # Set the title and labels
    ax.set_title(f"Average peer message processing times of validator {log_filename}")
    ax.set_xlabel("Round index")
    ax.set_ylabel("Time (seconds)")

    # Show the legend
    ax.legend()

    # Display the plot
    plt.show()

    # Save the figure
    fig.savefig(f'1_stacked_bar_chart_sync_times_val{log_filename}.png')

# Run the main function
if __name__ == "__main__":
    main()