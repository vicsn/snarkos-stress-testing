import os
import pandas as pd
import matplotlib.pyplot as plt
import copy
import numpy as np

# Set the variables
num_val = 25
val_index = 0
log_file_name = f"prepared_logs_{val_index}.log"
log_file_path = os.path.join(os.getcwd(), "..", "terraform", "aws-logs", log_file_name)

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

# Convert to DataFrame
df = pd.DataFrame(data, columns=['Timestamp', 'Message'])
df['Timestamp'] = pd.to_datetime(df['Timestamp'])

# Filter specific events
events = [
    "profiling", 
    "Advanced to block",
    "Starting round"
]

event_df = df[df['Message'].str.contains('|'.join(events), na=False)]

# for debugging
# store the event_df in a csv file
# event_df.to_csv(f'event_df_val{val_index}.csv', index=False)

class Block:
    def __init__(self, height, timestamp):
        self.height = height
        self.timestamp = timestamp
        self.start_time_prepare_advance_to_next_quorum_block = None
        self.end_time_prepare_advance_to_next_quorum_block = None
        self.start_time_check_next_block = None
        self.end_time_check_next_block = None
        self.start_time_advance_to_next_block = None
        self.end_time_advance_to_next_block = None
        self.advanced_to_block_time = None
        self.max_round_number = None
        self.num_transmissions = None
        self.round_proposal_generation_seconds = None
        self.certificate_generation_seconds = None
        self.certificate_collection_seconds = None
        self.previous_block = None
        self.associated_rounds = []

    def _get_min_timestamp(self):
        return min(
            self.start_time_prepare_advance_to_next_quorum_block,
            self.end_time_prepare_advance_to_next_quorum_block,
            self.start_time_check_next_block,
            self.end_time_check_next_block,
            self.start_time_advance_to_next_block,
            self.end_time_advance_to_next_block,
            self.advanced_to_block_time
        )
    
    def _get_min_timestamp_of_rounds(self):
        return min([r.get_min_timestamp() for r in self.associated_rounds])
    
    def _get_max_timestamp(self):
        return max(
            self.start_time_prepare_advance_to_next_quorum_block,
            self.end_time_prepare_advance_to_next_quorum_block,
            self.start_time_check_next_block,
            self.end_time_check_next_block,
            self.start_time_advance_to_next_block,
            self.end_time_advance_to_next_block,
            self.advanced_to_block_time
        )
    
    def _get_max_timestamp_of_rounds(self):
        return max([r.get_max_timestamp() for r in self.associated_rounds])
    
    def get_duration(self):
        return self._get_max_timestamp() - self._get_min_timestamp()
    
    def get_rounds_duration(self):
        return self._get_max_timestamp_of_rounds() - self._get_min_timestamp_of_rounds()
    
    def get_max_duration(self):
        min_time_rounds_and_block = min(self._get_min_timestamp(), self._get_min_timestamp_of_rounds())
        max_time_rounds_and_block = max(self._get_max_timestamp(), self._get_max_timestamp_of_rounds())
        return max_time_rounds_and_block - min_time_rounds_and_block

    def get_all_rounds_proposal_generation_time(self):
        # returns the sum of all rounds' time to generate proposal
        times = []
        for r in self.associated_rounds:
            times.append(r.get_time_to_generate_proposal())
        sum_seconds = 0
        for t in times:
            if t is not None:
                sum_seconds += t.total_seconds()
            else:
                print(f"None value found in times of block {self.height} for proposal generation - expected behavior")
        if sum_seconds == 0:
            print(f"Zero value found in times of block {self.height}")
        self.round_proposal_generation_seconds = sum_seconds
        return sum_seconds

    def get_individual_rounds_proposal_generation_time(self):
        times = []
        for r in self.associated_rounds:
            times.append(r.get_time_to_generate_proposal())
        times_none_is_0 = []
        for t in times:
            if t is not None:
                times_none_is_0.append(t.total_seconds())
            else:
                times_none_is_0.append(0)
                print(f"None value found in times of block {self.height} for proposal generation - expected behavior")
        #self.round_proposal_generation_seconds = sum(times_none_is_0)
        return times_none_is_0
    
    def get_all_rounds_certificate_generation_time(self):
        # returns the sum of all rounds' time to generate certificate
        times = []
        for r in self.associated_rounds:
            times.append(r.get_time_to_generate_certificate())
        sum_seconds = 0
        for t in times:
            if t is not None:
                sum_seconds += t.total_seconds()
            else:
                print(f"None value found in times of block {self.height}")
        self.certificate_generation_seconds = sum_seconds
        return sum_seconds
        #return sum([r.get_time_to_generate_certificate() for r in self.associated_rounds])

    def get_individual_rounds_certificate_generation_time(self):
        times = []
        for r in self.associated_rounds:
            times.append(r.get_time_to_generate_certificate())
        times_none_is_0 = []
        for t in times:
            if t is not None:
                times_none_is_0.append(t.total_seconds())
            else:
                times_none_is_0.append(0)
                print(f"None value found in times of block {self.height}")
        #self.certificate_generation_seconds = sum(times_none_is_0)
        return times_none_is_0
    
    def get_all_rounds_certificate_collection_time(self):
        # returns the sum of all rounds' time to collect certificates
        #return sum([r.get_time_to_collect_certificates() for r in self.associated_rounds])
        times = []
        for r in self.associated_rounds:
            times.append(r.get_time_to_collect_certificates())
        sum_seconds = 0
        for t in times:
            if t is not None:
                sum_seconds += t.total_seconds()
            else:
                print(f"None value found in times of block {self.height}")
        self.certificate_collection_seconds = sum_seconds
        return sum_seconds
    
    def get_individual_rounds_certificate_collection_time(self):
        times = []
        for r in self.associated_rounds:
            times.append(r.get_time_to_collect_certificates())
        times_none_is_0 = []
        for t in times:
            if t is not None:
                times_none_is_0.append(t.total_seconds())
            else:
                times_none_is_0.append(0)
                print(f"None value found in times of block {self.height}")
        #self.certificate_collection_seconds = sum(times_none_is_0)
        # check if a value less than 0 is in the list
        for t in times_none_is_0:
            if t < 0:
                print(f"Negative value found in times of block {self.height}")
        return times_none_is_0
    
    def get_time_for_subdag_processing(self):
        # get last end_certificate_collection_time of associated rounds
        last_end_certificate_collection_time = None
        for r in self.associated_rounds:
            if r.end_certificate_collection_time is not None:
                if last_end_certificate_collection_time is None or r.end_certificate_collection_time > last_end_certificate_collection_time:
                    last_end_certificate_collection_time = r.end_certificate_collection_time

        if last_end_certificate_collection_time is not None:
            return (self.start_time_prepare_advance_to_next_quorum_block - last_end_certificate_collection_time).total_seconds()
        else:
            print(f"No certificate collection before start_prepare_advance_to_next_quorum_block for block {self.height}")
            return 0

    def get_time_in_prepare_advance_to_next_quorum_block(self):
        return (self.end_time_prepare_advance_to_next_quorum_block - self.start_time_prepare_advance_to_next_quorum_block).total_seconds()

    def time_in_check_next_block(self):
        return (self.end_time_check_next_block - self.start_time_check_next_block).total_seconds()

    def time_in_advance_to_next_block(self):
        return (self.end_time_advance_to_next_block - self.start_time_advance_to_next_block).total_seconds()

