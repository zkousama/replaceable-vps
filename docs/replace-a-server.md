# Replacing the server

For when the machine has to be a different machine: a type in another family,
a different location, a rebuild from a known image. A resize within one family
is not this. That is a `server_type` change and an in-place apply, and the
provider keeps the disk.

This is the destructive one. Read it to the end before starting.

## What makes it cheap

Every DNS record takes its value from `hcloud_server.prod.ipv4_address`
rather than from an address. The records are dependents of the server in one
graph, so replacing the server is the whole instruction: they re-evaluate on
the way out of the same apply. There is no list of names to work through and
nothing to miss.

If the provider hands the new machine the same addresses, the records have no
diff at all. That is luck, not the design, and the design is what means it
does not matter either way.

## Before you touch anything

```sh
./scripts/preflight.sh
```

Every credential checked against the provider that has to accept it. The one
this exists for is DNS: a plan does not call that API until a record changes,
so a revoked token there is invisible until the apply that needs it, which is
halfway through the cutover.

Then, in order:

1. **Confirm the type is orderable.** Sold out is a real answer, and
   `tofu apply` reports it as `resource_unavailable` with no hint that
   capacity is the problem. Either check by hand or leave
   `scripts/wait-for-capacity.sh` on a schedule and get told.
2. **Snapshot the machine.** Minutes, and it is what "boot the new one from
   the old one" means.
3. **Take a logical dump of anything stateful, somewhere else.** A snapshot
   and the provider's backups both live in the account that holds the thing
   they protect. This is the copy that survives losing the account.
4. **Write down what the machine is serving now.** Container names and
   health, the version that is deployed, one request through the front door.
   You cannot tell whether the new box came back right if you did not write
   down what right looked like.

## The apply

5. **Point the variables at the new shape** by copying
   `infra/iac/migration.auto.tfvars.example` to `migration.auto.tfvars`. The
   file being on disk is the reminder that the protections are off; deleting
   it is how they go back on.

6. **Comment out `prevent_destroy`** in `server.tf`, with a marker saying why
   and a commit of its own. The commit that restores it is the other half of
   the audit trail.

7. **Turn the provider-side protections off, out of band:**

   ```sh
   hcloud server disable-protection prod delete rebuild
   ```

   Not optional, and not obvious. The plan shows
   `delete_protection: true -> false` as part of the replacement, which reads
   like the provider taking care of it. It does not flip the flag before
   issuing the destroy, so the destroy is refused and the apply stops in the
   middle. Doing this first costs nothing when they are already off.

8. **Plan, and read all of it.**

   ```sh
   tofu plan -replace=hcloud_server.prod
   ```

   1 to add, 1 to destroy, and the records either updating or showing no
   change. Anything else is a question, not a surprise to be clicked through.

9. **Apply.**

   ```sh
   tofu apply -replace=hcloud_server.prod
   ```

10. **Expect the host key to have changed.** First boot from a snapshot
    regenerates the SSH host keys on purpose, so a hundred clones of one image
    are not all carrying the same one. Your client will refuse to connect and
    say so loudly. That is the feature working:

    ```sh
    ssh-keygen -R prod
    ```

11. **Check it against what you wrote down in step 4.** Services up, a request
    through the front door, and the stateful things answering, not just
    running.

## Putting the safety equipment back

12. **Move the defaults in `variables.tf` to the new values.** Do this before
    the next plan, not after. With the migration tfvars deleted, a plan falls
    back to the defaults in source, and if `server_type` still names the old
    one the plan will offer to rescale the new machine back to where it
    started. In place, keeping the data, undoing the morning. It is caught by
    reading the plan and nowhere else.

13. **Delete `migration.auto.tfvars`, restore `prevent_destroy`, and apply.**
    The plan here should be 1 resource changed and 2 booleans flipped. If it
    says anything about `server_type`, go back to step 12.

14. **Keep the snapshot for a week,** then delete it. Things that only surface
    under a week of real traffic are the reason it is still there.

## If it goes wrong

The snapshot is the answer to almost everything: apply again from it and you
are back where you started, minus whatever was written since it was taken.
The logical dump is the answer to the rest. Both were taken in steps 2 and 3,
which is the only reason this section is 2 sentences long.
