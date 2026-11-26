variable "environment" {
  description = "Nom de l'environnement : dev ou prod"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment doit valoir dev ou prod."
  }
}

variable "instance_type" {
  description = "Taille des instances web"
  type        = string
  default     = "t3.micro"
}
