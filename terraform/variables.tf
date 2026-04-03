variable "domain_name" {
  description = "Domeinnaam voor het SSL certificaat"
  default = "luprointunemigrationtool.cloud"
  type        = string
}

variable "email" {
  description = "Email voor Let's Encrypt notificaties"
  default = "lucas.profeta@xylos.com"
  type        = string
}