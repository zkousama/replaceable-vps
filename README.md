# One VPS, described in files

OpenTofu and Ansible for a single Hetzner box that runs Docker: the server,
its firewall, the DNS records that point at it, and the configuration on top.
Small on purpose. It is the shape of a one-server deployment where the
interesting question is not how to scale it but how to replace it without a
bad afternoon.

The thing worth copying is in [`infra/iac/dns.tf`](infra/iac/dns.tf), and it is
one line:

```hcl
content = hcloud_server.prod.ipv4_address
```

A record defined that way is a dependent of the server rather than a copy of
its address, so replacing the machine is the entire instruction for a cutover.
Everything else here follows from wanting that to be true.

I wrote it up in [The bigger server was
cheaper](https://ousama.pages.dev/writing/the-bigger-server-was-cheaper), which
is the same pattern with the numbers from a real replacement.

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

Then configure the machine. Bootstrap runs once, as root on port 22, because
that is the only state a new server is in:

```sh
cd ../ansible
cp inventory.example.ini inventory.ini         # tofu output -raw inventory_line
cp group_vars/all.yml.example group_vars/all.yml
ansible-playbook bootstrap.yml -l prod -u root -e ansible_port=22
ansible-playbook site.yml -l prod
```

Run `site.yml` twice. The second run reporting `changed=0` is the only
evidence the roles are idempotent, and it is what makes a snapshot of this
machine a known quantity instead of a mystery you are cloning.

To replace the machine later: [docs/replace-a-server.md](docs/replace-a-server.md).

## Waiting for capacity

Sold out is a real answer from a cloud provider, and there is no announcement
when it stops being true. The newer server types in particular spend weeks in
limited availability, so a plan that depends on one is a plan that waits.
`tofu apply` reports this as `resource_unavailable`, with no hint that capacity
is the problem.

[`scripts/wait-for-capacity.sh`](scripts/wait-for-capacity.sh) asks the API
which of the locations you would accept can currently sell the type you want,
and pushes a notification when the answer changes for the better:

```sh
*/30 * * * * HCLOUD_TOKEN=... NTFY_URL=https://ntfy.sh/<topic> \
  /usr/local/bin/wait-for-capacity.sh --type cx33 --locations nbg1,hel1
```

It compares against the last answer it wrote down, so the notification hangs
off the transition rather than the state. A check that fires on the state sends
a push every half hour once the answer turns good, and a channel that repeats
itself is one you have stopped reading by the time it says something you need.

It needs curl and python3 and nothing else in this repository, so it is usable
on its own. Send a test push before trusting it: an alerting path you have not
seen work is a guess.

## Decisions, with the reasons

**State in object storage, not on a laptop.** The endpoint hostname carries
the account id, so it is passed at `init` time rather than committed. R2 keys
are 32 characters where AWS keys are 20, and mixing them up produces an error
about key length that takes a while to recognise, so `scripts/preflight.sh`
checks the shape.

**Two firewalls.** The provider's, at the edge, and ufw on the machine. They
fail differently: one is a setting in an account somebody else can change, the
other is a file a snapshot carries with it.

**SSH off its default port.** This stops nothing determined. It empties the
logs of the untargeted scanning that makes a real attempt hard to see. Key-only
auth, `AllowUsers`, and fail2ban are the parts that matter, and moving the port
means telling fail2ban too, or it runs happily and watches nothing.

**`prevent_destroy` on the server, hardcoded.** The provider-side delete
protection blocks the API and the console but not `tofu destroy`, which is a
different path. `prevent_destroy` is the only thing that blocks that one, and
it cannot be a variable because OpenTofu still does not accept them in
meta-arguments. A deliberate replacement comments it out in a commit that says
why, and the commit restoring it is the other half of the pair.

**`ignore_changes = [image]`.** Image slugs resolve to numeric ids that rotate
underneath them, so without this a plan offers to rebuild the server every time
the distribution publishes a build. It also means a replacement is driven by
`-replace` rather than by editing the image and waiting for a diff, which is
the honest way round: the variable says where the new machine comes from, the
flag asks for a new machine at all.

**Security updates only, and no automatic reboot.** Taking the whole updates
pocket unattended means new minor versions of everything at 6am, which is a
different risk from being unpatched and a worse one to hear about from someone
else. Kernel updates still need a reboot; `/var/run/reboot-required` says when,
and you pick the minute.

**Docker logs capped.** The default is unbounded, and an uncapped log is how a
disk fills up 8 months after anybody last looked, presenting as a database
problem.

## What this is not

No load balancer, no second server, no Kubernetes, no service mesh. One box
with a reverse proxy in front of containers, which is the right size for a lot
of things and the wrong size for the rest.

It also does not deploy applications. It gets you a hardened host with Docker
and a working DNS record; what runs on it is a separate concern, and mixing the
two is how you end up unable to touch the machine without redeploying the app.

## Licence

MIT.
