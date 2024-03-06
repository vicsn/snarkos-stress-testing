import os
import re
import requests

# The directory containing the log files
log_dir = "tx-cannon-logs"
# Regular expression to find transaction hashes
transaction_id_pattern = r'"transaction_id": ""([^"]+)""'
# Base URL for load balancer
load_balancer_URL = "http://snarkos-lb-981333943.us-west-1.elb.amazonaws.com:3030"

# Variables to count success and failure
tx_success = 0
tx_fail = 0

# Function to load transaction hashes from log files
def load_transaction_hashes(directory):
    transaction_hashes = []
    for filename in os.listdir(directory):
        if filename.endswith(".log"):  # Assuming log files end with .log
            filepath = os.path.join(directory, filename)
            with open(filepath, 'r') as file:
                content = file.read()
                matches = re.findall(transaction_id_pattern, content)
                transaction_hashes.extend(matches)
    return transaction_hashes

# Function to check transaction status
def check_transactions(transaction_hashes):
    global tx_success, tx_fail
    for hash in transaction_hashes:
        url = f"{load_balancer_URL}/mainnet/transaction/{hash}"
        try:
            response = requests.get(url)
            if response.status_code == 404 or response.text.startswith(("Something went wrong", "Invalid URL")):
                tx_fail += 1
            else:
                tx_success += 1
        except Exception as e:
            print(f"Error making request for {hash}: {e}")
            tx_fail += 1

# Load transaction hashes
transaction_hashes = load_transaction_hashes(log_dir)
# Check transactions
print(f"Total Transactions: {len(transaction_hashes)}, querying ...")
check_transactions(transaction_hashes)
# Print results
print(f"Transaction Success: {tx_success}, Transaction Fail: {tx_fail}")
