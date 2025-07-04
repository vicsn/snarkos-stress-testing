#!/bin/bash

ulimit -n 2048

PARENT_DIR=$(cd "$(dirname $0)" && pwd)
bold=$(tput bold)
normal=$(tput sgr0)

TFSTATE_BUCKET="${TF_STATE_BUCKET:-ephnet-terraform-state-bucket-eq}"
export AWS_REGION="${TF_STATE_REGION:-us-west-2}"
RELEASE_BUCKET="${RELEASE_BUCKET:-provable-binaries-releases}"
export TF_VAR_RELEASE_BUCKET=$RELEASE_BUCKET

# Override the USER var for the run, as USER is just ubuntu for the builder and we want a special, visible name:
# Ansible also uses this var to create its dynamic inventory, that's why we need it set the same as the OWNER for terraform.
export USER=builder
export OWNER=$USER

{% raw %}
sed -i "s|{{ lookup('env', 'USER') }}|$OWNER|" inventory/dynamic_inventory.aws_ec2.yml
{% endraw %}

# Functions to clean up resources using Terraform
cleanup_on_error() {
  rc=$?
  echo "ERR (rc: $rc)"

  # Download client logs:
  export SELECTED=_download_logs_clients
  run_test

  # Download validator logs:
  export SELECTED=_download_logs_validators
  run_test

  echo "An error occurred or finished. Destroying infrastructure to avoid unnecessary costs..."
  cleanup

  exit $rc
}

react_on_exit() {
  rc=$?
  echo "EXIT (rc: $rc)"

  # Download client logs:
  export SELECTED=_download_logs_clients
  run_test

  # Download validator logs:
  export SELECTED=_download_logs_validators
  run_test

  exit $rc
}

cleanup() {
    cd "$PARENT_DIR/terraform"
    terraform destroy -auto-approve -parallelism=50 -var="owner=$OWNER"

    cd "$PARENT_DIR/terraform_tx_cannon"
    terraform init
    terraform destroy -auto-approve -parallelism=50 -var="owner=$OWNER"
}

# Function to init and apply Terraform
init_and_apply_terraform() {
    cd $PARENT_DIR/terraform

    terraform init -migrate-state
    terraform apply -auto-approve -var="owner=$OWNER"

    # Save the load balancer DNS name
    terraform output -raw snarkos_lb_dns_name > $PARENT_DIR/lb_url.txt
    LB_URL=$(cat $PARENT_DIR/lb_url.txt)
    export NETWORK=$(cd "$PARENT_DIR/terraform" && TF_CLI_ARGS="-no-color" terraform output -raw snarkos_network)

    # Save updated IP addresses
    cd "$PARENT_DIR/playbooks"
    ansible-playbook ips.yml --extra-vars="snarkos_network=${NETWORK}" --extra-vars "test_network_url=${LB_URL}" --extra-vars="@${VARS}.yml"
}

run_test() {
    echo "${bold}$(date +"%T") - Running test: $SELECTED${normal}"

    # Run any pre-test script
    if [ -x "$PARENT_DIR/tests/$SELECTED/pre-test.sh" ]; then
        echo "Running pre-test script..."
        cd "$PARENT_DIR/tests/$SELECTED/"
        "./pre-test.sh"
    fi

    # Won't be defined if somebody kills the script and the logs cleanup kicks in as a run:
    if [[ -z "${LB_URL}" ]]; then
      LB_URL=$(cat $PARENT_DIR/lb_url.txt)
    fi

    (cd "$PARENT_DIR/terraform" && terraform init -input=false)
    export NETWORK=$(cd "$PARENT_DIR/terraform" && TF_CLI_ARGS="-no-color" terraform output -raw snarkos_network)

    # Run the test
    cd "$PARENT_DIR/playbooks"
    ansible-playbook run_test.yml --extra-vars="snarkos_network=${NETWORK}" --extra-vars="test_name=$SELECTED" --extra-vars="test_network_url=${LB_URL}" --extra-vars="@${VARS}.yml"

    # Run a check script if available
    if [ -x "$PARENT_DIR/tests/$SELECTED/check.sh" ]; then
        cd "$PARENT_DIR/tests/$SELECTED/"
        echo "Running check script in folder `pwd`"
        ./check.sh $NETWORK
    fi

    # Run any post-test script
    if [ -x "$PARENT_DIR/tests/$SELECTED/post-test.sh" ]; then
        echo "Running post-test script..."
        cd "$PARENT_DIR/tests/$SELECTED/"
        "./post-test.sh"
    fi
}

usage() {
  echo "----------"
  echo -e "Usage:\n" 1>&2
  echo -e "Set up:\n"  1>&2
  echo "  $0 setup [-a] [-t] [-m <l|light|h|heavy>] [-v <vars-file-name>]" 1>&2
  echo -e "\n  Sets up the infrastructure." 1>&2
  echo "    -a : If passed it sets up ansible provisioning." 1>&2
  echo "    -t : If passed it sets up only terraform." 1>&2
  echo "    -m : Stands for mode. Can be passed as light or heavy, default is light." 1>&2
  echo "    -v : Stands for the name of the vars file used by ansible." 1>&2
  echo "  Defaults : -at -m light -v vars" 1>&2
  echo -e "\nClean up:\n"  1>&2
  echo -e "  $0 cleanup" 1>&2
  echo -e "\n  Cleans up the infrastructure. Basically runs terraform destroy." 1>&2
  echo -e "\nExecute test(s):\n"  1>&2
  echo "  $0 test -t <test(s)> [-v <vars-file-name>]" 1>&2
  echo -e "\n  Runs the specified test(s)." 1>&2
  echo "    -t : Specifies the test(s) to run. If multiple tests are specified, they must be separated via commas." 1>&2
  echo "    -v : Stands for the name of the vars file used by ansible." 1>&2
  echo "  Defaults : -v vars" 1>&2
  echo "----------"
  exit 0
}

