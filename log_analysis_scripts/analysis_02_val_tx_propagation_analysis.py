import argparse
import os
import pandas as pd
from datetime import datetime
import re
import json
from datetime import timedelta
import numpy as np
import re

class Transaction:
    def __init__(self, hash):
        self.hash = hash

        self.origin_val = -1
        self.origin_type = None
        self.val_0_generator_time = None
        self.val_0_broadcast_time = None
        self.endpoint_broadcast_time = None

        self.events_in_narwhal = {}
        self.events_in_narwhal_block = {}

        self.events_try_advance_to_next_block = {}
        self.min_date = None

        self.global_index = None

    def is_events_in_narwhal_block_complete(self, num_val):
        return len(self.events_in_narwhal_block) == num_val

    def is_events_in_narwhal_complete(self, num_val):
        return len(self.events_in_narwhal) == num_val

    def is_rest_complete(self, num_val):
        return self.origin_val != -1 and self.origin_type != None and len(self.events_try_advance_to_next_block) == num_val
    
    def is_all_complete(self, num_val):
        return self.is_events_in_narwhal_complete(num_val) and self.is_events_in_narwhal_block_complete(num_val) and self.is_rest_complete(num_val)
    
    def first_occurrence(self):
        # set min date to in 1 year
        min_date = datetime.now() + timedelta(days=365)
        # search entire self.events_in_narwhal for the first occurrence of the transaction
        for val_id in self.events_in_narwhal:
            for date in self.events_in_narwhal[val_id]:
                if date < min_date:
                    min_date = date
        if(self.val_0_generator_time != None and self.val_0_generator_time < min_date):
            min_date = self.val_0_generator_time
        if(self.val_0_broadcast_time != None and self.val_0_broadcast_time < min_date):
            min_date = self.val_0_broadcast_time
            print(f"Error: val_0_broadcast_time is before first occurrence, {self.hash}")
            exit(1)
        if(self.endpoint_broadcast_time != None and self.endpoint_broadcast_time < min_date):
            min_date = self.endpoint_broadcast_time

        self.min_date = min_date
        return min_date

    def last_occurrence_in_narwhal_block_complete(self):
        # set max date to 0
        max_date = datetime.fromtimestamp(0)
        # search entire self.events_in_narwhal_block for the last occurrence of the transaction
        for val_id in self.events_in_narwhal_block:
            for date in self.events_in_narwhal_block[val_id]:
                if date > max_date:
                    max_date = date
        return max_date
    
    def last_occurence_events_try_advance_to_next_block(self):
        # set max date to 0
        max_date = datetime.fromtimestamp(0)
        # search entire self.events_try_advance_to_next_block for the last occurrence of the transaction
        for val_id in self.events_try_advance_to_next_block:
            date = self.events_try_advance_to_next_block[val_id]
            if date > max_date:
                max_date = date
        return max_date
    
    def first_occurence_events_try_advance_to_next_block(self):
        # set min date to in 1 year
        min_date = datetime.now() + timedelta(days=365)
        # search entire self.events_try_advance_to_next_block for the first occurrence of the transaction
        for val_id in self.events_try_advance_to_next_block:
            date = self.events_try_advance_to_next_block[val_id]
            if date < min_date:
                min_date = date
        return min_date

    def time_all_validators_narwhal_block_complete_at_least_once(self):
        # set max date to 0
        max_date = datetime.fromtimestamp(0)
        # search entire self.events_in_narwhal_block for the last occurrence of the transaction
        for val_id in self.events_in_narwhal_block:
            date = self.events_in_narwhal_block[val_id][0]
            if date > max_date:
                max_date = date
        return max_date

