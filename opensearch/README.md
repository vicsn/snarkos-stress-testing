## (Optional) Log Analytics

In the `opensearch` directory run Terraform to set up a serverless OpenSearch collection.

```bash
cd opensearch
terraform init
terraform apply
```

Copy the `collection_endpoint` and `dashboard_endpoint` from the Terraform outputs for later.

Go back to the main directory and run the `logstash_setup.yml` playbook. It will prompt you for the `collection_endpoint` and AWS access keys.

If you don't want to use your root access keys, you'll need the access keys to at least have access to the `AmazonOpenSearchIngestionFullAccess` permission.

```bash
cd ..
ansible-playbook logstash_setup.yml
```

Once this is complete, Logstash will immediately start sending logs to the OpenSearch collection. You can view the logs by navigating to the `dashboard_endpoint`.

The indices are automatically created, but you will need to [create an index pattern](https://opensearch.org/docs/latest/dashboards/management/index-patterns/) to search them in the `Discover` tab.

For more information on using OpenSearch Dashboards, check the documentation [here](https://opensearch.org/docs/latest/dashboards/index/).

Run `terraform destroy` in the `opensearch` directory to tear down the logging analytic resources. You can reuse and persist the OpenSearch collection across multiple devnets, so you should only need to do this if you are done testing.

If you need to adjust the Logstash template, it can be found at `templates/logstash.config`.