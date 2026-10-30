# Bootstrap the first SYSTEM_ADMIN

Run bootstrap through the deployed release with infrastructure or release access:

```sh
bin/golf_scoring eval 'GolfScoring.Release.bootstrap_system_admin()'
```

The command uses `GOLF_SCORING_BOOTSTRAP_EMAIL` and, when creating a new staff account, `GOLF_SCORING_BOOTSTRAP_PASSWORD`. It does not add an HTTP route. The release eval starts the application services needed for PostgreSQL and Ash, with the Phoenix web server disabled for that eval process.

## Create a new StaffUser

Read the password without echoing it. The literal password is never part of a shell command, so it does not enter shell history.

```sh
read -r -p 'Staff email: ' GOLF_SCORING_BOOTSTRAP_EMAIL
read -r -s -p 'Staff password: ' GOLF_SCORING_BOOTSTRAP_PASSWORD
printf '\n'
export GOLF_SCORING_BOOTSTRAP_EMAIL
export GOLF_SCORING_BOOTSTRAP_PASSWORD
trap 'unset GOLF_SCORING_BOOTSTRAP_EMAIL GOLF_SCORING_BOOTSTRAP_PASSWORD' EXIT

bin/golf_scoring eval 'GolfScoring.Release.bootstrap_system_admin()'

unset GOLF_SCORING_BOOTSTRAP_EMAIL GOLF_SCORING_BOOTSTRAP_PASSWORD
trap - EXIT
```

Use a password that meets the existing staff password policy. The release function supplies the password as both the password and confirmation inputs to the existing `StaffUser.provision_staff_user` action. AshAuthentication handles password hashing.

The release function removes `GOLF_SCORING_BOOTSTRAP_PASSWORD` from its process environment before starting the application runtime. The shell trap clears both variables if the command fails.

## Promote an existing active StaffUser

The target account must have `status = active` and `system_admin = false`. Read and export only its email. Leave the password variable unset.

```sh
read -r -p 'Staff email: ' GOLF_SCORING_BOOTSTRAP_EMAIL
export GOLF_SCORING_BOOTSTRAP_EMAIL
unset GOLF_SCORING_BOOTSTRAP_PASSWORD
trap 'unset GOLF_SCORING_BOOTSTRAP_EMAIL GOLF_SCORING_BOOTSTRAP_PASSWORD' EXIT

bin/golf_scoring eval 'GolfScoring.Release.bootstrap_system_admin()'

unset GOLF_SCORING_BOOTSTRAP_EMAIL GOLF_SCORING_BOOTSTRAP_PASSWORD
trap - EXIT
```

Promotion preserves the account's existing password. Bootstrap refuses suspended or disabled accounts and does not reactivate them.

## Repeat and recovery behavior

Bootstrap eligibility comes from the current database state: the count of StaffUsers with `status = active` and `system_admin = true`.

If an active SYSTEM_ADMIN exists, the command refuses before it looks up or changes the requested target. It writes no success audit event and creates no StaffUser. Bootstrap is eligible again only in an exceptional or recovery state where the active SYSTEM_ADMIN count is zero. There is no permanent bootstrap-used flag or token.

Every successful create or promotion writes one `system_admin_bootstrapped` AuditEvent in the same PostgreSQL transaction as the StaffUser change.
