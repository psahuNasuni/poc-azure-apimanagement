variable "project" {
  type        = string
  description = "Project name"
  default     = "httpazuretf"
}

variable "adminmail" {
  type        = string
  description = "Admin Email id"
  default     = "abedare@nasuni.com"
}

variable "output_path" {
  type        = string
  description = "function_path of filw where zip file is stored"
  default     = "./HTTPExampleFunction.zip"
}