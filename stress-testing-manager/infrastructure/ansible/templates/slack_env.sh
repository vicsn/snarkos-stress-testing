# Ansible-managed — Slack env for snarkos-stress-testing (do not edit)
#
# Values are populated from GCP Secret Manager by setup.yml. This template
# is kept for backwards compatibility with callers that still use it via
# ansible.builtin.template.
export SLACK_TOKEN="{{ slack_token | default('') }}"
export SLACK_CHANNEL_ID="{{ slack_channel_id | default('') }}"
export CHANNEL_ID="{{ slack_channel_id | default('') }}"
