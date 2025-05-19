USE_VNET=$(azd env get-value USE_VNET)
if [ "$USE_VNET" != "true" ]; then
    exit 0
fi

AZURE_VPN_CONFIG_DOWNLOAD_LINK=$(azd env get-value AZURE_VPN_CONFIG_DOWNLOAD_LINK)

echo "To use the VPN to access private endpoints, download the VPN configuration file from the following link: $AZURE_VPN_CONFIG_DOWNLOAD_LINK"
echo "Then modify the azurevpnconfig.xml file per the README instructions to point at the Private DNS resolver."