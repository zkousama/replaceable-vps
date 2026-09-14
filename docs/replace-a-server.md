# Replacing the server

For when the machine has to be a different machine: a different location, a
type with a smaller disk or another architecture, a rebuild from a known image.
A resize that keeps the architecture and doesn't shrink the disk isn't this.
That's a `server_type` change, an in-place apply, and the provider keeps the
disk.

This one destroys the machine. Read it to the end before starting.

## What makes it cheap

Every DNS record takes its value from `hcloud_server.prod.ipv4_address` rather
than from an address, so the records are dependents of the server in one graph.
Replacing the server is all you have to ask for: they re-evaluate on the way
out of the same apply, and there's no list of names to work through.

If the provider happens to hand the new machine the same addresses, the records
won't even show a diff. Don't count on that. The reference is what makes it
unimportant either way.

## Before you touch anything

```sh
./scripts/preflight.sh
```

Every credential checked against the provider that has to accept it. The one
this exists for is DNS: nothing touches that token between cutovers, so a
revoked one first shows up when the plan in step 8 reads the records, after the
snapshot is taken and the protections are off.

Then, in order:

1. **Confirm the type is orderable.** Sold out is a real answer, and `tofu
   apply` reports it as `resource_unavailable` with no hint that capacity is
   the problem. Check by hand, or leave `scripts/wait-for-capacity.sh` on a
   schedule and get told.
2. **Snapshot the machine.** A couple of minutes, and it's what "boot the new
   one from the old one" means.
3. **Take a logical dump of anything stateful, somewhere else.** A snapshot and
   the provider's backups both live in the account that holds the thing they
   protect. This one doesn't.
4. **Write down what the machine is serving now.** Container names and health,
   the version that's deployed, one request through the front door. Without
   that you'll be comparing the new box against your memory of the old one.

## The apply

5. **Point the variables at the new shape** by copying
   `infra/iac/migration.auto.tfvars.example` to `migration.auto.tfvars`. The
   file being on disk is the reminder that the protections are off; deleting it
   is how they go back on.

6. **Comment out `prevent_destroy`** in `server.tf`, with a marker saying why,
   in a commit of its own. The commit that restores it is the other half of the
   audit trail.

7. **Turn the provider-side protections off, out of band:**

   ```sh
   hcloud server disable-protection prod delete rebuild
   ```

   The plan shows `delete_protection: true -> false` as part of the
   replacement, which reads like the provider handling it for you. It doesn't
   flip the flag before issuing the destroy, so the destroy comes back refused
   and the apply stops in the middle. Running this first costs nothing if
   they're already off.

8. **Plan, and read all of it.**

   ```sh
   tofu plan -replace=hcloud_server.prod
   ```

   1 to add, 1 to destroy, and the records either updating or showing no
   change. Anything else is a question to answer before you type yes.

9. **Apply.**

   ```sh
   tofu apply -replace=hcloud_server.prod
   ```

10. **Expect the host key to have changed.** First boot from a snapshot
    regenerates the SSH host keys, so a hundred clones of one image don't all
    present the same one. Your client will refuse to connect and say so at
    length:

    ```sh
    ssh-keygen -R prod
    ```

11. **Check it against what you wrote down in step 4.** Services up, a request
    through the front door, and the stateful things answering rather than just
    running.

## Putting the safety equipment back

12. **Move the defaults in `variables.tf` to the new values.** Do this before
    the next plan. With the migration tfvars deleted, a plan falls back to the
    defaults in source, and if `server_type` still names the old one, that plan
    will offer to rescale the brand-new machine back to where it started: in
    place, keeping the data, undoing your morning. The plan output is where you
    catch this, and it's a legal change, so nothing else will stop it.

13. **Delete `migration.auto.tfvars`, restore `prevent_destroy`, and apply.**
    The plan should be 1 resource changed and 2 booleans flipped. If it says
    anything at all about `server_type`, go back to step 12.

14. **Keep the snapshot for a week,** then delete it. It's there for the
    problems that only turn up after a few days of real traffic.

## If it goes wrong

Apply again from the snapshot and you're back where you started, minus anything
written since it was taken. For the writes in that gap, there's the logical
dump from step 3. Both of those were taken before the destroy.
