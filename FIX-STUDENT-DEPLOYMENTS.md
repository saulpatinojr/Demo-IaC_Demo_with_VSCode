# Fix: let every student deploy (federated credential subject mismatch)

**Audience:** the workshop admin who owns the shared app registration.
**Time to fix:** about 10 minutes.
**One-line summary:** GitHub changed the ID string it presents during login,
so the app registration's federated credentials must be written in the new
format — one wildcard credential fixes all 35 students at once.

---

## 1. What we saw when we tested

We ran a test deployment through GitHub Actions using the shared workshop
identity (app registration `ec772fb1-230b-4d26-a980-4870f847e392`). GitHub
successfully built a login token and sent it to Microsoft Entra. Entra
**rejected it**:

```
AADSTS700213: No matching federated identity record found for presented
assertion subject 'repo:saulpatinojr@34853639/Demo-IaC_Demo_with_VSCode@1303622993:ref:refs/heads/...'
```

Look closely at the subject GitHub presented:

```
repo:saulpatinojr@34853639/Demo-IaC_Demo_with_VSCode@1303622993:ref:refs/heads/main
          ^^^^^^^^^                                ^^^^^^^^^^^
          account ID                               repository ID
```

GitHub now includes **numeric IDs** after the account name and the repository
name. A federated credential only matches if its subject is *character-for-
character identical* to what GitHub presents. Credentials written the old way:

```
repo:User35-TechCon/Demo-IaC_Demo_with_VSCode:ref:refs/heads/main   <-- old style, will NOT match
```

…never match the new string, so every login fails with `AADSTS700213`, for
every student, even though the app registration, its Contributor role, and the
GitHub secrets are all correct.

## 2. Why this is happening (confirmed by GitHub)

GitHub announced this change:
[Immutable subject claims for GitHub Actions OIDC tokens](https://github.blog/changelog/2026-04-23-immutable-subject-claims-for-github-actions-oidc-tokens/)

The key sentence: **every repository created after July 15, 2026 always uses
the new ID-enriched subject format.** There is no way to turn it off for new
repositories.

All 35 workshop forks (`User01-TechCon` … `User35-TechCon`) were created for
this event — after that date — so **every fork presents the new format**. Any
credential on the shared app that was written in the old name-only style will
fail for every student.

One more trap: an app registration allows **at most 20 classic federated
credentials**, and the class has 35 forks. So even "just recreate them in the
new format, one per student" cannot work with classic credentials. The fix
below avoids the cap entirely.

## 3. The fix — one credential that matches all 35 forks

Add a single **flexible federated credential** (Entra supports these for the
GitHub issuer) that pattern-matches every workshop fork. Do this once, on the
shared app registration:

**Portal steps**

1. Sign in to the Azure portal as the admin who owns the app registration.
2. Go to **Microsoft Entra ID → App registrations → search for app ID
   `ec772fb1-230b-4d26-a980-4870f847e392` → Certificates & secrets →
   Federated credentials → + Add credential**.
3. Choose the **GitHub Actions** scenario, then switch the subject entry to
   **flexible / claims matching expression** and enter:

   ```
   claims['sub'] matches 'repo:User*-TechCon@*/Demo-IaC_Demo_with_VSCode@*:ref:refs/heads/main'
   ```

4. Issuer must be `https://token.actions.githubusercontent.com` and audience
   `api://AzureADTokenExchange` (the defaults for the GitHub scenario).
5. Name it something like `workshop-all-forks` and save.

**Or the same thing with the Azure CLI**

```bash
cat > fic.json <<'JSON'
{
  "name": "workshop-all-forks",
  "issuer": "https://token.actions.githubusercontent.com",
  "audiences": ["api://AzureADTokenExchange"],
  "claimsMatchingExpression": {
    "value": "claims['sub'] matches 'repo:User*-TechCon@*/Demo-IaC_Demo_with_VSCode@*:ref:refs/heads/main'",
    "languageVersion": 1
  }
}
JSON

az ad app federated-credential create \
  --id ec772fb1-230b-4d26-a980-4870f847e392 \
  --parameters @fic.json
```

Notes:

- The `*` wildcards absorb the student number and the numeric IDs, so one
  credential covers `User01`–`User35` and any fork re-creation (new IDs still
  match). The pattern still pins the repo name and the `main` branch.
- **Leave any existing credentials in place** — extra credentials that never
  match are harmless. Delete old ones only if you hit the credential cap.
- If policy forbids flexible credentials, the fallback is one classic
  credential per fork with the exact IDs baked in — but the 20-credential cap
  means splitting students across two app registrations. Strongly prefer the
  flexible credential.

## 4. Prove it worked (2 minutes)

1. Sign in to GitHub as **`User35-TechCon`** (a testing account).
2. Open the fork `User35-TechCon/Demo-IaC_Demo_with_VSCode` → **Actions** →
   **"Curriculum L1.1 - Core Deployment"** → **Run workflow**.
3. Watch the run:
   - **"Azure login (OIDC)" turns green** → the fix worked. The rest of the
     run (lint → what-if → deploy into resource group `User35-TechCon`) proves
     the whole path end to end. Every other student fork works the same way.
   - **Login fails with `AADSTS700213`** → open the failed step's log and find
     the line `subject claim - repo:User35-TechCon@…`. That is the exact
     string Entra received. Compare it to the credential's pattern — fix the
     pattern until it matches, then re-run.

## 5. Reference: what a correct classic subject looks like

Only needed if you go per-fork instead of using the flexible credential.
For each student fork, the subject must be exactly:

```
repo:User<nn>-TechCon@<account-id>/Demo-IaC_Demo_with_VSCode@<repo-id>:ref:refs/heads/main
```

Get the two numbers per student (the failed-run log also prints the full
string ready to copy):

```bash
gh api users/User35-TechCon --jq .id                                  # account ID
gh api repos/User35-TechCon/Demo-IaC_Demo_with_VSCode --jq .id        # repository ID
```
