import os
import logging
from typing import Dict, List, Optional
from fastapi import FastAPI, Request, Depends
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates
from fastapi.staticfiles import StaticFiles
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.monitor.opentelemetry import configure_azure_monitor
import uvicorn

# pylint: disable=W1203,W0718

# Configure logging based on environment
log_level = os.environ.get("LOG_LEVEL", "INFO")
logging_level = getattr(logging, log_level)
logging.basicConfig(level=logging_level,
                   format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')

logger = logging.getLogger(__name__)
logger.info(f"Starting application with log level: {log_level}")

# Initialize FastAPI app
app = FastAPI(title="Environment Variables")

# Configure Azure Monitor
if "APPINSIGHTS_INSTRUMENTATIONKEY" in os.environ:
    try:
        configure_azure_monitor(
            connection_string=f"InstrumentationKey={os.environ['APPINSIGHTS_INSTRUMENTATIONKEY']}"
        )
        logger.info("Azure Monitor configured successfully")
    except Exception as e:
        logger.error(f"Failed to configure Azure Monitor: {e}")

# Setup templates
templates = Jinja2Templates(directory="templates")
os.makedirs("templates", exist_ok=True)

# Parse feature flags
def get_feature_flags() -> List[str]:
    """Parse feature flags from environment variables"""
    feature_flags = os.environ.get("FEATURE_FLAGS", "")
    if not feature_flags:
        return []
    return [flag.strip() for flag in feature_flags.split(",") if flag.strip()]

# Setup Key Vault client if available
key_vault_client = None
if os.environ.get("AZURE_KEY_VAULT_URI"):
    try:
        credential = DefaultAzureCredential()
        key_vault_client = SecretClient(
            vault_url=os.environ["AZURE_KEY_VAULT_URI"],
            credential=credential
        )
        logger.info("Key Vault client initialized successfully")
    except Exception as e:
        logger.error(f"Failed to initialize Key Vault client: {e}")

async def get_key_vault_secrets() -> Dict[str, str]:
    """Retrieve secrets from Key Vault"""
    if not key_vault_client:
        return {}
    try:
        secrets = {}
        secret_properties = key_vault_client.list_properties_of_secrets()
        for secret_property in secret_properties:
            secret_name = secret_property.name
            secret = key_vault_client.get_secret(secret_name)
            secrets[secret_name] = secret.value
        return secrets
    except Exception as e:
        logger.error(f"Failed to retrieve secrets from Key Vault: {e}")
        return {}

@app.get("/health", status_code=200)
async def health_check():
    """Health check endpoint"""
    logger.debug("Health check endpoint called")
    return {"status": "healthy"}

@app.get("/", response_class=HTMLResponse)
async def get_environment_variables(
    request: Request,
    feature_flags: List[str] = Depends(get_feature_flags),
    key_vault_secrets: Dict[str, str] = Depends(get_key_vault_secrets)
):
    """Display all environment variables in an HTML table"""
    logger.debug("Main endpoint called")

    env_vars = {k: v for k, v in os.environ.items()}

    # Add feature flags
    feature_flags_dict = {"PARSED_FEATURE_FLAGS": ", ".join(feature_flags)}

    # Add secrets (masked)
    secrets_dict = {"KV_" + k: "********" for k in key_vault_secrets.keys()}

    # Combine all variables
    all_vars = {**env_vars, **feature_flags_dict, **secrets_dict}

    # Sort for consistent display
    sorted_vars = dict(sorted(all_vars.items()))

    return templates.TemplateResponse(
        "index.html",
        {
            "request": request,
            "env_vars": sorted_vars,
            "feature_flags": feature_flags,
        }
    )

if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