def main():
    # Setup argument parser
    parser = argparse.ArgumentParser(description='Process log files and filter them by time.')
    parser.add_argument('--logpath', required=True, help='The relative path to the logs.')
    
    # Parse the arguments
    args = parser.parse_args()
    log_folder_path = args.logpath
    prepared_logs_path = os.path.join(os.getcwd(), log_folder_path)
    num_of_files = len([name for name in os.listdir(prepared_logs_path) if os.path.isfile(os.path.join(prepared_logs_path, name))])

    cutoff_seconds_after_first_val_ends = 5

    # load the pandas dataframes
    filtered_dfs = {}
    transactions = {}

    first_timestamp_dt = None
    last_timestamp_dt = None
    number_of_blocks = 999999999999999999999

    block_times = [[] for _ in range(num_of_files)]  # List to store block times for each validator

    for val_id in range(num_of_files):
        log_file_name = f"prepared_validator-{val_id}.log"
        log_file_path = os.path.join(os.getcwd(), "prepared_aws-logs", log_file_name)

        with open(log_file_path, 'r') as file:
            lines = file.readlines()

        # Assuming each line is a new entry and has a consistent format
        # We will split each line into a timestamp and a message
        data = [line.strip().split('  INFO ', 1) for line in lines if line.strip()]

        # Convert to DataFrame
        df = pd.DataFrame(data, columns=['Timestamp', 'Message'])

        first_time_this_val = df.iloc[0]['Timestamp'].rstrip("Z")
        first_timestamp_dt_this_val = datetime.fromisoformat(first_time_this_val)

        if first_timestamp_dt is None:
            first_timestamp_dt = first_timestamp_dt_this_val
        else:
            if first_timestamp_dt_this_val < first_timestamp_dt:
                first_timestamp_dt = first_timestamp_dt_this_val

        # find the last "Advanced to block" message in df
        advanced_block_indices = df[df['Message'].str.contains('Advanced to block', na=False)].index
        last_advanced_block_index = advanced_block_indices[-1] if len(advanced_block_indices) > 0 else None
        log = df.iloc[last_advanced_block_index]["Message"]
        block_number = re.search(r'Advanced to block (\d+)', log).group(1)
        if int(block_number) < number_of_blocks:
            number_of_blocks = int(block_number)

        filtered_df = df[df['Message'].str.contains('tx_propagation_logging-', na=False)]

        last_time_this_val = filtered_df.iloc[-1]['Timestamp'].rstrip("Z")
        last_timestamp_dt_this_val = datetime.fromisoformat(last_time_this_val)
        if last_timestamp_dt is None or last_timestamp_dt_this_val < last_timestamp_dt:
            last_timestamp_dt = last_timestamp_dt_this_val
        filtered_dfs[val_id] = filtered_df

        filtered_df_block_advancements = df[df['Message'].str.contains('Advanced to block ', na=False)]
        # Compute block times for each validator
        block_times[val_id] = [datetime.fromisoformat(filtered_df_block_advancements.iloc[i+1]['Timestamp'].rstrip("Z")) - datetime.fromisoformat(filtered_df_block_advancements.iloc[i]['Timestamp'].rstrip("Z"))
                            for i in range(len(filtered_df_block_advancements) - 1)]

    max_block_times = [max(block_times[i]) for i in range(num_of_files)]
    max_block_time = max(max_block_times)

    # remove cutoff_seconds_after_first_val_ends seconds from the last timestamp
    last_timestamp_dt = last_timestamp_dt - timedelta(seconds=cutoff_seconds_after_first_val_ends)

    for val_id in range(num_of_files):
        filtered_df = filtered_dfs[val_id]
        # iterate over the filtered dataframe
        for index, row in filtered_df.iterrows():


            message = row["Message"]
            timestamp_str = row["Timestamp"].rstrip("Z")
            timestamp_dt = datetime.fromisoformat(timestamp_str)

            if(timestamp_dt > last_timestamp_dt):
                break

            if "tx_propagation_logging-val_0_after_generation-" in message:
                tx_hash = message.split('"')[1]
                if(tx_hash in transactions):
                    print(f"Error: Transaction already exists, {tx_hash}")
                    exit(1)
                else:
                    transactions[tx_hash] = Transaction(tx_hash)
                    transactions[tx_hash].origin_val = val_id
                    transactions[tx_hash].origin_type = "val-0-generator"
                    transactions[tx_hash].val_0_generator_time = timestamp_dt

            elif "tx_propagation_logging-after-broadcast-endpoint-" in message:
                tx_hash = message.split('"')[1]
                if(tx_hash in transactions):
                    if(transactions[tx_hash].origin_type != None and transactions[tx_hash].origin_val != -1):
                        print(f"Error: Transaction already exists, {tx_hash}")
                        exit(1)
                    else:
                        transactions[tx_hash].origin_val = val_id
                        transactions[tx_hash].origin_type = "external"
                        transactions[tx_hash].endpoint_broadcast_time = timestamp_dt
                else:
                    transactions[tx_hash] = Transaction(tx_hash)
                    transactions[tx_hash].origin_val = val_id
                    transactions[tx_hash].origin_type = "external"
                    transactions[tx_hash].endpoint_broadcast_time = timestamp_dt

            elif "tx_propagation_logging-val_0_after_broadcast-" in message:
                tx_hash = message.split('"')[1]
                if(transactions[tx_hash].val_0_broadcast_time != None):
                    print(f"Error: Transaction already has a broadcast time, {tx_hash}")
                    exit(1)
                else:
                    transactions[tx_hash].val_0_broadcast_time = timestamp_dt

            elif "tx_propagation_logging-in_narwhal-" in message:
                match = re.search(r'\[.*?\]', message)
                tx_hashes = json.loads(match.group(0))
                for tx_hash in tx_hashes:
                    # get part before .
                    tx_hash = tx_hash.split(".")[0]
                    if(tx_hash not in transactions):
                        transactions[tx_hash] = Transaction(tx_hash)
                    if val_id not in transactions[tx_hash].events_in_narwhal:
                        transactions[tx_hash].events_in_narwhal[val_id] = [timestamp_dt]
                    else:
                        transactions[tx_hash].events_in_narwhal[val_id].append(timestamp_dt)

            elif "tx_propagation_logging-in_narwhal_block-" in message:
                match = re.search(r'\[.*?\]', message)
                tx_hashes = json.loads(match.group(0))
                for tx_hash in tx_hashes:
                    # get part before .
                    tx_hash = tx_hash.split(".")[0]
                    if(tx_hash not in transactions):
                        print(f"Error: Transaction in in_narwhal_block does not exist, {tx_hash}")
                        exit(1)
                    if val_id not in transactions[tx_hash].events_in_narwhal_block:
                        transactions[tx_hash].events_in_narwhal_block[val_id] = [timestamp_dt]
                    else:
                        transactions[tx_hash].events_in_narwhal_block[val_id].append(timestamp_dt)

            elif "tx_propagation_logging-try_advance_to_next_block-" in message:
                match = re.search(r'\[.*?\]', message)
                tx_hashes = json.loads(match.group(0))
                for tx_hash in tx_hashes:
                    # get part before .
                    tx_hash = tx_hash.split(".")[0]
                    if(tx_hash not in transactions):
                        transactions[tx_hash] = Transaction(tx_hash)
                        #print(f"Error: Transaction in in_narwhal_block does not exist, {tx_hash}")
                        #exit(1)

                    if(val_id in transactions[tx_hash].events_try_advance_to_next_block):
                        print(f"Error: Transaction already has a try_advance_to_next_block, {tx_hash} for val-{val_id}")
                        exit(1)
                    else:
                        transactions[tx_hash].events_try_advance_to_next_block[val_id] = timestamp_dt
            else:
                if(("tx_propagation_logging-add_unconfirmed_transaction- Added transaction to mempool. Transaction ID" in message) or message.startswith("request{method=POST uri=/mainnet/transaction/broadcast version=HTTP/1.1}: tx_propagation_logging-add_unconfirmed_transaction- Adde")):
                    continue
                else:
                    print(f"Error: Unknown message type, {message}")
                    exit(1)

    tx_times = []


    for transaction_hash in transactions:
        tx = transactions[transaction_hash]
        tx_times.append(tx.first_occurrence())

    # sort the list of transaction times
    tx_times_sorted = sorted(tx_times)

    for transaction_hash in transactions:
        tx = transactions[transaction_hash]
        # get index of tx.min_date in tx_times_sorted
        id = tx_times_sorted.index(tx.min_date)
        tx.global_index = id

    # iterate over transactions and get first 5 times that are generated externally
    external_tx_times = []
    for transaction_hash in transactions:
        tx = transactions[transaction_hash]
        if(tx.origin_type == "external"):
            external_tx_times.append(tx.min_date)
        
        if(len(external_tx_times) == 5):
            break

    oldest_external_tx_time = min(external_tx_times)
    id_of_oldest_external_tx = tx_times_sorted.index(oldest_external_tx_time)

    experiment_time_seconds = (last_timestamp_dt - first_timestamp_dt).total_seconds()

    print("\nStart presentation of stats")
    print(f"Number of validators: {num_of_files}")
    print(f"Number of transactions: {len(transactions)}")
    print(f"Number of blocks: {number_of_blocks}")
    print(f"Experiment time [h]: {round(experiment_time_seconds/3600, 2)}")
    print(f"Average TPS: {round(len(transactions)/experiment_time_seconds, 2)}")
    print(f"Average block time [s]: {round(experiment_time_seconds/number_of_blocks, 2)}")
    print(f"Max block time [s]: {round(max_block_time.total_seconds(), 2)}")
    print(f"Index of oldest transaction submitted to the REST endpoint (external): {id_of_oldest_external_tx} (due to tx cannon starting later)")

    num_complete_tx = 0
    num_incomplete_tx = 0

    for transaction_hash in transactions:
        tx = transactions[transaction_hash]
        if(tx.is_all_complete(num_of_files)):
            num_complete_tx += 1
        else:
            num_incomplete_tx += 1

    #print("\nRequirement: for a tx, all validators need to log tx hash after \"self.ledger.advance_to_next_block\"")

    num_complete_tx = 0
    num_incomplete_tx = 0

    oldest_complete_tx_time = None
    youngest_complete_tx_time = None
    oldest_incomplete_tx_time = None
    youngest_incomplete_tx_time = None

    fastest_complete_tx_time = None
    slowest_complete_tx_time = None

    tx_count = 0

    tx_count_complete = []
    tx_count_incomplete = []

    times_to_complete_seconds = []

    tx_complete = []
    tx_incomplete = []

    for transaction_hash in transactions:
        tx = transactions[transaction_hash]
        if(tx.is_rest_complete(num_of_files)):
            num_complete_tx += 1
            if(oldest_complete_tx_time == None or tx.first_occurrence() < oldest_complete_tx_time):
                oldest_complete_tx_time = tx.first_occurrence()
            if(youngest_complete_tx_time == None or tx.first_occurrence() > youngest_complete_tx_time):
                youngest_complete_tx_time = tx.first_occurrence()

            time_to_complete = tx.last_occurence_events_try_advance_to_next_block() - tx.first_occurrence()
            if(fastest_complete_tx_time == None or time_to_complete < fastest_complete_tx_time):
                fastest_complete_tx_time = time_to_complete
            if(slowest_complete_tx_time == None or time_to_complete > slowest_complete_tx_time):
                slowest_complete_tx_time = time_to_complete
            times_to_complete_seconds.append(time_to_complete.total_seconds())

            tx_count_complete.append(tx.global_index)
            tx_complete.append(tx)
        else:
            num_incomplete_tx += 1
            if(oldest_incomplete_tx_time == None or tx.first_occurrence() < oldest_incomplete_tx_time):
                oldest_incomplete_tx_time = tx.first_occurrence()
            if(youngest_incomplete_tx_time == None or tx.first_occurrence() > youngest_incomplete_tx_time):
                youngest_incomplete_tx_time = tx.first_occurrence()
            
            tx_count_incomplete.append(tx.global_index)
            tx_incomplete.append(tx)

        tx_count += 1

    # sort tx_count_complete and tx_count_incomplete
    tx_count_complete = sorted(tx_count_complete)
    tx_count_incomplete = sorted(tx_count_incomplete)

    print(f"\nComplete transactions: {num_complete_tx}, first five indices: {tx_count_complete[:5]}")
    print(f"Incomplete transactions: {num_incomplete_tx}, indices: {tx_count_incomplete}")

    incomplete_transactions_cutoff_index = len(transactions) - 100
    incomplete_transactions_cutoff_index = max(incomplete_transactions_cutoff_index, 0)
    # remove indices that are larger than incomplete_transactions_cutoff_index
    tx_count_incomplete_cutoff = [i for i in tx_count_incomplete if i < incomplete_transactions_cutoff_index]
    if(len(tx_count_incomplete_cutoff) > 0):
        print(f"\tAnalyzing non-recent incomplete transactions in more depth:")
        for index in tx_count_incomplete_cutoff:
            # find tx with global_index == index
            for transaction_hash in transactions:
                tx = transactions[transaction_hash]
                if(tx.global_index == index):
                    #print(f"\t\t\tTransaction hash: {transaction_hash}, first occurrence: {tx.first_occurrence()}")
                    age_seconds = (last_timestamp_dt - tx.min_date).total_seconds()
                    print(f"\t\tIndex: {tx.global_index}, origin type: {tx.origin_type}, origin validator index: {tx.origin_val}, made it into Narwhal: {len(tx.events_in_narwhal)>0 or len(tx.events_in_narwhal_block)>0}, age [s]: {round(age_seconds,2)}, hash: {transaction_hash[0:12]}...")
                    break
    else:
        print(f"\t\tNo non-recent incomplete transactions")


    print("\nTime to complete a transaction from first occurrence in logs to last occurrence of \"try_advance_to_next_block\" log [seconds]:")
    print(f"\tAverage: {round(np.mean(times_to_complete_seconds), 2)}")
    print(f"\tStandard deviation: {round(np.std(times_to_complete_seconds), 2)}")
    print(f"\tMedian: {round(np.median(times_to_complete_seconds), 2)}")
    print(f"\tFastest tx: {round(fastest_complete_tx_time.total_seconds(), 2)}")
    print(f"\tSlowest tx: {round(slowest_complete_tx_time.total_seconds(), 2)}")

    print("\nTransaction ages at experiment cutoff time: [seconds]")
    # compute age of oldest and youngest complete transactions at last_timestamp_dt
    oldest_complete_tx_age = (last_timestamp_dt - oldest_complete_tx_time).total_seconds()
    youngest_complete_tx_age = (last_timestamp_dt - youngest_complete_tx_time).total_seconds()
    print(f"\tOldest complete tx age: {round(oldest_complete_tx_age, 2)}")
    print(f"\tYoungest complete tx age: {round(youngest_complete_tx_age, 2)}")
    if(num_incomplete_tx > 0):
        oldest_incomplete_tx_age = (last_timestamp_dt - oldest_incomplete_tx_time).total_seconds()
        youngest_incomplete_tx_age = (last_timestamp_dt - youngest_incomplete_tx_time).total_seconds()
        print(f"\tOldest incomplete tx age: {round(oldest_incomplete_tx_age, 2)}")
        print(f"\tYoungest incomplete tx age: {round(youngest_incomplete_tx_age, 2)}")

    # histogram of origin_type in tx_incomplete
    origin_type_in_tx_incomplete = []
    for tx in tx_incomplete:
        origin_type_in_tx_incomplete.append(tx.origin_type)

    # count frequency of origin_type_in_tx_incomplete
    origin_type_in_tx_incomplete_count = {}
    for origin_type in origin_type_in_tx_incomplete:
        if origin_type in origin_type_in_tx_incomplete_count:
            origin_type_in_tx_incomplete_count[origin_type] += 1
        else:
            origin_type_in_tx_incomplete_count[origin_type] = 1


    # plot histogram of times_to_complete_seconds
    import matplotlib.pyplot as plt

    plt.hist(times_to_complete_seconds, bins=100)
    plt.xlabel("Time to complete a transaction [seconds]")
    plt.ylabel("Number of transactions")
    plt.title("Histogram of time to complete a transaction")
    #plt.yscale("log")  # Set y-axis to logarithmic scale
    plt.savefig("histogram.png")
    plt.show()

    # save the plot

    num_tx = len(transactions)
    counter = 0
    cutoff_analysis = int(0.8*num_tx)

    tx_number_with_0_events_try_advance_to_next_block = []
    tx_number_with_0_events_try_advance_to_next_block_origin_type = []

    max_logs_events_in_narwhal_for_a_val = 0
    max_logs_events_in_narwhal_block_for_a_val = 0

    tx_not_logging_6 = []

    for transaction_hash in transactions:
        tx = transactions[transaction_hash]

        if(tx.global_index > cutoff_analysis):
            continue

        events_in_narwhal = tx.events_in_narwhal
        for val in events_in_narwhal:
            val_event = events_in_narwhal[val]
            max_logs_events_in_narwhal_for_a_val = max(max_logs_events_in_narwhal_for_a_val, len(val_event))
        
        events_in_narwhal_block = tx.events_in_narwhal_block
        for val in events_in_narwhal_block:
            val_event = events_in_narwhal_block[val]
            max_logs_events_in_narwhal_block_for_a_val = max(max_logs_events_in_narwhal_block_for_a_val, len(val_event))

        events_try_advance_to_next_block = tx.events_try_advance_to_next_block
        if(len(events_try_advance_to_next_block) == 0):

            # get id of tx.min_date in tx_times_sorted
            id = tx.global_index

            tx_number_with_0_events_try_advance_to_next_block.append(id)
            tx_number_with_0_events_try_advance_to_next_block_origin_type.append(tx.origin_type)
            #print(f"Id: {id}, origin type: {tx.origin_type}, val: {tx.origin_val}, len(events_in_narwhal): {len(events_in_narwhal)}, len(events_in_narwhal_block): {len(events_in_narwhal_block)}")
            tx_not_logging_6.append(tx)

        counter += 1


    print("\nMaximum # of Narwhal logs for a transaction in a single validator:")

    print("\tIn propose_batch: ", max_logs_events_in_narwhal_for_a_val)
    print("\tIn process_batch_signature_from_peer: ", max_logs_events_in_narwhal_block_for_a_val)

    print("\nEnd presentation of stats")

    # count tx_number_with_0_events_try_advance_to_next_block_origin_type occurrences
    count_external = 0
    count_val_0_generator = 0
    for origin_type in tx_number_with_0_events_try_advance_to_next_block_origin_type:
        if(origin_type == "external"):
            count_external += 1
        elif(origin_type == "val-0-generator"):
            count_val_0_generator += 1

    # index of "external" in tx_number_with_0_events_try_advance_to_next_block_origin_type
    index_external = [i for i, x in enumerate(tx_number_with_0_events_try_advance_to_next_block_origin_type) if x == "external"]

    # iterate over each tx in tx_not_logging_6, then plot the length of their events_in_narwhal and events_in_narwhal_block
    import matplotlib.pyplot as plt

    # store the lengths of events_in_narwhal and events_in_narwhal_block
    events_in_narwhal_len = []
    events_in_narwhal_block_len = []
    for tx in tx_not_logging_6:
        len1 = len(tx.events_in_narwhal)
        len2 = len(tx.events_in_narwhal_block)

        events_in_narwhal_len.append(len1)
        events_in_narwhal_block_len.append(len2)

    # plot the lengths of events_in_narwhal and events_in_narwhal_block
    plt.plot(events_in_narwhal_len, label="events_in_narwhal")
    plt.plot(events_in_narwhal_block_len, label="events_in_narwhal_block")
    plt.xlabel("Transaction count")
    plt.ylabel("Number of validators")
    plt.title("Number of validators logging events_in_narwhal and\nevents_in_narwhal_block for a transaction that doesn't make it into a block")
    plt.legend()
    plt.show()

    # save the plot
    plt.savefig("events_in_narwhal_and_events_in_narwhal_block.png")

# Run the main function
if __name__ == "__main__":
    main()