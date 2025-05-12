param name string

param openAiResourceName string

resource openAi 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: openAiResourceName
}

// RAI Policy resource if a policy name is provided
resource raiPolicy 'Microsoft.CognitiveServices/accounts/raiPolicies@2024-10-01' = {
  parent: openAi
  name: name
  properties: {
    mode: 'Blocking'
    basePolicyName: 'Microsoft.DefaultV2'
    contentFilters: [
      // Indirect attacks
      {
        blocking: true
        enabled: true
        name: 'indirect_attack'
        severityThreshold: 'Low'
        source: 'Prompt'
      }
      // Jailbreak
      {
        blocking: true
        enabled: true
        name: 'jailbreak'
        severityThreshold: 'Low'
        source: 'Prompt'
      }
      // Prompt
      {
        blocking: true
        enabled: true
        name: 'hate'
        severityThreshold: 'Low'
        source: 'Prompt'
      }
      {
        blocking: true
        enabled: true
        name: 'sexual'
        severityThreshold: 'Low'
        source: 'Prompt'
      }
      {
        blocking: true
        enabled: true
        name: 'selfharm'
        severityThreshold: 'Low'
        source: 'Prompt'
      }
      {
        blocking: true
        enabled: true
        name: 'violence'
        severityThreshold: 'Low'
        source: 'Prompt'
      }
      {
        blocking: true
        enabled: true
        name: 'profanity'
        severityThreshold: 'Low'
        source: 'Prompt'
      }
      // Completion
      {
        blocking: true
        enabled: true
        name: 'hate'
        severityThreshold: 'Low'
        source: 'Completion'
      }
      {
        blocking: true
        enabled: true
        name: 'sexual'
        severityThreshold: 'Low'
        source: 'Completion'
      }
      {
        blocking: true
        enabled: true
        name: 'selfharm'
        severityThreshold: 'Low'
        source: 'Completion'
      }
      {
        blocking: true
        enabled: true
        name: 'violence'
        severityThreshold: 'Low'
        source: 'Completion'
      }
      {
        blocking: true
        enabled: true
        name: 'profanity'
        severityThreshold: 'Low'
        source: 'Completion'
      }
    ]
  }
}
