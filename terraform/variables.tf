variable "domain_name" {
  description = "Domeinnaam voor het SSL certificaat"
  type        = string
}

variable "email" {
  description = "Email voor Let's Encrypt notificaties"
  type        = string
}
variable "project_id" {
  description = "id of the project I am working on"
  type = string
}