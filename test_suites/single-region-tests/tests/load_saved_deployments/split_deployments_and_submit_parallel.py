import os
import sys
import subprocess
from concurrent.futures import ProcessPoolExecutor, as_completed
import time

# Function to send transactions to a validator without surpassing the rate limit.
def send_transactions(deployments_path, ip_address, network):
    results = []
    with open(deployments_path, "r") as f:
        i = 0
        for tx in f.readlines():
            # sleep 1 second every 5 txs. This is a simplified way to throttle the txs to stay below the rate-limit.
            if i % 5 == 0:
                time.sleep(1)
            cmd = f"curl http://{ip_address}:3030/{network}/transaction/broadcast -X POST -H \"Content-Type: application/json\" -d '{tx}'"
            result = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            output = result.stdout.decode().strip()
            error = result.stderr.decode().strip()
            results.append(f"Executed {cmd}\nOutput: {output}\nError: {error}")
            i += 1

    return results

def main():

    # Error if no argument was passed.
    if len(sys.argv) < 2:
        print("Please provide the network type as an argument")
        exit()
    # Set network from first argument.
    network = sys.argv[1]

    # Read ip_addresses.txt
    ip_addresses_path = os.path.join(os.getcwd(), "..", "..", "ip_addresses.txt")
    # Check if the file exists
    if not os.path.exists(ip_addresses_path):
        print(f"Missing ip_addresses.txt file, make sure to run terraform...")
        exit()
    with open(ip_addresses_path, "r") as f:
        ip_addresses = f.readlines()

    num_validators = len(ip_addresses)

    # Read how many pregenerated txs files are there giving num_validators
    num_pregenerated_txs_files_path = os.path.join(os.getcwd(), "..", "..", "transaction_files")
    num_pregenerated_txs_files = len([name for name in os.listdir(num_pregenerated_txs_files_path) if f"deploys-{ network }-{num_validators}val-" in name])
    
    print(num_pregenerated_txs_files)
    # Read pregenerated txs
    txs = []
    for i in range(num_pregenerated_txs_files):
        tx_path = os.path.join(os.getcwd(), "..", "..", "transaction_files", f"deploys-{ network }-{num_validators}val-{i}.txt")
        if not os.path.exists(tx_path):
                print(f"Missing transaction file {tx_path}, exiting...")
                exit()
        with open(tx_path, "r") as f:
            for tx in f.readlines():
                txs.append(tx)

    # Create a folder to store the deployments
    deployments_split_folder_path = os.path.join(os.getcwd(), "programs_to_deploy")
    if not os.path.exists(deployments_split_folder_path):
        os.makedirs(deployments_split_folder_path)

    number_of_programs = len(txs)
    print("number of programs: ", number_of_programs)
    programs_per_validator = number_of_programs // num_validators
    assert programs_per_validator > 0, "Not enough programs to split among validators"

    deployment_counter = 0
    deployment_paths = []
    for i in range(num_validators):
        deployment_path = os.path.join(deployments_split_folder_path, f"deployments_{i}.txt")
        deployment_paths.append(deployment_path)

        # if the file exists, delete it
        if os.path.exists(deployment_path):
            os.remove(deployment_path)

        for j in range(programs_per_validator):
            # append deployment to deployment_path file
            with open(deployment_path, "a") as f:
                f.write(txs[deployment_counter])

            deployment_counter += 1
    
    # start measure time
    start = time.time()

    # Use ProcessPoolExecutor to parallelize the execution
    with ProcessPoolExecutor(max_workers=num_validators) as executor:
        # Schedule the execute_command calls and use as_completed to block until they are done
        futures = {executor.submit(send_transactions, deployment_paths[i], ip_addresses[i].strip(), network): i for i in range(num_validators)}
        for future in as_completed(futures):
            i = futures[future]
            try:
                data = future.result()
                # print(data)
            except Exception as exc:
                print(f'Generated an exception: {exc}')
            else:
                print(f'Validator {i} - {ip_addresses[i].strip()} completed')
    
    # end measure time
    end = time.time()
    print(f"Time elapsed: {end - start} seconds")

if __name__ == '__main__':
    main()
