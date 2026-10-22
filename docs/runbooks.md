# Runbooks

## First live test

Run once after the Entra app, mailbox and secret exist, on a staging host:

```shell
bin/rails ms_graph_mailer:check
bin/rails "ms_graph_mailer:smoke[you@example.com,Jane Doe via My App]"
```

Send to an internal address and to an external one (e.g. Gmail), then check:

| Check | Expected | If not |
|---|---|---|
| Message arrives | Yes | See [Troubleshooting](#troubleshooting) |
| Shared mailbox **Sent Items** (with `save_to_sent_items: false`) | Empty | Ask the Microsoft 365 admin about journaling/retention rules |
| **Sender name** the recipient sees | `Jane Doe via My App` | Exchange shows the mailbox display name instead. Either accept one name for all mail (set a suitable mailbox display name), or give each app its own mailbox (`user_id`) with its own display name. No code change either way. |

## Rotate the client secret

No application restart is needed.

1. Entra → App registrations → your app → Certificates & secrets → **New client secret**. Keep the
   old secret.
2. Update `client_secret` in the AWS Secrets Manager secret.
3. Wait. Every process picks up the new value within `aws_secret_ttl` (default 10 minutes), or
   immediately if Entra rejects the old secret first.
4. After more than an hour, check Entra → Enterprise applications → your app → Sign-in logs →
   *Service principal sign-ins*: only the new credential (key id) should be in use.
5. Delete the old secret in Entra. Set a reminder before the new one expires.

With static credentials, deploy the new value and restart instead.

## Roll back to SMTP

1. Set `MAIL_DELIVERY_METHOD=smtp` for the application (requires `smtp_settings`).
2. Restart web and background-job processes.
3. `bin/rails ms_graph_mailer:check` shows `delivery_method: smtp`.

Unset the variable and restart to return to Graph.

## Upgrade the gem

1. Read [CHANGELOG.md](../CHANGELOG.md).
2. Change the `tag:` in the Gemfile (e.g. `tag: "v1.1.0"`), then `bundle update ms_graph_mailer`.
3. Deploy to staging, run `check` and `smoke`, then production.

## Troubleshooting

| Error (`#status` / `#code`) | Meaning | Fix |
|---|---|---|
| `ConfigurationError` at boot | Invalid configuration | Read the message; see [configuration.md](configuration.md) |
| `ConfigurationError: ... needs the aws-sdk-secretsmanager gem` | Gem missing | Add `gem "aws-sdk-secretsmanager"` |
| `TransientError: Could not read secret ... (Aws::...AccessDeniedException)` | IAM role cannot read the secret | Fix the IAM policy ([setup-aws.md](setup-aws.md)) |
| `TransientError: Could not read secret ... (Aws::Errors::MissingCredentialsError)` | No AWS credentials on the host | Attach an instance/task role |
| `401 invalid_client` | Client secret wrong, expired or deleted | Update the secret in Secrets Manager |
| `400 invalid_request` / `unauthorized_client` | Tenant or client id wrong, app disabled | Check the secret's ids |
| `403 ErrorAccessDenied` | The mailbox is outside the app's Exchange RBAC scope | Add the mailbox to the scope group; re-run `Test-ServicePrincipalAuthorization` |
| `404 ErrorInvalidUser` / `ResourceNotFound` / `MailboxNotEnabledForRESTAPI` | `user_id` is not an Exchange Online mailbox | Check `user_id`; on-premises mailboxes are not supported by Graph |
| `ErrorSendAsDenied` | From differs from `user_id` and `enforce_from` is off | Turn `enforce_from` on or fix the mailer's From |
| `DeliveryError: Message is ... bytes` | Request over ~4 MB | Reduce attachments |
| `429 TooManyRequests` (`TransientError`) | Throttled | Retried automatically; if persistent, reduce volume or split mailboxes |
| `DeliveryError: Timed out waiting for graph.microsoft.com` | No response within `read_timeout` | Not retried (may have been sent). Check connectivity; check the Exchange message trace before resending. |
| `TransientError: Connection to ... failed` | Network/firewall | Allow outbound 443 to the hosts in [setup-aws.md](setup-aws.md#3-network) |

Exchange admin center → Mail flow → **Message trace** shows what the mailbox sent (metadata only).
