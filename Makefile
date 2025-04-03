# Makefile for Azure FastAPI App Service Deployment

# Default configuration
ENV ?= dev
RESOURCE_GROUP ?= rg-fastapi-$(ENV)
LOCATION ?= westeurope
BASENAME ?= rcarmo-test
ACR_NAME ?= $(shell echo $(BASENAME)-acr-$(ENV) | tr -d '-')
IMAGE_NAME ?= fastapi-env-app
TAG ?= latest
IMAGE_FULL_NAME ?= $(ACR_NAME).azurecr.io/$(IMAGE_NAME):$(TAG)
FEATURE_FLAGS ?= ""
TENANT_ID ?= $(shell az account show --query tenantId -o tsv)

.PHONY: help init build push login-acr deploy-infra deploy-app deploy clean register-entra-app update-auth

help: ## Display this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

init: ## Create resource group and ensure proper subscription
	@echo "Creating resource group $(RESOURCE_GROUP) in $(LOCATION)..."
	az group create --name $(RESOURCE_GROUP) --location $(LOCATION)

build: ## Build the Docker container using Azure Container Registry remote build
	@echo "Uploading source code for remote build on ACR $(ACR_NAME)..."
	az acr build --registry $(ACR_NAME) --image $(IMAGE_FULL_NAME) .

login-acr: ## Log in to Azure Container Registry
	@echo "Logging in to ACR $(ACR_NAME)..."
	az acr login --name $(ACR_NAME)

push: login-acr ## Push the container to ACR
	@echo "Tagging and pushing image to $(ACR_NAME)..."
	docker tag $(IMAGE_NAME):$(TAG) $(IMAGE_FULL_NAME)
	docker push $(IMAGE_FULL_NAME)

deploy-infra: ## Deploy Azure resources with Bicep
	@echo "Deploying infrastructure for environment: $(ENV)..."
	@echo "Setting up environment-specific settings for $(ENV)"
	@LOG_LEVEL=""; \
	if [ "$(ENV)" = "dev" ]; then LOG_LEVEL="DEBUG"; \
	elif [ "$(ENV)" = "staging" ]; then LOG_LEVEL="INFO"; \
	else LOG_LEVEL="WARNING"; fi; \
	echo "Using LOG_LEVEL: $$LOG_LEVEL"; \
	\
	CLIENT_ID=""; \
	if [ -f .clientid ]; then CLIENT_ID=$$(cat .clientid); fi; \
	if [ ! -z "$$CLIENT_ID" ]; then \
		echo "Using Client ID: $$CLIENT_ID"; \
	else \
		echo "No Client ID found. You can run 'make register-entra-app' after deployment to enable authentication."; \
	fi; \
	\
	az deployment group create \
		--resource-group $(RESOURCE_GROUP) \
		--template-file ./infra/main.bicep \
		--parameters \
			environmentName='$(ENV)' \
			tenantId='$(TENANT_ID)' \
			clientId="$$CLIENT_ID" \
			featureFlags='$(FEATURE_FLAGS)' \
			logLevel="$$LOG_LEVEL"

deploy-app: ## Configure App Service to use the container
	@echo "Deploying application container for environment: $(ENV)..."
	$(eval APP_NAME := $(shell az webapp list --resource-group $(RESOURCE_GROUP) --query '[0].name' -o tsv))
	@echo "Using App Service: $(APP_NAME)"
		
	# Store ACR credentials in Key Vault
	#$(eval KEY_VAULT := $(shell az keyvault list --resource-group $(RESOURCE_GROUP) --query '[0].name' -o tsv))
	#$(eval ACR_PASSWORD := $(shell az acr credential show -n $(ACR_NAME) --query "passwords[0].value" -o tsv))
	#az keyvault secret set --vault-name $(KEY_VAULT) --name "acr-password" --value "$(ACR_PASSWORD)" --output none
		
	# Configure the app to use the container
	az webapp config container set \
		--resource-group $(RESOURCE_GROUP) \
		--name $(APP_NAME) \
		--container-image-name $(IMAGE_FULL_NAME) \
		--container-registry-url https://$(ACR_NAME).azurecr.io

	# Restart the app
	az webapp restart --resource-group $(RESOURCE_GROUP) --name $(APP_NAME)
	@echo "Application deployed to https://$(APP_NAME).azurewebsites.net"

deploy: build push deploy-infra deploy-app ## Full deployment process

