# Tests supporting multiple versions of SnarkOS

The current versions of the observability tests, maintained by the Eiger DevOps team is being updated and
a bit stripped down with automated tests in mind. With that in mind we should think on what we can change to make the
following requirements (from https://github.com/provableHQ/stress-observability/issues/223) happen:

```
The stress tests can deploy a network with two snarkOS versions: an honest and a malice version,
the malice version is used for the malicious-* tests.

We need some related functionality, namely to run different honest snarkOS versions side by side.
This allows us to test asynchronous network upgrades, where old nodes are one by one updating to new nodes.

It would be great to add a new update_nodes test, which ingests a commit hash to install on the machines one by one with some delay.
If we ever want to run other custom tests during the upgrade process, we'd need to make a new testrunner for this.
```

To make all of this happen, we have to:
1. Make the auto-builder application support multiple versions of SnarkOS. In the moment, to make it as straight forward as possible when a new version is released,
   it supports only one that it puts on a specific place, that then is used by the ansible/terraform/bash scripts.
2. Make sure the auto-tester is deterministic. This means when there is a new version, the auto tester knows what to execute as the alternative version.
3. Write the new test with terraform/ansible.

All of these steps are doable and will help us join our repositories and tests at one point.
I'll be writing my plan/thoughts related to every point above.

## Make auto-builder support multiple versions of SnarkOS

In the moment the builder receives a new git tag/branch, builds a new SnarkOS executable and puts it on a permanent place (S3, but we'll make it configurable in the future).
When the auto-tester executes the bash script for running tests it just works with the S3 bucket configured and gets that version for the tests.
This was a decision we made to make the tests simpler and not dependable on anything outside the current AWS account (something we can make also smarter in the future, so the cloud can be switched).

The task here is the following:
1. Make the auto-builder build SnarkOS and store it under its git hash. That way for every hash we'll have a built version.
2. Make the latest built version also the `current` one (so we have a pointer to the latest one) so the tests can use it as main.
3. Make the previous `current` version the `previous` one (so we have a pointer to the one built before the latest) so it can be used as alternative one.
4. As a small but easy optimisation, before building check if the git hash has a built already stored and skip it. That way 5 tags pointing to the same hash won't trigger 5 builds.

With this change we can write automated tests that can start multiple nodes with the `previous` versions and gradually update to the `current` version, for example.
This is for the automated testing, but we can also run a test with specific stored hash for the `previous` versions and specific one for the `current` one.

With this we both support auto-builds and automated testing without any manual intervention and manual runs with specific hashes.

## Make the Automated tester deterministic

With the above work we always will have `current` and `previous` version so it is deterministic.
But we should support configurations like - "this hash is always the previous version, until the configuration is updated".

This is specific for the application running the tests automatically and not to the terraform/ansible infrastructure.

## Write a new test that does asynchronous network updates

If the test can be configured to use `current` and `previous` SnarOS executable then its idea will be:
1. Start all nodes with `previous` SnarkOS version running.
2. Stop a node and update the version to `current`. Run it. Wait. Make checks.
3. Repeat the above for all nodes.

With the above ideas both manual runs and automated runs should work.
For this test to work better and with the changes I suggested for the auto-builder, we should return the option to use
local pre-build SnarkOS binaries for specific tests (as we stripped many options like that down initially to make things simpler).

One other idea to have in mind is to use [terraform workspaces](https://developer.hashicorp.com/terraform/language/state/workspaces) so we can
execute tests in parallel. This is a big optimization and needs its own design document, but the idea is to divide the tests in groups and implement modules
in the automated tester application that can run them in parallel. For example the multiple-versions-of-snarkos group tests can be ran asynchronously to the "normal" tests.
I had this idea for also running some time-taking tests by themselves in parallel to the others too.