class Round:
    def __init__(self, round_number):
        self.round_number = round_number
        self.start_time = None
        self.end_time = None
        self.start_certificate_time = None
        self.end_certificate_time = None
        self.start_certificate_collection_time = None
        self.end_certificate_collection_time = None
        self.associated_block = None
        self.time_logged_in_advance_to_block = None

    def get_min_timestamp(self):
        return min(
            time for time in [
                self.start_time,
                self.end_time,
                self.start_certificate_time,
                self.end_certificate_time,
                self.start_certificate_collection_time,
                self.end_certificate_collection_time,
                self.time_logged_in_advance_to_block
            ] if time is not None
        )    
    
    def get_max_timestamp(self):
        return max(
            time for time in [
                self.start_time,
                self.end_time,
                self.start_certificate_time,
                self.end_certificate_time,
                self.start_certificate_collection_time,
                self.end_certificate_collection_time,
                self.time_logged_in_advance_to_block
            ] if time is not None
        )
    
    def get_time_to_generate_proposal(self):
        if(self.end_time is None or self.start_time is None):
            return None
        return self.end_time - self.start_time
    
    def get_time_to_generate_certificate(self):
        if(self.end_certificate_time is None or self.start_certificate_time is None):
            return None
        return self.end_certificate_time - self.start_certificate_time
    
    def get_time_to_collect_certificates(self):
        previous_block_advanced_to_block_time = None
        if(self.associated_block is not None):
            previous_block = self.associated_block.previous_block
            if(self.associated_block.height > 1):
                previous_block_advanced_to_block_time = previous_block.advanced_to_block_time

        if self.start_certificate_collection_time is None and self.end_certificate_collection_time is None:
            return None
        elif self.start_certificate_collection_time is None:
            return self.end_certificate_collection_time - self.start_time
        else:
            return self.end_certificate_collection_time - self.start_certificate_collection_time

