# One VPS, described in files

OpenTofu and Ansible for a single Hetzner box that runs Docker: the server, its
firewall, the DNS records that point at it, and the configuration on top. It's
deliberately small, and built around one operation: replacing the machine with
an identical one. That's what you want on the day your provider reprices its
lineup, or the plan you're on stops being the cheap one.

The whole repository is arranged around one line, in
[`infra/iac/dns.tf`](infra/iac/dns.tf):

```hcl
content = hcloud_server.prod.ipv4_address
```

A record defined that way is a dependent of the server rather than a copy of
its address, so replacing the machine is the entire instruction for a cutover.
Everything else here follows from wanting that to be true.

There is a write-up of a real replacement that used this pattern, with the
numbers from the day, and this README will link it once it is published.

## What is in here

```
infra/iac/          the server, the firewall, the DNS records
infra/ansible/      what gets installed on it
scripts/            preflight the credentials, wait for capacity
docs/               the runbook for replacing the machine
```

## Using it

```sh
cd infra/iac
cp terraform.tfvars.example terraform.tfvars   # edit it
tofu init -backend-config="endpoints={s3=\"https://<account>.r2.cloudflarestorage.com\"}"
tofu apply
```

`ssh_source_cidrs` has no default. Who can reach SSH is a decision, not
something to inherit from a file you skimmed.

`CLOUDFLARE_API_TOKEN` has to be set even before a single DNS record exists.
The records are declared in the configuration, so OpenTofu configures their
provider on every plan, and the error when it is missing talks about `api_key`
rather than about DNS.

Then configure the machine. Bootstrap runs once, as root on port 22, because
that is the state a new server arrives in:

```sh
cd ../ansible
cp inventory.example.ini inventory.ini         # tofu output -raw inventory_line
cp group_vars/all.yml.example group_vars/all.yml

# Ansible will not connect to a host it has never seen, and it is right not
# to. This trusts the key on first use; the paranoid version reads the
# fingerprint off the server's console before accepting it.
ssh-keyscan -p 22 -t ed25519 <the ip> >> ~/.ssh/known_hosts

ansible-playbook bootstrap.yml -l prod -e ansible_port=22
ssh-keyscan -p <ssh_port> -t ed25519 <the ip> >> ~/.ssh/known_hosts
ansible-playbook site.yml -l prod
```

The port is `-e` rather than `-u`-style flags because extra vars are the only
level that outranks the inventory. There is no `-u root` here for the same
reason: the playbook's own plays set the user, and an `ansible_user` in the
inventory would beat both.

Run `site.yml` twice. If the second run reports `changed=0` the roles are
idempotent; if it doesn't, something in them rewrites a file on every pass, and
a snapshot of the machine will carry whatever that is.

To replace the machine later: [docs/replace-a-server.md](docs/replace-a-server.md).

## Waiting for capacity

Cloud providers do run out of a server type, and nothing announces it when
they stop. Newer types can spend weeks in limited availability. `tofu apply`
reports it as `resource_unavailable`, which doesn't say whether the problem is
the type, the location or your account.

[`scripts/wait-for-capacity.sh`](scripts/wait-for-capacity.sh) asks the API
which of the locations you would accept can currently sell the type you want,
and pushes a notification when the answer changes for the better:

```sh
*/30 * * * * HCLOUD_TOKEN=... NTFY_URL=https://ntfy.sh/<topic> \
  /usr/local/bin/wait-for-capacity.sh --type cx33 --locations nbg1,hel1
```

It compares against the last answer it wrote down, so the push hangs off the
transition rather than the state: fire on the state and cron notifies every
half hour from the moment capacity appears, which is a channel you'll mute
inside a day. Send a test push and watch it arrive before leaving it running.

It needs curl and python3 and nothing else from this repository.

## Decisions, with the reasons

**State in object storage.** The endpoint hostname carries the account id, so
it goes in at `init` time rather than into a file. R2 keys are 32 characters
where AWS keys are 20, and loading the wrong ones fails with a message about
key length that takes a while to place, so `preflight.sh` checks the shape.

**2 firewalls.** The provider's at the edge, ufw on the machine. One is a
setting in an account other people can change, the other is a file a snapshot
carries with it.

**SSH off its default port.** For log volume, not security: untargeted scanning
stops filling the auth log, so a real attempt is easier to spot. Key-only auth,
`AllowUsers` and fail2ban do the actual work.

**`prevent_destroy`, hardcoded.** The provider's delete protection blocks the
API and the console but not `tofu destroy`. This blocks that path, and OpenTofu
won't take a variable in a meta-argument, so a deliberate replacement comments
it out in a commit that says why.

**`ignore_changes = [image]`.** Image slugs resolve to numeric ids that rotate
underneath them, so without it every plan offers to rebuild the server. It also
means a replacement is asked for with `-replace` rather than by editing the
image and waiting for a diff.

The rest of the reasoning lives next to what it describes, in the comments.

## Scope

One machine, with a reverse proxy in front of containers, and everything here
assumes it: the DNS records point at a server rather than at a load balancer,
and the playbooks configure a host rather than a fleet. More than one machine
is a different design rather than a bigger version of this one.

It stops short of deploying anything, too. What you get is a hardened host with
Docker on it and a DNS record that resolves to it. Whatever runs there is a
separate concern, and keeping the 2 apart is why the machine can be replaced
without touching the application.

## Checks

`tofu fmt`, `tofu validate` against the real providers, `--syntax-check` on
both playbooks and shellcheck on both scripts, on every push. All of it runs
without credentials, which is also its ceiling: it proves the configuration
parses and the playbooks are well formed, and nothing more.

The rest was done by hand on 12 September 2026: a cx23 in nbg1 provisioned
from these files, bootstrapped, and converged with `site.yml`, which reported
`changed=0` on its second run. Verified on the box afterwards: sshd on the
moved port with root and password logins off, ufw active, fail2ban watching
that same port, Docker with its logs capped, and unattended upgrades taking
security only. 5 things were broken when that run started and are fixed here.
The server was destroyed the same hour.

## Licence

MIT.
