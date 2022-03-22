# Configure the Microsoft Azure Provider.
provider "azurerm" {
  features {}
}


# Azure Provider source and version being used.
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.91.0"
    }
  }
}


resource "azurerm_resource_group" "resource_group" {
  name     = "${var.project}rg"
  location = "East US"
}


data "archive_file" "test" {
  type        = "zip"
  source_dir  = "./HTTP_Trigger"
  output_path = var.output_path
}


resource "azurerm_storage_account" "storage_account" {
  name                     = "${var.project}st"
  resource_group_name      = azurerm_resource_group.resource_group.name
  location                 = azurerm_resource_group.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  allow_blob_public_access = true
}


resource "azurerm_storage_container" "storage_container" {
  name                  = "${var.project}stcont"
  storage_account_name  = azurerm_storage_account.storage_account.name
  container_access_type = "container"
}


resource "azurerm_storage_blob" "storage_blob" {
  name                   = filesha256(var.output_path)
  storage_account_name   = azurerm_storage_account.storage_account.name
  storage_container_name = azurerm_storage_container.storage_container.name
  type                   = "Block"
  source                 = var.output_path
}


data "azurerm_storage_account_blob_container_sas" "storage_account_blob_container_sas" {
  connection_string = azurerm_storage_account.storage_account.primary_connection_string
  container_name    = azurerm_storage_container.storage_container.name
  https_only        = true

  start  = "2022-01-01T00:00:00Z"
  expiry = "2022-12-31T00:00:00Z"

  permissions {
    read   = true
    add    = false
    create = false
    write  = false
    delete = false
    list   = false
  }
}


resource "azurerm_app_service_plan" "app_service_plan" {
  name                = "${var.project}-app-service-plan"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  kind                = "FunctionApp"
  reserved            = true # This has to be set to true for Linux. Not related to the Premium Plan
  sku {
    tier = "Dynamic"
    size = "Y1"
  }
}


resource "azurerm_function_app" "function_app" {
  name                = "${var.project}-function-app"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  app_service_plan_id = azurerm_app_service_plan.app_service_plan.id
  app_settings = {
    "WEBSITE_RUN_FROM_PACKAGE"       = "https://${azurerm_storage_account.storage_account.name}.blob.core.windows.net/${azurerm_storage_container.storage_container.name}/${azurerm_storage_blob.storage_blob.name}${data.azurerm_storage_account_blob_container_sas.storage_account_blob_container_sas.sas}",
    "FUNCTIONS_WORKER_RUNTIME"       = "python",
    "AzureWebJobsDisableHomepage"    = "false",
    "https_only"                     = "true",
    "APPINSIGHTS_INSTRUMENTATIONKEY" = "${azurerm_application_insights.app_insights.instrumentation_key}"
  }
  os_type = "linux"
  site_config {
    linux_fx_version          = "Python|3.9"
    use_32_bit_worker_process = false
  }
  storage_account_name       = azurerm_storage_account.storage_account.name
  storage_account_access_key = azurerm_storage_account.storage_account.primary_access_key
  version                    = "~3"
}


resource "azurerm_application_insights" "app_insights" {
  name                = "${var.project}app-insights"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  application_type    = "web"
}


resource "azurerm_api_management" "apim" {
  name                = "apim-${var.project}"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  publisher_name      = "apimpoc"
  publisher_email     = var.adminmail

  sku_name = "Developer_1"
}


# Our general API definition, here we could include a nice swagger file or something
resource "azurerm_api_management_api" "apim_api" {
  name                  = "httpexample-api"
  resource_group_name   = azurerm_resource_group.resource_group.name
  api_management_name   = azurerm_api_management.apim.name
  revision              = "1"
  display_name          = "Exampletf API"
  path                  = "example"
  protocols             = ["https"]
  subscription_required = "false"

  import {
    content_format = "openapi"
    content_value  = file("${path.module}/api-spec.yml")
  }

  depends_on = [
    azurerm_function_app.function_app
  ]
}


# A seperate backend definition, we need this to set our authorisation code for our azure function
resource "azurerm_api_management_backend" "apim_backend" {
  name                = "${var.project}apim_backend"
  resource_group_name = azurerm_resource_group.resource_group.name
  api_management_name = azurerm_api_management.apim.name
  protocol            = "http"
  url                 = "https://${azurerm_function_app.function_app.name}.azurewebsites.net/api/"
}


# We use a policy on our API to set the backend, which has the configuration for the authentication code
resource "azurerm_api_management_api_policy" "apim_policy" {
  api_name            = azurerm_api_management_api.apim_api.name
  resource_group_name = azurerm_resource_group.resource_group.name
  api_management_name = azurerm_api_management.apim.name

  # Put any policy block here, has to be XML :(
  # More options: https://docs.microsoft.com/en-us/azure/api-management/api-management-policies
  xml_content = <<XML
    <policies>
        <inbound>
            <base />
            <set-backend-service backend-id="${azurerm_api_management_backend.apim_backend.name}" />
        </inbound>
    </policies>
  XML
}


resource "azurerm_api_management_logger" "apim-logges" {
  name                = "${var.project}apim-logges"
  api_management_name = azurerm_api_management.apim.name
  resource_group_name = azurerm_resource_group.resource_group.name
  resource_id         = azurerm_application_insights.app_insights.id

  application_insights {
    instrumentation_key = azurerm_application_insights.app_insights.instrumentation_key
  }
}