# Initialize dictionaries to store times
start_round_times = {}
quorum_times = {}
advanced_block_times = []

# Iterate through the dataframe and categorize events
recording_started = False

blocks = {}
rounds = {}

for index, row in event_df.iterrows():
    message = row['Message']
    timestamp = row['Timestamp']

    # check if message is profiling - starting proposal generation for round {round_number}
    if "profiling - starting proposal generation for round" in message:
        round_number = int(message.split('round ')[1])
        if(round_number in rounds):
            #print(f"Round {round_number} already exists, still found a new proposal generation start")
            continue
        start_round_times[round_number] = timestamp
        rounds[round_number] = Round(round_number)
        rounds[round_number].start_time = timestamp
        continue

    if "profiling - ending proposal generation for round" in message:
        round_number = int(message.split('round ')[1])
        rounds[round_number].end_time = timestamp
        continue

    if "profiling - starting certificate generation for round" in message:
        round_number = int(message.split('round ')[1])
        rounds[round_number].start_certificate_time = timestamp
        continue

    if "profiling - ending certificate generation for round" in message:
        round_number = int(message.split('round ')[1])
        rounds[round_number].end_certificate_time = timestamp
        continue

    if "profiling - starting certificate collection for round" in message:
        round_number = int(message.split('round ')[1])
        rounds[round_number].start_certificate_collection_time = timestamp
        continue

    if "Starting round" in message:
        round_number = message.split('round ')[1]
        round_number = round_number.split('...')[0]
        round_number = int(round_number)
        round_before = round_number - 1
        if(round_before in rounds):
            if(rounds[round_before].end_certificate_collection_time is None):
                rounds[round_before].end_certificate_collection_time = timestamp
        continue

    if "profiling - ending certificate collection for round" in message:
        round_number = int(message.split('round ')[1])
        if(round_number in rounds):
            if(rounds[round_number].end_certificate_collection_time is None):
                rounds[round_number].end_certificate_collection_time = timestamp
        else:
            new_round = Round(round_number)
            new_round.end_certificate_collection_time = timestamp
            print(f"Created new round {round_number} with end_certificate_collection_time")

        continue

    if "profiling - starting prepare_advance_to_next_quorum_block" in message:
        block_number = len(blocks) + 1
        block = Block(block_number, timestamp)
        block.start_time_prepare_advance_to_next_quorum_block = timestamp
        blocks[block_number] = block
        continue

    if "profiling - ending prepare_advance_to_next_quorum_block for block " in message:
        block_number = int(message.split('block ')[2])
        blocks[block_number].end_time_prepare_advance_to_next_quorum_block = timestamp
        continue

    if "starting check_next_block for block" in message:
        block_number = int(message.split('block ')[2])
        blocks[block_number].start_time_check_next_block = timestamp
        continue

    if "profiling - ending check_next_block for block" in message:
        block_number = int(message.split('block ')[2])
        blocks[block_number].end_time_check_next_block = timestamp
        continue

    if "profiling - starting advance_to_next_block for block" in message:
        block_number = int(message.split('block ')[2])
        blocks[block_number].start_time_advance_to_next_block = timestamp
        continue
    
    if "Advanced to block" in message:
        block_number = int(message.split('block ')[1].split(' ')[0])
        round_number = int(message.split('round ')[1].split(' ')[0])
        transmissions_number = int(message.split('number of transmissions: ')[1].split(' ')[0])
        if(not (block_number in blocks)):
            print(f"Block {block_number} not found - handling should be investigated")
            continue
        blocks[block_number].advanced_to_block_time = timestamp
        blocks[block_number].max_round_number = round_number
        blocks[block_number].num_transmissions = transmissions_number

        if(round_number not in rounds):
            rounds[round_number] = Round(round_number)
            rounds[round_number].time_logged_in_advance_to_block = timestamp
            print(f"Creating new round {round_number} for block {block_number}")

        associated_rounds = [rounds[round_number]]
        rounds[round_number].associated_block = blocks[block_number]
        round_number_loop = copy.deepcopy(round_number)

        while round_number_loop > 1 and round_number_loop - 1 in rounds:
            round_number_loop -= 1
            if(rounds[round_number_loop].associated_block is None):
                rounds[round_number_loop].associated_block = blocks[block_number]
                associated_rounds.append(rounds[round_number_loop])
            else:
                break
        
        blocks[block_number].associated_rounds = associated_rounds

        advanced_block_times.append(timestamp)
        continue
    
    if "profiling - ending advance_to_next_block for block" in message:
        block_number = int(message.split('block ')[2])
        blocks[block_number].end_time_advance_to_next_block = timestamp
        continue