deploy-dev: ## Deploy to development environment
	$(MAKE) deploy ENV=dev FEATURE_FLAGS="dev_mode,debug_api"

deploy-staging: ## Deploy to staging environment
	$(MAKE) deploy ENV=staging FEATURE_FLAGS="metrics,api_logging"

deploy-prod: ## Deploy to production environment
	$(MAKE) deploy ENV=prod

update-deps: ## Update dependencies in requirements.txt to latest versions
	@echo "Updating dependencies to latest versions..."
	@if ! command -v pip-tools &> /dev/null; then \
		echo "Installing pip-tools..."; \
		pip install pip-tools; \
	fi
	@echo "Creating backup of current requirements.txt..."
	cp src/requirements.txt src/requirements.txt.bak
	@echo "Generating updated requirements..."
	cd src && pip-compile --upgrade --generate-hashes --output-file=requirements.txt requirements.in || (echo "Failed to update. Make sure you have a requirements.in file or create one from requirements.txt"; exit 1)
	@echo "Dependencies updated. Previous version saved as requirements.txt.bak"
	@echo "Run 'make build' to rebuild the container with updated dependencies"

clean: ## Remove resource group and all resources
	@echo "WARNING: This will delete all resources in the resource group $(RESOURCE_GROUP)"
	@read -p "Are you sure you want to continue? (y/n) " answer; \
	if [ "$$answer" = "y" ]; then \
		echo "Deleting resource group $(RESOURCE_GROUP)..."; \
		az group delete --name $(RESOURCE_GROUP) --yes --no-wait; \
		echo "Deletion initiated. It may take a few minutes to complete."; \
	else \
		echo "Deletion cancelled."; \
	fi

register-entra-app: ## Register EntraID application for authentication
	@echo "Registering EntraID application for authentication..."
	@if ! az webapp list --resource-group $(RESOURCE_GROUP) --query '[0].name' -o tsv &>/dev/null; then \
		echo "No App Service found. Deploy infrastructure first with 'make deploy-infra'."; \
		exit 1; \
	fi; \
	APP_NAME=$$(az webapp list --resource-group $(RESOURCE_GROUP) --query '[0].name' -o tsv); \
	echo "App Service Name: $$APP_NAME"; \
	APP_URL="https://$$APP_NAME.azurewebsites.net"; \
	REDIRECT_URL="$$APP_URL/.auth/login/aad/callback"; \
	echo "App Service URL: $$APP_URL"; \
	echo "Redirect URL: $$REDIRECT_URL"; \
	\
	echo "Creating EntraID application registration..."; \
	APP_INFO=$$(az ad app create \
		--display-name "FastAPI-Env-App-Auth-$(ENV)" \
		--web-redirect-uris "$$REDIRECT_URL" \
		--sign-in-audience "AzureADMyOrg" \
		--query "{clientId:appId, objectId:id}" \
		-o json); \
	\
	CLIENT_ID=$$(echo "$$APP_INFO" | jq -r '.clientId'); \
	OBJECT_ID=$$(echo "$$APP_INFO" | jq -r '.objectId'); \
	\
	echo "Application registered successfully!"; \
	echo "Client ID: $$CLIENT_ID"; \
	echo "Object ID: $$OBJECT_ID"; \
	\
	echo "Creating service principal..."; \
	az ad sp create --id "$$CLIENT_ID"; \
	\
	echo "$$CLIENT_ID" > .clientid; \
	echo "Client ID saved to .clientid file"; \
	echo "Run 'make update-auth' to update the App Service with authentication settings"

update-auth: ## Update App Service with authentication settings
	@echo "Updating App Service with authentication settings..."
	@if ! [ -f .clientid ]; then \
		echo "No client ID found. Run 'make register-entra-app' first."; \
		exit 1; \
	fi; \
	CLIENT_ID=$$(cat .clientid); \
	APP_NAME=$$(az webapp list --resource-group $(RESOURCE_GROUP) --query '[0].name' -o tsv); \
	echo "Updating App Service $$APP_NAME with client ID $$CLIENT_ID"; \
	\
	az deployment group create \
		--resource-group $(RESOURCE_GROUP) \
		--template-file ./infra/main.bicep \
		--parameters \
			environmentName='$(ENV)' \
			tenantId='$(TENANT_ID)' \
			clientId="$$CLIENT_ID" \
			featureFlags='$(FEATURE_FLAGS)'

.DEFAULT_GOAL := help
