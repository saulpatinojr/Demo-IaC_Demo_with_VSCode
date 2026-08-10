// ============================================================================
// Lab policy guardrails for ONE resource group.
//
// Deployed per matching resource group by lab-policy.bicep -- do not deploy
// this file directly. Six assignments per group: allowed locations, allowed
// resource types, and tag inheritance for Owner / Event / Date / Instructor.
//
// ARM PUTs are idempotent: re-running converges an existing assignment to
// this definition instead of skipping it, so an edited parameter actually
// lands on re-run.
// ============================================================================
param allowedLocations array
param allowedResourceTypes array
param tagsToInherit array

// Built-in policy definitions, referenced by their well-known GUIDs.
var defAllowedLocations = tenantResourceId('Microsoft.Authorization/policyDefinitions', 'e56962a6-4747-49cd-b67b-bf8b01975c4f')
var defAllowedResourceTypes = tenantResourceId('Microsoft.Authorization/policyDefinitions', 'a08ec900-254a-4555-9bf5-e42af04b5c5c')
var defInheritTag = tenantResourceId('Microsoft.Authorization/policyDefinitions', 'ea3f2387-9b95-492a-a190-fcdc54f7b070')

var rgName = resourceGroup().name
// Assignment names cap at 64 characters; the tag assignments drop the common
// prefix the same way the original script did.
var shortRg = replace(rgName, 'rg-techdemo-', '')

resource locationAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: take('lab-loc-${rgName}', 64)
  properties: {
    displayName: 'Lab: Allowed locations (${rgName})'
    policyDefinitionId: defAllowedLocations
    parameters: {
      listOfAllowedLocations: { value: allowedLocations }
    }
  }
}

resource resourceTypeAssignment 'Microsoft.Authorization/policyAssignments@2024-04-01' = {
  name: take('lab-rtype-${rgName}', 64)
  properties: {
    displayName: 'Lab: Allowed resource types (${rgName})'
    policyDefinitionId: defAllowedResourceTypes
    parameters: {
      listOfResourceTypesAllowed: { value: allowedResourceTypes }
    }
  }
}

resource tagAssignments 'Microsoft.Authorization/policyAssignments@2024-04-01' = [for tag in tagsToInherit: {
  name: take('lab-tag-${tag}-${shortRg}', 64)
  properties: {
    displayName: 'Lab: Inherit ${tag} tag (${rgName})'
    policyDefinitionId: defInheritTag
    parameters: {
      tagName: { value: tag }
    }
  }
}]

output assignmentCount int = 2 + length(tagsToInherit)
