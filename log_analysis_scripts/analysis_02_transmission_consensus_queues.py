import argparse
import os
import pandas as pd
import numpy as np

def main():
    # Setup argument parser
    parser = argparse.ArgumentParser(description='Process log files and filter them by time.')
    parser.add_argument('--logfile', required=True, help='The relative path to the log file.')

    # Parse the arguments
    args = parser.parse_args()
    log_folder_path = args.logfile

    log_file_path = os.path.join(os.getcwd(), log_folder_path)

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
        "Received unconfirmed transaction",
        "Sending request for transmission",
    ]

    event_df = df[df['Message'].str.contains('|'.join(events), na=False)]

    unconfirmed_tx_dict = {}
    sending_request_dict = {}

    for i, row in event_df.iterrows():
        if "Received unconfirmed transaction" in row['Message']:
            # format: Received unconfirmed transaction 'at1dwyav5uvy2wmm..' in the queue
            tx_hash = row['Message'].split('Received unconfirmed transaction ')[1].split(' in the queue')[0]
            # remove ' and .. from the tx_hash
            tx_hash = tx_hash[1:-3]
            unconfirmed_tx_dict[tx_hash] = row['Timestamp']
        elif "Sending request for transmission" in row['Message']:
            # format: Sending request for transmission at1lt805lhty9z5a...
            tx_hash = row['Message'].split('Sending request for transmission ')[1]
            # split after .
            tx_hash = tx_hash.split('.')[0]
            sending_request_dict[tx_hash] = row['Timestamp']
    
    i = 0

    for key in sending_request_dict:
        time_sending_request = sending_request_dict[key]
        if key in unconfirmed_tx_dict:
            time_unconfirmed_tx = unconfirmed_tx_dict[key]
            if(time_unconfirmed_tx < time_sending_request):
                # indicating that the unconfirmed transaction was in the mempool before the sending request
                i += 1

    print(f"Number of TXs in unconfirmed_tx_dict: {len(unconfirmed_tx_dict)} (in mempool)")
    print(f"Number of TXs in sending_request_dict: {len(sending_request_dict)} (sending request)")
    print(f"Number of TXs found in both dicts: {i}")
    if len(sending_request_dict) > 0:
        print(f"\tShare of sending_request_dict: {i/len(sending_request_dict)*100:.2f}%")
    else:
        print(f"\tShare of sending_request_dict is undefined.")
    if len(unconfirmed_tx_dict) > 0:
        print(f"\tShare of unconfirmed_tx_dict: {i/len(unconfirmed_tx_dict)*100:.2f}%")
    else:
        print(f"\tShare of unconfirmed_tx_dict is undefined.")

# Run the main function
if __name__ == "__main__":
    main()