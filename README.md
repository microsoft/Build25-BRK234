
<p align="center">
<img src="img/banner.jpg" alt="decorative banner" width="1200"/>
</p>

# Build25 BRK234 - Deploying an end-to-end secure AI application

## Description

Security can be challenging at the best of times, especially when it’s not your full-time job. In this session, we walk you through the end-to-end deployment of a secure AI application, all the way from identities, VNETS, NSGs, key vault through to prompt shields and data labelling. If you’ve ever felt overwhelmed by trying to do the right thing by security but didn’t know where to start, this session is for you!

## Content Owners

* [Sarah Young](https://build.microsoft.com/speakers/b50342f4-8026-49ec-9a35-a121d157a8dd?source=/speakers/d5b5eb86-ed40-4047-88a7-4e5232734a70)
* [Pamela Fox](https://build.microsoft.com/speakers/d5b5eb86-ed40-4047-88a7-4e5232734a70?source=/speakers/d5b5eb86-ed40-4047-88a7-4e5232734a70)

## Session Resources 

| Resources          | Links                             | Description        |
|:-------------------|:----------------------------------|:-------------------|
| Build session page | https://build.microsoft.com/sessions/BRK234 | Event session page with downloadable recording, slides, resources, and speaker bio |
| Session recording on YouTube | https://aka.ms/build2025/video/BRK234 | YouTube page with session recording and speaker-moderated chat |

## Code sample

This project includes a simple chat app (Python/JS) that uses Azure OpenAI to generate responses, along with the infrastructure to deploy it to Azure (Bicep). The infrastructure always deploys the app to [Azure Container Apps](https://learn.microsoft.com/azure/container-apps/overview) but it can be configured with different security levels, including a virtual network, Azure Front Door, and Azure VPN. All of this is deployed to Azure using the [Azure Developer CLI](https://learn.microsoft.com/azure/developer/azure-developer-cli/overview).

* [Getting started](#getting-started)
* [Deploying](#deploying)
* [Development server](#development-server)
* [Costs](#costs)
* [Related code samples and documentation](#related-code-samples-and-documentation)

### Getting started

You have a few options for getting started with this template.
The quickest way to get started is GitHub Codespaces, since it will setup all the tools for you, but you can also [set it up locally](#local-environment).

#### GitHub Codespaces

You can run this template virtually by using GitHub Codespaces. The button will open a web-based VS Code instance in your browser:

1. Open the template (this may take several minutes):

    [![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/Azure-Samples/secure-ai-app-build-demo)

2. Open a terminal window
3. Continue with the [deploying steps](#deploying)

#### VS Code Dev Containers

A related option is VS Code Dev Containers, which will open the project in your local VS Code using the [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers):

1. Start Docker Desktop (install it if not already installed)
2. Open the project:

    [![Open in Dev Containers](https://img.shields.io/static/v1?style=for-the-badge&label=Dev%20Containers&message=Open&color=blue&logo=visualstudiocode)](https://vscode.dev/redirect?url=vscode://ms-vscode-remote.remote-containers/cloneInVolume?url=https://github.com/azure-samples/secure-ai-app-build-demo)

3. In the VS Code window that opens, once the project files show up (this may take several minutes), open a terminal window.
4. Continue with the [deploying steps](#deploying)

#### Local environment

If you're not using one of the above options for opening the project, then you'll need to:

1. Make sure the following tools are installed:

    * [Azure Developer CLI (azd)](https://aka.ms/install-azd)
    * [Python 3.10+](https://www.python.org/downloads/)
    * [Docker Desktop](https://www.docker.com/products/docker-desktop/)
    * [Git](https://git-scm.com/downloads)

2. Download the project code by cloning the repository.
3. Open the project folder
4. Create a [Python virtual environment](https://docs.python.org/3/tutorial/venv.html#creating-virtual-environments) and activate it.
5. Install required Python packages:

    ```shell
    pip install -r requirements-dev.txt
    ```

6. Install the app in editable mode:

    ```shell
    python -m pip install -e src
    ```

7. Continue with the [deploying steps](#deploying).

### Deploying

Once you've opened the project in [Codespaces](#github-codespaces), in [Dev Containers](#vs-code-dev-containers), or [locally](#local-environment), you can deploy it to Azure.

#### Azure account setup

1. Sign up for a [free Azure account](https://azure.microsoft.com/free/) and create an Azure Subscription.
2. Check that you have the necessary permissions:
    * Your Azure account must have `Microsoft.Authorization/roleAssignments/write` permissions, such as [Role Based Access Control Administrator](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#role-based-access-control-administrator-preview), [User Access Administrator](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#user-access-administrator), or [Owner](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#owner). If you don't have subscription-level permissions, you must be granted [RBAC](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#role-based-access-control-administrator-preview) for an existing resource group and [deploy to that existing group](/docs/deploy_existing.md#resource-group).
    * Your Azure account also needs `Microsoft.Resources/deployments/write` permissions on the subscription level.

#### Deploying with azd

1. Login to Azure:

    ```shell
    azd auth login
    ```

2. Create a new azd environment:

    ```shell
    azd env new
    ```

    This will create a new folder inside `.azure` with the name of your environment, and will store the azd configuration files there.

3. Set the azd environment variables to match the desired security configuration.

    Use a stricter Responsible AI policy for Azure OpenAI than the default filter:

    ```bash
    azd env set USE_STRICT_RAI_POLICY true
    ```

    Configure monitoring for Azure OpenAI:

    ```bash
    azd env set USE_MONITORING true
    ```

    Use keyless authentication for Azure OpenAI:

    ```bash
    azd env set USE_KEYLESS_AUTH true
    ```

    Use a virtual network for the app:

    ```bash
    azd env set USE_VNET true
    ```

    Disable public ingress for the app. This must be combined with VNet option:

    ```bash
    azd env set USE_PUBLIC_INGRESS false
    ```

    Add Azure Front Door to the app (along with Web Application Firewall). This must be combined with VNet option:

    ```bash
    azd env set USE_FRONT_DOOR true
    ```

4. If you are *not* using a VNet, then you can use `up` command to provision and deploy all the resources in the same command:

    ```shell
    azd env new
    ```

5. If you are using a VNet, you will need to first provision the environment with the virtual network configured:

    ```bash
    azd provision
    ```

6. Once provisioning is complete, you'll see a mesage with a link to download the VPN configuration file. Download the VPN configuration files from the Azure portal. Open `azurevpnconfig.xml`, and replace the `<clientconfig>` empty tag with the following:

    ```xml
      <clientconfig>
        <dnsservers>
          <dnsserver>10.0.11.4</dnsserver>
        </dnsservers>
      </clientconfig>
    ```

5. Open the "Azure VPN" client and select "Import" button. Select the `azurevpnconfig.xml` file you just downloaded and modified.

6. Select "Connect" and the new VPN connection. You will be prompted to select your Microsoft account and login.

7. Once you're successfully connected to VPN, you can proceed to deploy the application:

    ```bash
    azd deploy
    ```

### Development server

In order to run this app locally, you first need to deploy it to Azure following the steps above. 

1. When you ran `azd up`, a `.env` file should have been automatically created with the necessary environment variables.

2. Start the development server:

    ```shell
    python -m quart --app src.quartapp run --port 50505 --reload
    ```

    This will start the app on port 50505, and you can access it at `http://localhost:50505`.

### Costs

Pricing varies per region and usage, so it isn't possible to predict exact costs for your usage.
It also depends on whether you choose to enable the optional features (like Azure Front Door, VPN, etc.) and how much you use them.

You can try the [Azure pricing calculator](https://azure.com/e/3987c81282c84410b491d28094030c9a) for the resources:

* Azure OpenAI Service: S0 tier, GPT-4o model. Pricing is based on token count. [Pricing](https://azure.microsoft.com/pricing/details/cognitive-services/openai-service/)
* Azure Container App: Consumption tier with 0.5 CPU, 1GiB memory/storage. Pricing is based on resource allocation, and each month allows for a certain amount of free usage. [Pricing](https://azure.microsoft.com/pricing/details/container-apps/)
* Azure Container Registry: Basic tier. [Pricing](https://azure.microsoft.com/pricing/details/container-registry/)
* Log analytics: Pay-as-you-go tier. Costs based on data ingested. [Pricing](https://azure.microsoft.com/pricing/details/monitor/)
* TODO: More services

⚠️ To avoid unnecessary costs, remember to take down your app if it's no longer in use,
either by deleting the resource group in the Portal or running `azd down`.

### Related code samples and documentation

* [OpenAI Chat Application Quickstart](https://github.com/Azure-Samples/openai-chat-app-quickstart): Similar to this project, but without the virtual network. It deploys a publicly availeble endpoint.
* [OpenAI Chat Application with Microsoft Entra Authentication - MSAL SDK](https://github.com/Azure-Samples/openai-chat-app-entra-auth-local): Similar to this project, but adds user authentication with Microsoft Entra using the Microsoft Graph SDK and built-in authentication feature of Azure Container Apps.
* [OpenAI Chat Application with Microsoft Entra Authentication - Built-in Auth](https://github.com/Azure-Samples/openai-chat-app-entra-auth-local): Similar to this project, but adds user authentication with Microsoft Entra using the Microsoft Graph SDK and MSAL SDK.
* [RAG chat with Azure AI Search + Python](https://github.com/Azure-Samples/azure-search-openai-demo/): A more advanced chat app that uses Azure AI Search to ground responses in domain knowledge. Includes optional user authentication and virtual network.
* [Develop Python apps that use Azure AI services](https://learn.microsoft.com/azure/developer/python/azure-ai-for-python-developers)

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow Microsoft’s Trademark & Brand Guidelines. Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship. Any use of third-party trademarks or logos are subject to those third-party’s policies.
