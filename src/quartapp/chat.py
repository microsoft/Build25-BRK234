import base64
import json
import os

import azure.identity.aio
import openai
from quart import (
    Blueprint,
    Response,
    current_app,
    render_template,
    request,
    stream_with_context,
)

bp = Blueprint("chat", __name__, template_folder="templates", static_folder="static")


@bp.before_app_serving
async def configure_openai():

    client_args = {}
    # Use an Azure OpenAI endpoint instead,
    # either with a key or with keyless authentication
    if os.getenv("AZURE_OPENAI_KEY_OVERRIDE"):
        # Authenticate using an Azure OpenAI API key
        # This is generally discouraged, but is provided for developers
        # that want to develop locally inside the Docker container.
        current_app.logger.info("Using Azure OpenAI with key")
        client_args["api_key"] = os.environ["AZURE_OPENAI_KEY_OVERRIDE"]
    else:
        if os.getenv("RUNNING_IN_PRODUCTION"):
            client_id = os.getenv("AZURE_CLIENT_ID")
            current_app.logger.info(
                "Using Azure OpenAI with managed identity credential for client ID: %s", client_id
            )
            azure_credential = azure.identity.aio.ManagedIdentityCredential(client_id=client_id)
        else:
            tenant_id = os.environ["AZURE_TENANT_ID"]
            current_app.logger.info(
                "Using Azure OpenAI with Azure Developer CLI credential for tenant ID: %s", tenant_id
            )
            azure_credential = azure.identity.aio.AzureDeveloperCliCredential(tenant_id=tenant_id)
        client_args["azure_ad_token_provider"] = azure.identity.aio.get_bearer_token_provider(
            azure_credential, "https://cognitiveservices.azure.com/.default"
        )
    bp.openai_client = openai.AsyncAzureOpenAI(
        azure_endpoint=os.environ["AZURE_OPENAI_ENDPOINT"],
        api_version="2024-10-21",
        **client_args,
    )


@bp.after_app_serving
async def shutdown_openai():
    await bp.openai_client.close()


def extract_login_info(headers) -> tuple[str, str]:
    """
    If the X-MS-CLIENT-PRINCIPAL header is present, decode it and
    extract the username from the claims.

    Returns a tuple of (is_authenticated, username).
    """
    default_username = "You"
    if "X-MS-CLIENT-PRINCIPAL" not in headers:
        return None, default_username

    token = json.loads(base64.b64decode(headers.get("X-MS-CLIENT-PRINCIPAL")))
    claims = {claim["typ"]: claim["val"] for claim in token["claims"]}
    return True, claims.get("name", default_username)


@bp.get("/")
async def index():
    is_authenticated, username = extract_login_info(request.headers)
    return await render_template("index.html", 
        is_authenticated=is_authenticated,
        username=username)


@bp.post("/chat/stream")
async def chat_handler():
    request_json = await request.get_json()
    request_messages = request_json["messages"]
    # get the base64 encoded image from the request
    image = request_json["context"]["file"]

    @stream_with_context
    async def response_stream():
        # This sends all messages, so API request may exceed token limits
        all_messages = [
            {"role": "system", "content": "You are a helpful assistant."},
        ] + request_messages[0:-1]
        all_messages = request_messages[0:-1]
        if image:
            user_content = []
            user_content.append({"text": request_messages[-1]["content"], "type": "text"})
            user_content.append({"image_url": {"url": image, "detail": "auto"}, "type": "image_url"})
            all_messages.append({"role": "user", "content": user_content})
        else:
            all_messages.append(request_messages[-1])

        chat_coroutine = bp.openai_client.chat.completions.create(
            # Azure Open AI takes the deployment name as the model name
            model=os.environ["AZURE_OPENAI_CHAT_DEPLOYMENT"],
            messages=all_messages,
            stream=True,
            temperature=request_json.get("temperature", 0.0),
        )
        try:
            async for event in await chat_coroutine:
                event_dict = event.model_dump()
                if event_dict["choices"]:
                    yield json.dumps(event_dict["choices"][0], ensure_ascii=False) + "\n"
        except Exception as e:
            current_app.logger.error(e)
            yield json.dumps({"error": str(e)}, ensure_ascii=False) + "\n"

    return Response(response_stream())
