USE_FRONT_DOOR=$(azd env get-value USE_FRONT_DOOR)
if [ "$USE_FRONT_DOOR" != "true" ]; then
    exit 0
fi

AZURE_CONTAINER_ENVIRONMENT_NAME=$(azd env get-value AZURE_CONTAINER_ENVIRONMENT_NAME)
AZURE_RESOURCE_GROUP=$(azd env get-value AZURE_RESOURCE_GROUP)

echo "Approving private endpoint connection for Front Door..."

ENDPOINT_ID=$(az network private-endpoint-connection list \
    --name $AZURE_CONTAINER_ENVIRONMENT_NAME \
    --resource-group $AZURE_RESOURCE_GROUP \
    --type Microsoft.App/managedEnvironments \
    --query "[0].id" -o tsv 2>/dev/null)

if [ -z "$ENDPOINT_ID" ]; then
    echo "Failed to find private endpoint connection."
    exit 1
fi

echo "Found private endpoint connection with ID: $ENDPOINT_ID"

# Approve the private endpoint connection using the extracted ID
if az network private-endpoint-connection approve --id "$ENDPOINT_ID" >/dev/null 2>&1; then
    echo "Private endpoint connection approved successfully."
else
    echo "Failed to approve private endpoint connection."
    exit 1
fi