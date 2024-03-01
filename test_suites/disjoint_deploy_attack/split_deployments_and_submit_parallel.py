import os
import subprocess
from concurrent.futures import ProcessPoolExecutor, as_completed
import time

# Function to send transactions to a validator without surpassing the rate limit.
def send_transactions(deployments_path, ip_address):
    results = []
    with open(deployments_path, "r") as f:
        i = 0
        for tx in f.readlines():
            # sleep 1 second every 5 txs. This is a simplified way to throttle the txs to stay below the rate-limit.
            if i % 5 == 0:
                time.sleep(1)
            cmd = f"curl http://{ip_address}:3030/mainnet/transaction/broadcast -X POST -H \"Content-Type: application/json\" -d '{tx}'"
            result = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            output = result.stdout.decode().strip()
            error = result.stderr.decode().strip()
            results.append(f"Executed {cmd}\nOutput: {output}\nError: {error}")
            i += 1

    return results

def main():

    # Read ip_addresses.txt
    ip_addresses_path = os.path.join(os.getcwd(), "ip_addresses.txt")
    with open(ip_addresses_path, "r") as f:
        ip_addresses = f.readlines()

    # Read pregenerated txs
    txs = []
    for i in range(5):
        tx_path = os.path.join(os.getcwd(), "pregenerated_txs", f"{i}-e9533b6-5val-deploys.txt")
        with open(tx_path, "r") as f:
            for tx in f.readlines():
                txs.append(tx)

    # Create a folder to store the deployments
    deployments_split_folder_path = os.path.join(os.getcwd(), "programs_to_deploy", "split")
    if not os.path.exists(deployments_split_folder_path):
        os.makedirs(deployments_split_folder_path)

    number_of_programs = len(txs)
    number_of_validators = len(ip_addresses)

    programs_per_validator = number_of_programs // number_of_validators

    deployment_counter = 0
    deployment_paths = []
    for i in range(number_of_validators):
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
    print("starting to measure time")
    start = time.time()

    # Use ProcessPoolExecutor to parallelize the execution
    with ProcessPoolExecutor(max_workers=number_of_validators) as executor:
        # Schedule the execute_command calls and use as_completed to block until they are done
        futures = {executor.submit(send_transactions, deployment_paths[i], ip_addresses[i].strip()): i for i in range(number_of_validators)}
        for future in as_completed(futures):
            i = futures[future]
            try:
                data = future.result()
                print(data)
            except Exception as exc:
                print(f'Generated an exception: {exc}')
            else:
                print(f'Validator {i} completed')
    
    # end measure time
    end = time.time()
    print(f"Time elapsed: {end - start} seconds")

    print(f"end time: {end}")

    print("Done")

if __name__ == '__main__':
    main()
