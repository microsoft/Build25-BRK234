# Define the .env file path
$envFilePath = ".env"

# Clear the contents of the .env file
Set-Content -Path $envFilePath -Value ""

# Append new values to the .env file
$azureOpenAiEndpoint = azd env get-value AZURE_OPENAI_ENDPOINT
$azureOpenAiDeployment = azd env get-value AZURE_OPENAI_CHAT_DEPLOYMENT
$azureOpenAiApiVersion = azd env get-value AZURE_OPENAI_API_VERSION
$azureTenantId = azd env get-value AZURE_TENANT_ID

Add-Content -Path $envFilePath -Value "AZURE_OPENAI_CHAT_DEPLOYMENT=$azureOpenAiCDeployment"
Add-Content -Path $envFilePath -Value "AZURE_OPENAI_ENDPOINT=$azureOpenAiEndpoint"
Add-Content -Path $envFilePath -Value "AZURE_TENANT_ID=$azureTenantId"
# Get USE_KEYLESS_AUTH value from azd environment
$useKeylessAuth = azd env get-value USE_KEYLESS_AUTH
# Default to true if not set or not specifically 'false'
if ([string]::IsNullOrEmpty($useKeylessAuth) -or $useKeylessAuth -ne "false") {
    $useKeylessAuth = "true"
    # Log this default for transparency
    Write-Host "USE_KEYLESS_AUTH not set or not 'false', defaulting to 'true' for keyless auth."
}

# If keyless auth is not used, get the OpenAI key and store it in .env
if ($useKeylessAuth -eq "false") {
    # Get Azure OpenAI resource name and resource group from azd environment
    $azureOpenAiResource = azd env get-value AZURE_OPENAI_RESOURCE
    $azureResourceGroup = azd env get-value AZURE_RESOURCE_GROUP
    
    if (![string]::IsNullOrEmpty($azureOpenAiResource) -and ![string]::IsNullOrEmpty($azureOpenAiResourceGroup)) {
        Write-Host "Keyless auth is disabled. Retrieving OpenAI key..."
        # Check if user is logged in to Azure CLI
        try {
            $null = az account show
        } catch {
            Write-Error "Not logged in to Azure CLI. Please run 'az login' first."
            exit 1
        }
        
        # Get OpenAI key using Azure CLI
        try {
            $openAiKey = az cognitiveservices account keys list `
                --name "$azureOpenAiResource" `
                --resource-group "$azureResourceGroup" `
                --query "key1" -o tsv
            
            if (![string]::IsNullOrEmpty($openAiKey)) {
                Add-Content -Path $envFilePath -Value "AZURE_OPENAI_KEY_OVERRIDE=$openAiKey"
                Write-Host "OpenAI key retrieved and saved to .env"
            } else {
                Write-Error "Failed to retrieve OpenAI key. Empty key returned."
            }
        } catch {
            Write-Error "Failed to retrieve OpenAI key. Please check your resource name, resource group, and permissions."
        }
    } else {
        Write-Warning "AZURE_OPENAI_RESOURCE or AZURE_RESOURCE_GROUP not set in azd environment."
    }
} else {
    Write-Host "Using keyless authentication for Azure OpenAI."
}