parse_setup() {
  OPTSTRING="atm:v:"

  run_ansible="default"
  run_terraform="default"
  mode=l
  vars="vars"

  shift
  while getopts ${OPTSTRING} option; do
    case "${option}" in
      a)
        run_ansible=set
        ;;
      t)
        run_terraform=set
        ;;
      m)
        m=${OPTARG}
        if [ "$m" = "l" ] ||  [ "$m" == "light" ]; then
          mode=l
        elif [ "$m" = "h" ] ||  [ "$m" == "heavy" ]; then
          mode=h
        else
          usage
        fi
        ;;
      v)
        vars=${OPTARG}
        ;;
      *)
        echo $option
        usage
        exit 1
        ;;
    esac
  done
  shift $((OPTIND - 1))

  RUN_SETUP=n
  RUN_TERRAFORM=n
  RUN_TESTS=n

  if [ ${run_ansible} = "set" ]; then
    RUN_SETUP=y
  fi
  if [ ${run_terraform} = "set" ]; then
    RUN_TERRAFORM=$mode
  fi
  if [ ${run_ansible} = "default" -a ${run_terraform} = "default" ]; then
    RUN_TERRAFORM=$mode
    RUN_SETUP=y
  fi
  VARS=$vars

  echo "Terraform: $RUN_TERRAFORM Ansible: $RUN_SETUP Tests: $RUN_TESTS Vars: $VARS"
}

parse_tests_to_run() {
  OPTSTRING="t:v:"

  vars="vars"

  shift
  while getopts ${OPTSTRING} option; do
    case "${option}" in
      t)
        tests=${OPTARG}
        ;;
      v)
        vars=${OPTARG}
        ;;
      *)
        echo $option
        usage
        exit 1
        ;;
    esac
  done
  shift $((OPTIND - 1))

  if [ -z "${tests:-}" ]; then
    usage
    exit 1
  fi

  RUN_SETUP=n
  RUN_TERRAFORM=n
  RUN_TESTS=y
  VARS=$vars

  SELECTED_TESTS=(${tests//,/ })
}


# Trap setup:

trap cleanup_on_error ERR

trap react_on_exit EXIT

# Exit immediately if a command exits with a non-zero status.
set -e

# Exit if an undefined variable is used.
set -u

# export trap to functions
set -E

# Main

command="${1:-usage}"

case $command in
  setup)
    echo "Infrastructure setup initiated."

    parse_setup $@
    ;;
  cleanup)
    echo "Infrastructure cleanup initiated."
    cleanup
    exit 0
    ;;
  test)
    echo "Test run initiated."

    parse_tests_to_run $@
    ;;
  *)
    usage
    exit 1
    ;;
esac

# Define key name
KEY_NAME="devnet-key"

# Check if the SSH key already exists, generate if not
if [ ! -f "${KEY_NAME}" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t rsa -b 4096 -f "${KEY_NAME}" -N '' # -N '' specifies no passphrase
    chmod 400 "${KEY_NAME}"
else
    echo "SSH key already exists. Skipping generation..."
fi

# Configuration:
#RUN_TERRAFORM="${1:-l}"
#RUN_SETUP="${2:-y}"
#RUN_TESTS="${3:-y}"
#SELECTED="${4:-unbond_bond_validators}"
#VARS="${5:-vars}"

# Optionally initialize and apply Terraform
if [ "$RUN_TERRAFORM" == "h" ]; then
    cp $PARENT_DIR/terraform/variables.tf.heavy $PARENT_DIR/terraform/variables.tf
    init_and_apply_terraform
elif [ "$RUN_TERRAFORM" == "l" ]; then
    cp $PARENT_DIR/terraform/variables.tf.light $PARENT_DIR/terraform/variables.tf
    init_and_apply_terraform
elif [ "$RUN_TERRAFORM" == "n" ]; then
    echo "Skipping Terraform..."
else
    echo "Invalid option. Exiting..."
    exit 1
fi

# Read the load balancer DNS name from lb_url.txt
LB_URL=$(cat $PARENT_DIR/lb_url.txt)

# Read the network from $PARENT_DIR/playbooks/vars.yml
export NETWORK=$(grep "network:" $PARENT_DIR/playbooks/${VARS}.yml | cut -d " " -f2)

# Optionally run Ansible playbook to setup services
if [ "$RUN_SETUP" == "y" ]; then
    cd "$PARENT_DIR/playbooks"
    ansible-playbook setup.yml --extra-vars "test_network_url=${LB_URL}" --extra-vars="@${VARS}.yml"
elif [ "$RUN_SETUP" == "n" ]; then
    echo "Skipping setup..."
else
    echo "Invalid option. Exiting..."
    exit 1
fi

# Run tests
if [ "$RUN_TESTS" == "y" ]; then
  for i in "${!SELECTED_TESTS[@]}"
  do
      SELECTED=${SELECTED_TESTS[i]}
      echo "Running test ${SELECTED}, vars: $VARS"

      run_test

      # Download client logs:
      export SELECTED=_download_logs_clients
      run_test

      # Download validator logs:
      export SELECTED=_download_logs_validators
      run_test

      # Download prometheus snapshot:
      # export SELECTED=_download_prometheus_snapshot
      # run_test
  done
fi
