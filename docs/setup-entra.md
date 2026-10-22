# Entra ID and Exchange Online setup

Done once by a Microsoft 365 administrator. One Entra app can serve many Rails applications.

## 1. Register the app

1. Microsoft Entra admin center → **App registrations** → **New registration**.
2. Name it, e.g. "Rails Mailer". Supported account types: **this organizational directory only**.
   No redirect URI.
3. Note the **Application (client) ID** and **Directory (tenant) ID**.
4. **Certificates & secrets** → **New client secret**. Choose an expiry and set a reminder before
   it. Copy the secret **value** once; store it in AWS Secrets Manager (see
   [setup-aws.md](setup-aws.md)) or your secret store. Entra allows two secrets at a time, which
   is what makes rotation without downtime possible ([runbooks.md](runbooks.md#rotate-the-client-secret)).

## 2. Create the sending mailbox

Create a **shared mailbox** in Exchange Online, e.g. `notifications@example.com` (shared mailboxes
need no license). Decide with your administrator:

- the mailbox **display name**: recipients may see it instead of the From name your app sends;
- what happens to replies (auto-reply, forwarding, or nobody reads it);
- retention, and who may open the mailbox.

## 3. Allow the app to send only as that mailbox

Grant `Mail.Send` through **Exchange Online RBAC for Applications**, scoped to a group. Do **not**
grant `Mail.Send` under *API permissions* in Entra: permissions add up, and a tenant-wide grant
would let the app send as every mailbox.

```powershell
Connect-ExchangeOnline

# Mail-enabled security group containing only the mailbox(es) the app may send as
New-DistributionGroup -Name "sg-rails-mail-senders" -Type Security -Members notifications@example.com

# Link the Entra app's service principal (enterprise application object id) to Exchange
New-ServicePrincipal -AppId <client-id> -ObjectId <enterprise-app-object-id> -DisplayName "Rails Mailer"

# Scope and role assignment
New-ManagementScope -Name "Rails mail senders" `
  -RecipientRestrictionFilter "MemberOfGroup -eq '<distinguished name of sg-rails-mail-senders>'"
New-ManagementRoleAssignment -App <client-id> -Role "Application Mail.Send" `
  -CustomResourceScope "Rails mail senders"
```

Check before going live (changes can take up to an hour to apply):

```powershell
Test-ServicePrincipalAuthorization -Identity <client-id> -Resource notifications@example.com   # InScope: True
Test-ServicePrincipalAuthorization -Identity <client-id> -Resource <any-other-mailbox>         # InScope: False
```

To let another application use its own mailbox later, add that mailbox to the group.

## 4. Email authentication

Mail now leaves from Exchange Online. Make sure SPF, DKIM and DMARC for the sending domain
cover Exchange Online.

## 5. Optional: journaling and retention

`save_to_sent_items: false` stops the mailbox from keeping a copy. Tenant-wide journaling rules
or retention policies can still capture messages elsewhere; confirm this matches your
compliance requirements.

## References

- [user: sendMail](https://learn.microsoft.com/graph/api/user-sendmail)
- [Client credentials flow](https://learn.microsoft.com/entra/identity-platform/v2-oauth2-client-creds-grant-flow)
- [RBAC for Applications in Exchange Online](https://learn.microsoft.com/exchange/permissions-exo/application-rbac)
