import argparse
import os
import pandas as pd
import matplotlib.pyplot as plt

def get_rounds_for_blocks(df):
    rounds_for_blocks = {}

    # filter for "Advanced to block" logs
    advanced_to_block = df[df['Message'].str.contains('Advanced to block', na=False)]

    # get the round number for each block
    previous_round = 1
    for i, row in advanced_to_block.iterrows():
        block_height = int(row['Message'].split('Advanced to block ')[1].split(' at round')[0])
        round_number = int(row['Message'].split(' at round ')[1].split(' ')[0])
        rounds_for_blocks[block_height] = [j for j in range(previous_round, round_number+1)]
        previous_round = round_number + 1

    return rounds_for_blocks

def get_block_times(df):
    block_times = {}

    # filter for "Advanced to block" logs
    advanced_to_block = df[df['Message'].str.contains('Advanced to block', na=False)]
    previous_timestamp = None

    for i, row in advanced_to_block.iterrows():
        block_height = int(row['Message'].split('Advanced to block ')[1].split(' at round')[0])
        round_number = int(row['Message'].split(' at round ')[1].split(' ')[0])
        if previous_timestamp is not None:
            block_times[block_height] = (row['Timestamp'] - previous_timestamp).total_seconds()
        previous_timestamp = row['Timestamp']

    return block_times

