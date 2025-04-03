# Azure FastAPI App Service Sample

> **Note:** This is currently a work in progress. The project is being developed to demonstrate the deployment of a FastAPI application on Azure App Service with various features and configurations, and is not yet complete nor fully deployable.

A Python FastAPI application that displays environment variables in an HTML table format, deployed as a Linux container on Azure App Service. The application is secured with Azure Entra ID authentication and integrates with Azure Monitor for logging.

## Project Overview

This application provides a simple web interface to view all environment variables available to the running container. It includes:

- HTML table display of all environment variables
- Parsing of `FEATURE_FLAGS` environment variable as a comma-delimited list
- Health check endpoint
- Environment-specific logging configuration
- Azure Key Vault integration using Managed Identity
- Azure Monitor integration for logging and monitoring

## Local Development Setup

### Prerequisites

- Docker and Docker Compose
- Python 3.x (for local development outside of Docker)
- Azure CLI (for deployment)

### Running Locally

1. Clone this repository:

   ```bash
   git clone <repository-url>
   cd azure-fastapi-app-service
   ```

2. Create a `.env` file for local environment variables:

   ```bash
   echo "FEATURE_FLAGS=local_dev,debug" > .env
   ```

3. Run the application using Docker Compose:

   ```bash
   docker-compose up
   ```

4. Access the application:
   - Development environment: http://localhost:8000
   - Staging environment: http://localhost:8001
   - Production environment: http://localhost:8002

## Deployment

### Prerequisites

- Azure subscription
- Azure CLI installed and logged in
- Docker installed

### Deployment Steps

1. Initialize the infrastructure:

   ```bash
   make init
   ```

2. Deploy to the desired environment:

   ```bash
   # For development
   make deploy-dev
   
   # For staging
   make deploy-staging
   
   # For production
   make deploy-prod
   ```

3. To deploy with custom feature flags:

   ```bash
   make deploy ENV=<environment> FEATURE_FLAGS="flag1,flag2,flag3"
   ```

4. To update dependencies to latest versions:

   ```bash
   make update-deps
   ```

5. To clean up resources:

   ```bash
   make clean
   ```

## Project Structure

```plaintext
/
├── src/               # Application source code
│   ├── main.py        # FastAPI application
│   ├── requirements.txt # Python dependencies
│   └── templates/     # HTML templates
├── infra/             # Bicep templates
│   ├── main.bicep     # Main infrastructure template
│   └── modules/       # Modularized Bicep components
├── Dockerfile         # Container definition
├── docker-compose.yml # Local development setup
├── Makefile           # Deployment automation
├── README.md          # This file
└── spec.md            # Technical specification
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `FEATURE_FLAGS` | Comma-delimited list of feature flags | "" |
| `LOG_LEVEL` | Logging level (DEBUG, INFO, WARNING) | Based on environment |
| `AZURE_KEY_VAULT_URI` | URI of Azure Key Vault | Set by App Service |
| `APPINSIGHTS_INSTRUMENTATIONKEY` | Azure Application Insights key | Set by App Service |

### Environment-specific Settings

- **Development**: DEBUG logging, feature flags: "dev_mode,debug_api"
- **Staging**: INFO logging, feature flags: "metrics,api_logging"
- **Production**: WARNING logging, no default feature flags

## Authentication

Authentication is handled by Azure App Service using Entra ID. The Bicep templates configure the App Service to require authentication with specific tenant ID and user role settings.

## Key Vault Integration

The application uses the Managed Identity assigned to the App Service to access secrets in Key Vault. No credentials are stored in the application code or configuration.

## Makefile Commands

- `make help` - Display available commands
- `make init` - Create resource group and ACR
- `make build` - Build Docker container
- `make push` - Push container to ACR
- `make deploy-infra` - Deploy Azure resources with Bicep
- `make deploy-app` - Configure App Service to use the container
- `make deploy` - Full deployment process
- `make deploy-dev` - Deploy to development environment
- `make deploy-staging` - Deploy to staging environment
- `make deploy-prod` - Deploy to production environment
- `make update-deps` - Update dependencies in requirements.txt
- `make clean` - Remove resource group and all resources