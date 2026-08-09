# Cleanup & Reset

Two different cleanups, and they are not interchangeable. One stops Azure charging you. The other takes the lab off your laptop.

> [!CAUTION]
> **Order matters.** Tear down Azure **first**, then clear credentials. Once you are signed out you can no longer delete anything — and Azure Firewall, Bastion, Front Door and SQL keep billing at roughly **$1.84/hr** with the full stack up.

| | What it removes | Script |
|---|---|---|
| **1 · Azure** | Everything the labs deployed, and optionally the OIDC identity | `Cleanup-Labs.ps1` |
| **2 · This machine** | `az` and `gh` sign-ins, saved settings, your passwords file | `Clear-LabCredentials.ps1` |

---

## 1. Tear down Azure

Preview first — it lists what would go and changes nothing:

```powershell
./scripts/Cleanup-Labs.ps1 -ResourceGroup $env:AZURE_RESOURCE_GROUP -WhatIf
./scripts/Cleanup-Labs.ps1 -ResourceGroup $env:AZURE_RESOURCE_GROUP
```

**You should see:** the resources deleted in three passes, then a report of anything that survived. It deletes the *contents* of the group and leaves the group itself — in a classroom you usually hold Contributor on the group and cannot recreate it.

Prefer the browser? **Actions → Teardown labs → Run workflow**, and type `DELETE` to confirm. It defaults to a dry run.

Also removing the Entra app registration this workshop created:

```powershell
./scripts/Cleanup-Labs.ps1 -Prefix "<yourname>" -RemoveOidc
```

> [!WARNING]
> **Do not delete only the Azure Firewall.** After L2, both spoke subnets route `0.0.0.0/0` at its private IP. Removing it alone black-holes every VM's outbound traffic while they keep billing. Tear down all of L2, route table included, or run the full teardown.

---

## 2. Clear this machine

Skip this on a classroom laptop that gets reimaged. **Do it if you ran the labs on your own machine.**

```powershell
./scripts/Clear-LabCredentials.ps1 -WhatIf   # preview
./scripts/Clear-LabCredentials.ps1
```

It checks for still-deployed resources before signing you out, and stops to ask if it finds any.

### What the labs put on your machine

| Left behind | Where | Removed by |
|---|---|---|
| Azure sign-in token | `~/.azure` token cache | `Clear-LabCredentials.ps1` |
| GitHub sign-in token | `gh` config (`hosts.yml`) | `Clear-LabCredentials.ps1` |
| Your prefix, region, resource group | User environment variables *(Windows)* | `Clear-LabCredentials.ps1`, or `Load-LabSettings.ps1 -Clear` |
| **VM and SQL passwords** | User environment variables *(Windows)*, and `lab-settings.csv` | Both of the above |
| GitHub Desktop / VS Code sign-in | Each app's own store | **You** — sign out in the app |

Only clearing the saved settings, staying signed in:

```powershell
./scripts/Load-LabSettings.ps1 -Clear
```

> [!IMPORTANT]
> **`-Persist` writes your lab passwords to disk in plain text.** On Windows they go to the registry under `HKCU\Environment` and stay until removed. That is a deliberate convenience for a throwaway lab, not a habit to carry to work — real credentials belong in a secret store, which is exactly what the OIDC path in these labs demonstrates.
>
> This workshop is **Windows 11 only**. On macOS or Linux `-Persist` does nothing at all — only Windows has a user environment store for it to write to — so there is nothing stored to clean up there either. The script says so rather than pretending. `lab-settings.csv` is the persistence in that case: re-run `./scripts/Load-LabSettings.ps1` per terminal.

---

## Useful commands

**Where am I signed in?**

```powershell
az account show --query "{subscription:name, user:user.name}" -o table
gh auth status
```

**What is still deployed, and what is it costing?**

```powershell
az resource list -g $env:AZURE_RESOURCE_GROUP --query "[].{name:name, type:type}" -o table
az resource list -g $env:AZURE_RESOURCE_GROUP --query "length(@)"
```

**Reload settings in a new terminal**

```powershell
./scripts/Load-LabSettings.ps1
```

**Why did a deployment fail?**

```powershell
$RG = $env:AZURE_RESOURCE_GROUP
az deployment group list -g $RG --query "[?properties.provisioningState=='Failed'].[name]" -o tsv
az deployment group show -g $RG --name <deployment-name> --query properties.error
```

**Start the whole workshop over** — teardown, then re-run setup:

```powershell
./scripts/Cleanup-Labs.ps1 -ResourceGroup $env:AZURE_RESOURCE_GROUP
./scripts/Setup-Oidc.ps1 -ResourceGroup $env:AZURE_RESOURCE_GROUP -Prefix "<yourname>"
```

---

## Related pages

- [Deployment Guide](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Deployment-Guide) — the one-time OIDC setup
- [Tools and References](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Tools-and-References) — every script, one line each
- [Troubleshooting](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Troubleshooting) — when a command does not do what this page says
- [Instructor Admin Tools](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/wiki/Instructor-Admin-Tools) — tearing down a whole class at once

<br>

---

> <img src="icon-spotlight.svg" width="16" align="top"> **GitHub feature spotlight · Manual approval as a safety interlock**
>
> **You just used it:** the *Teardown labs* workflow will not delete anything until you type `DELETE` into the input box. It is `workflow_dispatch` with a required input, and it defaults to a dry run.
> **Find it:** [`.github/workflows/teardown.yml`](https://github.com/saulpatinojr/Demo-IaC_Demo_with_VSCode/blob/main/.github/workflows/teardown.yml) — the `inputs.confirm` block and the step that checks it.
> **Beyond the lab:** the destructive button and the confirmation should never be the same click. A typed confirmation costs three seconds and is the cheapest guard you can put in front of an irreversible action.
> [Docs →](https://docs.github.com/actions/using-workflows/manually-running-a-workflow)
