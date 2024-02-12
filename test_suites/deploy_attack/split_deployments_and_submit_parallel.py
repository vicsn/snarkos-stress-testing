import os
import subprocess
from concurrent.futures import ProcessPoolExecutor, as_completed
import time

# Function to execute command
def execute_command(i, ip_addresses):
    ip = ip_addresses[i].strip()
    cmd = f"tx-cannon batch-send --manifest programs_to_deploy/res_split/deployment_{i}.txt -e http://{ip}:3033"
    result = subprocess.run(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    output = result.stdout.decode().strip()
    error = result.stderr.decode().strip()
    return f"Executed {cmd}\nOutput: {output}\nError: {error}"

def main():

    # read ip_addresses.txt
    ip_addresses_path = os.path.join(os.getcwd(), "ip_addresses.txt")
    with open(ip_addresses_path, "r") as f:
        ip_addresses = f.readlines()

    deployment_txt_path = os.path.join(os.getcwd(), "programs_to_deploy", "res", "8-val-64-tx.txt")
    deployments_split_folder_path = os.path.join(os.getcwd(), "programs_to_deploy", "res_split")

    # create the folder if it does not exist
    if not os.path.exists(deployments_split_folder_path):
        os.makedirs(deployments_split_folder_path)

    # read deployment_txt_path
    with open(deployment_txt_path, "r") as f:
        deployments = f.readlines()

    number_of_programs = len(deployments)
    number_of_validators = len(ip_addresses)

    programs_per_validator = number_of_programs // number_of_validators

    deployment_counter = 0
    for i in range(number_of_validators):
        deployment_path = os.path.join(deployments_split_folder_path, f"deployment_{i}.txt")
        # if the file exists, delete it
        if os.path.exists(deployment_path):
            os.remove(deployment_path)

        for j in range(programs_per_validator):
            # append deployment to deployment_path file
            with open(deployment_path, "a") as f:
                f.write(deployments[deployment_counter])

            deployment_counter += 1
    
    # start measure time
    print("starting to measure time")
    start = time.time()

    # Use ProcessPoolExecutor to parallelize the execution
    with ProcessPoolExecutor(max_workers=number_of_validators) as executor:
        # Schedule the execute_command calls and use as_completed to block until they are done
        futures = {executor.submit(execute_command, i, ip_addresses): i for i in range(number_of_validators)}
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