# remove the last block
blocks.pop(len(blocks))

# assign previous blocks for each block
for block in blocks.values():
    if block.height > 1:
        block.previous_block = blocks[block.height - 1]

# compure the duration of each block and add it to a list
blocks_durations = []
for block in blocks.values():
    blocks_durations.append(block.get_max_duration().total_seconds())

# Extract data
block_heights = []
proposal_gen_times = []
certificate_gen_times = []
certificate_col_times = []
subdag_processing_times = []
prepare_advance_to_next_quorum_block_times = []
check_next_block_times = []
advance_next_block_times = []
unaccounted_times = []

#previous_block_end_time = 0 
for block in blocks.values():
    # Compute the tracked times for each block.

    # For each associated round, collect the start_time, if it is not None.
    proposal_gen_start = min([r.start_time for r in block.associated_rounds if r.start_time is not None])
    proposal_gen_time = block.get_individual_rounds_proposal_generation_time()
    certificate_gen_time = block.get_individual_rounds_certificate_generation_time()
    certificate_col_time = block.get_individual_rounds_certificate_collection_time()
    subdag_processing_time = block.get_time_for_subdag_processing()
    time_in_advance_to_next_quorum_block = block.get_time_in_prepare_advance_to_next_quorum_block()
    check_next_block_time = block.time_in_check_next_block()
    advance_next_block_time = block.time_in_advance_to_next_block()

    # Compute the unaccounted time for each block.
    unaccounted_time = 0
    if block.height != 1:
        block_gen_time = (block.end_time_advance_to_next_block - proposal_gen_start).total_seconds()
        unaccounted_time = block_gen_time - advance_next_block_time - check_next_block_time - time_in_advance_to_next_quorum_block - subdag_processing_time - sum(certificate_col_time) - sum(certificate_gen_time) - sum(proposal_gen_time)

    # Collect the times for later visualization.
    block_heights.append(block.height)
    proposal_gen_times.append(proposal_gen_time)
    certificate_gen_times.append(certificate_gen_time)
    certificate_col_times.append(certificate_col_time)
    subdag_processing_times.append(subdag_processing_time)
    prepare_advance_to_next_quorum_block_times.append(time_in_advance_to_next_quorum_block)
    check_next_block_times.append(check_next_block_time)
    advance_next_block_times.append(advance_next_block_time)
    unaccounted_times.append(unaccounted_time)

def flatten_list_of_lists(lol):
    return [item for sublist in lol for item in sublist]

# Plotting
fig, ax = plt.subplots(figsize=(10, 7))

# Initialize the bottom stack array for 114 blocks
bottoms = np.zeros(len(block_heights))

# Define colors for each category
proposal_color = 'blue'
certificate_color = 'green'
collection_color = 'red'
subdag_processing_color = 'orange'
prepare_advance_color = 'purple'
check_next_color = 'cyan'
advance_next_color = 'magenta'
unaccounted_color = 'black'

# Iterate over each block to stack bars
for i in range(len(block_heights)):
    # Stack the proposal, certificate, and collection times for each block
    for j in range(len(proposal_gen_times[i])):  # Assuming len(proposal_gen_times[i]) is the same for certificate and collection times
        
        # Proposal Generation Time
        ax.bar(block_heights[i], proposal_gen_times[i][j], bottom=bottoms[i], 
               label='Proposal Generation Time' if i == 0 and j == 0 else "",
               color=proposal_color)
        bottoms[i] += proposal_gen_times[i][j]

        # Certificate Generation Time
        ax.bar(block_heights[i], certificate_gen_times[i][j], bottom=bottoms[i], 
               label='Certificate Generation Time' if i == 0 and j == 0 else "",
               color=certificate_color)
        bottoms[i] += certificate_gen_times[i][j]

        # Certificate Collection Time
        ax.bar(block_heights[i], certificate_col_times[i][j], bottom=bottoms[i], 
               label='Certificate Collection Time' if i == 0 and j == 0 else "",
               color=collection_color)
        bottoms[i] += certificate_col_times[i][j]

