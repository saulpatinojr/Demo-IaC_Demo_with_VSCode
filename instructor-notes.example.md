# Instructor notes — workshop identifiers (PRIVATE when filled in)

Copy this file to `instructor-notes.md` and fill in the real values.
`instructor-notes.md` is gitignored. Note what is and isn't secret here: the
app/tenant/subscription IDs are deliberately **committed** to the repo as
in-code workflow fallbacks — they are identifiers, not credentials, and this
classroom environment is deleted after the event — so seeing them in
`.github/workflows/*.yml` is expected, not a leak. What belongs **only** in
your gitignored copy is the rest: the shared storage account name and any
roster or tenant notes.

## Shared deployment identity (Entra app registration)

| Item                     | Value                     |
| ------------------------ | ------------------------- |
| App (client) ID          | `<app-client-id>`         |
| Tenant ID                | `<tenant-id>`             |
| Subscription ID          | `<subscription-id>`       |
| Shared storage account   | `<storage-account-name>`  |

One app registration is shared by the whole class. It holds Contributor on
every student resource group and is the identity that actually deploys —
students themselves hold only Reader. Each student fork authenticates to it
through a federated credential.

**Subject format matters.** GitHub repos created after 15 Jul 2026 — which
includes every workshop fork — always present the immutable, ID-enriched
OIDC subject, so each federated credential's subject must be:

    repo:User<nn>-TechCon@<owner-id>/Demo-IaC_Demo_with_VSCode@<repo-id>:ref:refs/heads/main

The classic name-only subject (`repo:User<nn>-TechCon/Demo-IaC…`) fails with
`AADSTS700213: No matching federated identity record found`. When a login
fails, the fork's Actions log ("Federated token details") prints the exact
subject to copy into the credential. One Entra *flexible* federated
credential with a claims-matching expression can also cover every fork with
a single entry instead of 35.

The L1–L4 and teardown workflows carry the three IDs as in-code fallbacks
(this classroom environment is deleted after the event), so forks work with
zero secrets; `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID`
secrets on a fork still take precedence when present. The shared storage
account is namespaced per student by key — record its name here.

## Roster and naming

- Students: `User01-TechCon` … `User30-TechCon`; testing: `User31-TechCon` … `User35-TechCon`.
- Each `User<nn>-TechCon` has, all pre-created before class:
  - an Entra UPN `User<nn>-TechCon@<tenant-domain>` (Reader on the subscription),
  - a GitHub account of the same name holding a fork of this repo,
  - a resource group named exactly `User<nn>-TechCon`.
- The deploy workflows default their target resource group to the **fork
  owner's name** and their resource prefix to its lowercased first segment
  (`User01-TechCon` → RG `User01-TechCon`, prefix `user01`).

**Isolation is naming, not permissions.** Because one Contributor identity is
shared by the whole class, nothing in Azure stops one student's pipeline from
writing over another's resources — the owner-derived resource group default is
the only thing keeping them apart. Do not hand-edit resource group names in
student forks.
