// This file is for doing static analysis and contains sensible defaults
// for PSRule to minimise false-positives and provide the best results.

// This file is not intended to be used as a runtime configuration file.

targetScope = 'subscription'

module main 'main.bicep' = {
  name: 'main'
  params: {
    name: 'ragpostgres'
    location: 'swedencentral'
    acaExists: false
    openAiResourceLocation: 'eastus'
  }
}
