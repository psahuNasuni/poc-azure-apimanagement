output "Function_App_Name" {
  value       = azurerm_function_app.function_app.name
  description = "Deployed function app name"
}

output "Function_App_Default_Hostname" {
  value       = azurerm_function_app.function_app.default_hostname
  description = "Deployed function app hostname"
}