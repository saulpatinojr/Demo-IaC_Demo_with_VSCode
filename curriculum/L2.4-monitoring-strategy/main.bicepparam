using 'main.bicep'

param prefix = readEnvironmentVariable('AZURE_PREFIX', 'iacdemo')
param alertEmail = readEnvironmentVariable('ALERT_EMAIL', 'you@example.com')

// Off unless you hold Resource Policy Contributor or Owner. Plain Contributor
// -- what this lab grants, and what the OIDC identity has -- cannot create a
// policy assignment, and turning this on without the rights fails the deploy.
param assignAuditPolicy = toLower(readEnvironmentVariable('CURRICULUM_ASSIGN_POLICY', 'false')) == 'true'

// The saving. Set false to leave every table on the Analytics plan and watch
// the difference in the Usage table over the following day.
param useBasicPlanForFirewallLogs = toLower(readEnvironmentVariable('CURRICULUM_BASIC_PLAN', 'true')) == 'true'

// About one month of the full L1-L2 stack at ~$1.93/hr, rounded up. Lower it
// to your real classroom allowance -- a budget set above what you would ever
// spend never fires, which is the same as not having one.
param monthlyBudgetUsd = int(readEnvironmentVariable('CURRICULUM_MONTHLY_BUDGET', '1450'))