# Stack the remaining times (prepare, check, advance, and end) for each block
ax.bar(block_heights, subdag_processing_times, bottom=bottoms, label='Time processing subdag', color=subdag_processing_color)
bottoms = [b + p for b, p in zip(bottoms, subdag_processing_times)]  # Update the bottoms after adding each bar

ax.bar(block_heights, prepare_advance_to_next_quorum_block_times, bottom=bottoms, label='Time in prepare_advance_to_next_quorum_block', color=prepare_advance_color)
bottoms = [b + p for b, p in zip(bottoms, prepare_advance_to_next_quorum_block_times)]

ax.bar(block_heights, check_next_block_times, bottom=bottoms, label='Time in check_next_block', color=check_next_color)
bottoms = [b + c for b, c in zip(bottoms, check_next_block_times)]

ax.bar(block_heights, advance_next_block_times, bottom=bottoms, label='Time in advance_to_next_block', color=advance_next_color)
bottoms = [b + a for b, a in zip(bottoms, advance_next_block_times)]

# Stack the unaccounted time for each block
ax.bar(block_heights, unaccounted_times, bottom=bottoms, label='Unaccounted Time', color=unaccounted_color)
bottoms = [b + u for b, u in zip(bottoms, unaccounted_times)]

# Add labels and title
ax.set_xlabel('Block Height')
ax.set_ylabel('Time')
ax.set_title(f'Stacked Bar Chart of Block Times, index {val_index} of {num_val} validators')
ax.legend()


blocks_durations2 = []
for block in blocks.values():
    if block.height > 1:
        previous_block = blocks[block.height - 1]
        blocks_durations2.append((block.advanced_to_block_time - previous_block.advanced_to_block_time).total_seconds())

# Display the plot
plt.show()

# Save the figure
fig.savefig(f'1_stacked_bar_chart_block_times_val{val_index}.png')


# Another bar chart with number of transmissions per block
fig, ax = plt.subplots(figsize=(10, 7))

# Bar chart
p1 = ax.bar(block_heights, [block.num_transmissions for block in blocks.values()], label='Number of Transmissions')

# Add labels and title
ax.set_xlabel('Block Height')
ax.set_ylabel('Number of Transmissions')
ax.set_title(f'Number of Transmissions per Block, index {val_index} of {num_val} validators')
ax.legend()

# Display the plot
plt.show()
# save the figure
fig.savefig(f'2_bar_chart_num_transmissions_val{val_index}.png')

# Display number of associated rounds per block in a bar chart
fig, ax = plt.subplots(figsize=(10, 7))

# Bar chart
p1 = ax.bar(block_heights, [len(block.associated_rounds) for block in blocks.values()], label='Number of Associated Rounds')

# Add labels and title
ax.set_xlabel('Block Height')
ax.set_ylabel('Number of Associated Rounds')
ax.set_title(f'Number of Associated Rounds per Block, index {val_index} of {num_val} validators')
ax.legend()

# Display the plot
plt.show()
# save the figure
fig.savefig(f'3_bar_chart_num_associated_rounds_val{val_index}.png')

# compute share of blocks with 0 proposal generation time, 0 certificate generation time, 0 certificate collection time
num_blocks = len(blocks)
num_blocks_zero_proposal_gen_time = len([block for block in blocks.values() if block.round_proposal_generation_seconds == 0])
num_blocks_zero_certificate_gen_time = len([block for block in blocks.values() if block.certificate_generation_seconds == 0])
num_blocks_zero_certificate_col_time = len([block for block in blocks.values() if block.certificate_collection_seconds == 0])

print(f"Share of blocks with 0 proposal generation time [%]: {num_blocks_zero_proposal_gen_time / num_blocks * 100}")
print(f"Share of blocks with 0 certificate generation time [%]: {num_blocks_zero_certificate_gen_time / num_blocks * 100}")
print(f"Share of blocks with 0 certificate collection time [%]: {num_blocks_zero_certificate_col_time / num_blocks * 100}")