def get_block_transmission_numbers(df):
    block_transmission_numbers = {}

    # filter for "Advanced to block" logs
    advanced_to_block = df[df['Message'].str.contains('Advanced to block', na=False)]
    for i, row in advanced_to_block.iterrows():
        block_height = int(row['Message'].split('Advanced to block ')[1].split(' at round')[0])
        transmissions_number = int(row['Message'].split('number of transmissions: ')[1].split(' ')[0])
        block_transmission_numbers[block_height] = transmissions_number

    return block_transmission_numbers

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
        "profiling",
        "Advanced to block",
    ]

    event_df = df[df['Message'].str.contains('|'.join(events), na=False)]

    rounds_for_blocks = get_rounds_for_blocks(event_df)

    fig, ax = plt.subplots(figsize=(10, 7))
    ax.legend()
    used_labels = {}

    start_time = event_df.iloc[0]['Timestamp']

    time_ending_proposal_gen = event_df[event_df['Message'].str.contains('profiling - ending proposal generation for round', na=False)]
    for i, row in time_ending_proposal_gen.iterrows():
        round = int(row['Message'].split('round ')[1].split(',')[0])

        # find exact log - starting proposal generation for round {round} in event_df
        time_starting_proposal_gen = event_df[event_df['Message'] == f'profiling - starting proposal generation for round {round}']["Timestamp"]

        x_bar_start = round - 0.5
        x_bar_end = round + 0.5
        y_bar_start = (time_starting_proposal_gen.iloc[0] - start_time).total_seconds()
        y_bar_end = (row["Timestamp"] - start_time).total_seconds()

        # make a bar plot
        label = 'Proposal generation'
        if label not in used_labels:
            ax.bar((x_bar_end+x_bar_start)/2, y_bar_end-y_bar_start, bottom=y_bar_start, width=x_bar_end-x_bar_start, label=label, color='tab:blue')
            used_labels[label] = True
        else:
            ax.bar((x_bar_end+x_bar_start)/2, y_bar_end-y_bar_start, bottom=y_bar_start, width=x_bar_end-x_bar_start, color='tab:blue')


    time_ending_certificate_gen = event_df[event_df['Message'].str.contains('profiling - ending certificate generation for round', na=False)]
    
    for i, row in time_ending_certificate_gen.iterrows():
        round = int(row['Message'].split('round ')[1].split(',')[0])

        time_starting_certificate_gen = event_df[event_df['Message'] == f'profiling - starting certificate generation for round {round}']["Timestamp"]

        x_bar_start = round - 0.5
        x_bar_end = round + 0.5
        y_bar_start = (time_starting_certificate_gen.iloc[0] - start_time).total_seconds()
        y_bar_end = (row["Timestamp"] - start_time).total_seconds()

        # make a bar plot
        label = 'Certificate generation'
        if label not in used_labels:
            ax.bar((x_bar_end+x_bar_start)/2, y_bar_end-y_bar_start, bottom=y_bar_start, width=x_bar_end-x_bar_start, label=label, color='tab:green')
            used_labels[label] = True
        else:
            ax.bar((x_bar_end+x_bar_start)/2, y_bar_end-y_bar_start, bottom=y_bar_start, width=x_bar_end-x_bar_start, color='tab:green')


    time_ending_certificate_col = event_df[event_df['Message'].str.contains('profiling - ending certificate collection for round', na=False)]
    
    for i, row in time_ending_certificate_col.iterrows():
        round = int(row['Message'].split('round ')[1].split(',')[0])

        time_starting_certificate_col = event_df[event_df['Message'] == f'profiling - starting certificate collection for round {round}']["Timestamp"]

        if(len(time_starting_certificate_col) > 0): # to discuss - should we do something if no starting certificate collection log is found?
            x_bar_start = round - 0.5
            x_bar_end = round + 0.5
            y_bar_start = (time_starting_certificate_col.iloc[0] - start_time).total_seconds()
            y_bar_end = (row["Timestamp"] - start_time).total_seconds()

            # make a bar plot
            label = 'Certificate collection'
            if label not in used_labels:
                ax.bar((x_bar_end+x_bar_start)/2, y_bar_end-y_bar_start, bottom=y_bar_start, width=x_bar_end-x_bar_start, label=label, color='tab:red')
                used_labels[label] = True
            else:
                ax.bar((x_bar_end+x_bar_start)/2, y_bar_end-y_bar_start, bottom=y_bar_start, width=x_bar_end-x_bar_start, color='tab:red')


    time_ending_certificate_col = event_df[event_df['Message'].str.contains('profiling - ending certificate collection for round', na=False)]
    
    for i, row in time_ending_certificate_col.iterrows():
        round = int(row['Message'].split('round ')[1].split(',')[0])

        # get index label of the row in event_df
        index_label = row.name

        # get the integer position of the index label
        index_position = event_df.index.get_loc(index_label)

        # get event_df after the row
        event_df_after = event_df.iloc[index_position + 1:]

        # find the next "profiling - starting prepare_advance_to_next_quorum_block" in event_df_after
        time_prepare_adv_next_quorum_block = event_df_after[event_df_after['Message'] == f'profiling - starting prepare_advance_to_next_quorum_block']["Timestamp"]

        if(len(time_prepare_adv_next_quorum_block) > 0): # to discuss - should we do something if no prepare_advance_to_next_quorum_block log is found?
            x_bar_start = round - 0.5
            x_bar_end = round + 0.5
            y_bar_start = (row["Timestamp"] - start_time).total_seconds()
            y_bar_end = (time_prepare_adv_next_quorum_block.iloc[0] - start_time).total_seconds()

            # make a bar plot
            label = 'Processing subdag'
            if label not in used_labels:
                ax.bar((x_bar_end+x_bar_start)/2, y_bar_end-y_bar_start, bottom=y_bar_start, width=x_bar_end-x_bar_start, label=label, color='tab:orange')
                used_labels[label] = True
            else:
                ax.bar((x_bar_end+x_bar_start)/2, y_bar_end-y_bar_start, bottom=y_bar_start, width=x_bar_end-x_bar_start, color='tab:orange')

        # make a light grey bar at round - 0.5 from (row["Timestamp"] - start_time).total_seconds() to 0
        x_bar_start = round - 0.5
        x_bar_end = round - 0.4
        y_bar_start = (row["Timestamp"] - start_time).total_seconds()
        y_bar_end = 0
        ax.bar((x_bar_end+x_bar_start)/2, y_bar_end-y_bar_start, bottom=y_bar_start, width=x_bar_end-x_bar_start, color='lightgrey')

    time_starting_prepare_adv_to_next_quorum_block = event_df[event_df['Message'].str.contains('profiling - starting prepare_advance_to_next_quorum_block', na=False)]
    
    for i, row in time_starting_prepare_adv_to_next_quorum_block.iterrows():
        # get index label of the row in event_df
        index_label = row.name

        # get the integer position of the index label
        index_position = event_df.index.get_loc(index_label)

        # get event_df after the row
        event_df_after = event_df.iloc[index_position + 1:]

        # find the next "profiling - ending prepare_advance_to_next_quorum_block for block" in event_df_after
        entry_prepare_adv_next_quorum_block = event_df_after[event_df_after['Message'].str.contains('profiling - ending prepare_advance_to_next_quorum_block for block', na=False)]
        time_prepare_adv_next_quorum_block = entry_prepare_adv_next_quorum_block["Timestamp"]
        log_prepare_adv_next_quorum_block = entry_prepare_adv_next_quorum_block["Message"]

        block_height = int(log_prepare_adv_next_quorum_block.iloc[0].split('for block ')[1])

        round_numbers = rounds_for_blocks[block_height]
        round_start = round_numbers[0]
        round_end = round_numbers[-1]

        x_bar_start = round_start - 0.5
        x_bar_end = round_end + 0.5
        y_bar_start = (row["Timestamp"] - start_time).total_seconds()
        y_bar_end = (time_prepare_adv_next_quorum_block.iloc[0] - start_time).total_seconds()

        # make a bar plot
        label = 'Prepare advance to next quorum block'
        if label not in used_labels:
            ax.bar((x_bar_end+x_bar_start)/2, y_bar_end-y_bar_start, bottom=y_bar_start, width=x_bar_end-x_bar_start, label=label, color='tab:purple')
            used_labels[label] = True
        else:
            ax.bar((x_bar_end+x_bar_start)/2, y_bar_end-y_bar_start, bottom=y_bar_start, width=x_bar_end-x_bar_start, color='tab:purple')


    times_start = event_df[event_df['Message'].str.contains('starting check_next_block for block', na=False)]
    
    for i, row in times_start.iterrows():

        block_height = int(row['Message'].split('for block ')[1])

        # get index label of the row in event_df
        index_label = row.name

        # get the integer position of the index label
        index_position = event_df.index.get_loc(index_label)

        # get event_df after the row
        event_df_after = event_df.iloc[index_position + 1:]

        # find the next "profiling - ending prepare_advance_to_next_quorum_block for block" in event_df_after
        entry = event_df_after[event_df_after['Message'] == f'profiling - ending check_next_block for block {block_height}']
        time_end = entry["Timestamp"]
        log_prepare_adv_next_quorum_block = entry["Message"]

        round_numbers = rounds_for_blocks[block_height]
        round_start = round_numbers[0]
        round_end = round_numbers[-1]

        x_bar_start = round_start - 0.5
        x_bar_end = round_end + 0.5
        y_bar_start = (row["Timestamp"] - start_time).total_seconds()
        y_bar_end = (time_end.iloc[0] - start_time).total_seconds()

        # make a bar plot
        label = 'Check next block'
        if label not in used_labels:
            ax.bar((x_bar_end+x_bar_start)/2, y_bar_end-y_bar_start, bottom=y_bar_start, width=x_bar_end-x_bar_start, label=label, color='tab:cyan')
            used_labels[label] = True
        else:
            ax.bar((x_bar_end+x_bar_start)/2, y_bar_end-y_bar_start, bottom=y_bar_start, width=x_bar_end-x_bar_start, color='tab:cyan')

    

    times_start = event_df[event_df['Message'].str.contains('starting advance_to_next_block for block', na=False)]
    for i, row in times_start.iterrows():

        block_height = int(row['Message'].split('for block ')[1])

        # get index label of the row in event_df
        index_label = row.name

        # get the integer position of the index label
        index_position = event_df.index.get_loc(index_label)

        # get event_df after the row
        event_df_after = event_df.iloc[index_position + 1:]

        # find the next "profiling - ending prepare_advance_to_next_quorum_block for block" in event_df_after
        entry = event_df_after[event_df_after['Message'] == f'profiling - ending advance_to_next_block for block {block_height}']
        time_end = entry["Timestamp"]
        log_prepare_adv_next_quorum_block = entry["Message"]

        round_numbers = rounds_for_blocks[block_height]
        round_start = round_numbers[0]
        round_end = round_numbers[-1]

        x_bar_start = round_start - 0.5
        x_bar_end = round_end + 0.5
        y_bar_start = (row["Timestamp"] - start_time).total_seconds()
        y_bar_end = (time_end.iloc[0] - start_time).total_seconds()

        # make a bar plot
        label = 'Advance to next block'
        if label not in used_labels:
            ax.bar((x_bar_end+x_bar_start)/2, y_bar_end-y_bar_start, bottom=y_bar_start, width=x_bar_end-x_bar_start, label=label, color='magenta')
            used_labels[label] = True
        else:
            ax.bar((x_bar_end+x_bar_start)/2, y_bar_end-y_bar_start, bottom=y_bar_start, width=x_bar_end-x_bar_start, color='magenta')
    
    # plot legend
    ax.legend()
    # Set the title and labels
    ax.set_title(f"Consensus process of validator {log_filename}")
    ax.set_xlabel("Round index")
    ax.set_ylabel("Time (seconds)")

    # show the plot
    plt.show()

    # Save the figure
    fig.savefig(f'1_val_consensus_profiling_{log_filename}.png')


    # Another figure with block times
    block_times = get_block_times(event_df)

    fig, ax = plt.subplots(figsize=(10, 7))
    ax.bar(block_times.keys(), block_times.values())
    ax.set_title(f"Block times of validator {log_filename}")
    ax.set_xlabel("Block index")
    ax.set_ylabel("Time (seconds)")
    plt.show()

    fig.savefig(f'2_val_block_times_{log_filename}.png')


    # Another bar chart with number of transmissions per block
    num_transmissions = get_block_transmission_numbers(event_df)
    fig, ax = plt.subplots(figsize=(10, 7))

    # Bar chart
    #ax.bar(block_heights, [block.num_transmissions for block in blocks.values()], label='Number of Transmissions')
    ax.bar(num_transmissions.keys(), num_transmissions.values(), label='Number of transmissions')

    # Add labels and title
    ax.set_xlabel('Block Height')
    ax.set_ylabel('Number of transmissions')
    ax.set_title(f'Number of transmissions per block, file {log_filename}')
    ax.legend()

    # Display the plot
    plt.show()
    # save the figure
    fig.savefig(f'3_block_num_transmissions_{log_filename}.png')


    # Display number of associated rounds per block in a bar chart
    fig, ax = plt.subplots(figsize=(10, 7))

    # Bar chart, use rounds_for_blocks for it
    p1 = ax.bar(rounds_for_blocks.keys(), [len(rounds) for rounds in rounds_for_blocks.values()], label='Number of associated Rounds')

    # Add labels and title
    ax.set_xlabel('Block Height')
    ax.set_ylabel('Number of associated rounds')
    ax.set_title(f'Number of associated rounds per block, file {log_filename}')
    ax.legend()

    # Display the plot
    plt.show()
    # save the figure
    fig.savefig(f'4_block_associated_rounds_{log_filename}.png')


# Run the main function
if __name__ == "__main__":
    main()