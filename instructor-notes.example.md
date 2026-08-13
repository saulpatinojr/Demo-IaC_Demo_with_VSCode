# Instructor notes — workshop identifiers (PRIVATE when filled in)

Copy this file to `instructor-notes.md` and fill in the real values.
`instructor-notes.md` is gitignored: the identifiers live there and **nowhere
else in the repo** — never in workflow files, docs, or commit history.

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
through a federated credential whose subject is:

    repo:User<nn>-TechCon/Demo-IaC_Demo_with_VSCode:ref:refs/heads/main

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
