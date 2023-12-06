#!/bin/bash

# Determine the number of AWS EC2 instances by checking ~/.ssh/config
NODE_ID=0
while [ -n "$(grep "aws-n${NODE_ID}" ~/.ssh/config)" ]; do
    NODE_ID=$((NODE_ID + 1))
done

# Read the number of AWS EC2 instances to query from the user
read -p "Enter the number of AWS EC2 instances to query (default: $NODE_ID): " NUM_INSTANCES
NUM_INSTANCES="${NUM_INSTANCES:-$NODE_ID}"

echo "Using $NUM_INSTANCES AWS EC2 instances for querying."

# Define a function to run the installation and configuration on a node
run_installation_and_configuration() {
  local NODE_ID=$1
  # SSH into the node
  ssh -o StrictHostKeyChecking=no aws-n$NODE_ID << EOF
    # Commands to run on the remote instance
    sudo -i  # Switch to root user

    # Logstash Installation
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee -a /etc/apt/sources.list.d/elastic-8.x.list
    sudo apt-get update && sudo apt-get install logstash
    sudo /usr/share/logstash/bin/logstash-plugin install --version 2.0.0 logstash-output-opensearch
    sudo systemctl start logstash.service

    # Create Logstash configuration
    cat > /etc/logstash/conf.d/logstash.conf << 'LOGSTASH_CONF'
input {
  file {
    path => "/tmp/snarkos.log"
    start_position => "beginning"
    codec => multiline {
      pattern => "^%{TIMESTAMP_ISO8601}"
      negate => true
      what => "previous"
    }
  }
}
filter {
  grok {
    match => { "message" => "^%{TIMESTAMP_ISO8601:timestamp}\\s+%{LOGLEVEL:loglevel}\\s+%{GREEDYDATA:message}" }
    overwrite => [ "message" ]
  }
  date {
    match => [ "timestamp", "ISO8601" ]
  }
}
output {
  opensearch {
    ecs_compatibility => disabled
    hosts => "https://wqcnb8fib7sn7wbraau7.us-east-2.aoss.amazonaws.com:443"
    index => "test4"
    auth_type => {
      type => 'aws_iam'
      aws_access_key_id => 'mykey'
      aws_secret_access_key => 'mykey'
      region => 'us-east-2'
      service_name => 'aoss'
    }
    default_server_major_version => 2
    legacy_template => false
  }
  stdout {}
}
LOGSTASH_CONF

    # Restart Logstash to apply the new configuration
    sudo systemctl restart logstash.service

    exit  # Exit root user
EOF

  # Check the exit status of the SSH command
  if [ $? -eq 0 ]; then
    echo "Logstash installation and configuration on aws-n$NODE_ID completed successfully."
  else
    echo "Logstash installation and configuration on aws-n$NODE_ID failed."
  fi
}

# Loop through aws-n nodes and run installations and configurations in parallel
for NODE_ID in $(seq 0 $NUM_INSTANCES); do
  run_installation_and_configuration $NODE_ID &
done

# Wait for all background jobs to finish
wait
