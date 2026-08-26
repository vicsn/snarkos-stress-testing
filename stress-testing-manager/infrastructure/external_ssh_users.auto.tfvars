# stress-testing-manager/infrastructure/external_ssh_users.auto.tfvars
#
# External users authorized to SSH into the STM as the "ubuntu" account.
# This file is gitignored — each engineer maintains their own local copy.
#
# Terraform reads this file (auto-loaded via the .auto.tfvars suffix), and:
#   1. `network.tf`      -> firewall rule allows TCP/22 from each user's IP
#   2. `ansible_vars.tf` -> writes <repo-root>/keys.pub (one public_key per line)
#   3. `common/roles/shared_ssh_keys` -> installs each line into
#                             ~ubuntu/.ssh/authorized_keys
#
# Field reference:
#   name       - unique per entry; written to authorized_keys `comment` for
#                grep-based revocation. Duplicate names collapse to one line.
#   ip_address - either a bare IPv4 (gets /32 appended automatically) or a
#                pre-formed CIDR (used verbatim). No IPv6 support yet.
#   public_key - full SSH public key line. Supported prefixes:
#                ssh-ed25519, ssh-rsa, ecdsa-sha2-nistp256|384|521.
#
# ORDER MATTERS: after editing this file, run `tf_stack.sh provision`
# BEFORE `tf_stack.sh setup`. Running `setup` alone will silently reuse
# the previous generation's keys.pub.
#
# CLOUDFLARE WARP IP's
#     ## 100.96.0.0/12              (default WARP v4)
#     ## 2606:4700:cf1:1000::/64    (default WARP v6)
#     ## fd01:73bb:28e9::/64        ( other  WARP v6)

external_ssh_users = [
  {
    name       = "victor.s.nicolaas@protonmail.com"
    ip_address = "100.96.0.0/12"
    public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPSfFj2Kf8WUyEtNKImFVgj6rO+1OGxyUguixNPjLmN5 victor.s.nicolaas@protonmail.com"
  },
  {
    name       = "ljedrz@gmail.com"
    ip_address = "100.96.0.0/12"
    public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIKhZZUm/cdmoQqJ/MR2lr1OafeM3MZBXtP3I50DCQ6D ljedrz@gmail.com"
  },
  {
    name       = "ljedrz@gmail.com"
    ip_address = "100.96.0.0/12"
    public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHIS7O9hXtMOjotY33xoL/ecGxXgo087HuiwxZJhKqGh ljedrz@gmail.com"
  },
  {
    name       = "mikenichols@provable.com"
    ip_address = "104.28.172.156"
    public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIJ6fEkk5FO2j4nJrbO6ESrk6K3rP/XQ2al8qVfewaz0 mikenichols@provable.com"
  },
  {
    name       = "beck.ct@gmail.com"
    ip_address = "100.96.0.0/12"
    public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDmj24ISNJfPpyqM5oFLoKbUT16xgM0w6s07PF7paGfm beck.ct@gmail.com"
  },
  {
    name       = "eran@rundste.in"
    ip_address = "100.96.0.0/12"
    public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKEBWO8YFW/PwCNzauTF/bGaXSKhuFWkS6eBbfe7Z0vI eran@rundste.in"
  },
  {
    name       = "sergii"
    ip_address = "100.96.0.0/12"
    public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPtwChogeZB6S56lmKWHT6FSUStMZ8iHKM4cEikgTnH/ sergii@aleo.org"
  },
  {
    name       = "john.reynolds"
    ip_address = "100.96.0.0/12"
    public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII/4UHLfS2UjtJdoSBH7oQdTmTiWlY2RU7WWqTw5nXWY"
  },

]
