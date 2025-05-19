#!/bin/bash

# Define the .env file path
ENV_FILE_PATH=".env"

# Clear the contents of the .env file
> $ENV_FILE_PATH

echo "AZURE_OPENAI_CHAT_DEPLOYMENT=$(azd env get-value AZURE_OPENAI_CHAT_DEPLOYMENT)" >> $ENV_FILE_PATH
echo "AZURE_OPENAI_ENDPOINT=$(azd env get-value AZURE_OPENAI_ENDPOINT)" >> $ENV_FILE_PATH
echo "AZURE_TENANT_ID=$(azd env get-value AZURE_TENANT_ID)" >> $ENV_FILE_PATH

# Get USE_KEYLESS_AUTH value from azd environment
USE_KEYLESS_AUTH=$(azd env get-value USE_KEYLESS_AUTH)
# Default to true if not set or empty
if [ -z "$USE_KEYLESS_AUTH" ] || [ "$USE_KEYLESS_AUTH" != "false" ]; then
    USE_KEYLESS_AUTH="true"
    # Log this default for transparency
    echo "USE_KEYLESS_AUTH not set or not 'false', defaulting to 'true' for keyless auth."
fi

# If keyless auth is not used, get the OpenAI key and store it in .env
if [ "$USE_KEYLESS_AUTH" = "false" ]; then
    # Get Azure OpenAI resource name and resource group from azd environment
    AZURE_OPENAI_RESOURCE=$(azd env get-value AZURE_OPENAI_RESOURCE)
    AZURE_RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP)
    
    if [ -n "$AZURE_OPENAI_RESOURCE" ] && [ -n "$AZURE_RESOURCE_GROUP" ]; then
        echo "Keyless auth is disabled. Retrieving OpenAI key..."
        # Check if user is logged in to Azure CLI
        az account show > /dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo "Error: Not logged in to Azure CLI. Please run 'az login' first."
            exit 1
        fi
        
        # Get OpenAI key using Azure CLI
        OPENAI_KEY=$(az cognitiveservices account keys list \
            --name "$AZURE_OPENAI_RESOURCE" \
            --resource-group "$AZURE_RESOURCE_GROUP" \
            --query "key1" -o tsv 2>/dev/null)
        
        if [ $? -eq 0 ] && [ -n "$OPENAI_KEY" ]; then
            echo "AZURE_OPENAI_KEY_OVERRIDE=$OPENAI_KEY" >> $ENV_FILE_PATH
            echo "OpenAI key retrieved and saved to .env"
        else
            echo "Error: Failed to retrieve OpenAI key. Please check your resource name, resource group, and permissions."
        fi
    else
        echo "Warning: AZURE_OPENAI_RESOURCE or AZURE_RESOURCE_GROUP not set in azd environment."
    fi
else
    echo "Using keyless authentication for Azure OpenAI."
fi
