
variable "name" {
  description = "(Required) Specifies the name of the resource. Changing this forces a new resource to be created."
  type        = string
}

variable "resource_group_name" {
  description = "(Required) The name of the resource group in which to create the resource. Changing this forces a new resource to be created."
  type        = string
}

variable "tags" {
  description = "(Optional) Specifies the tags of the log analytics workspace"
  type        = map(any)
  default     = {}
}

variable "location" {
  description = "(Required) Specifies the supported Azure location where the resource exists. Changing this forces a new resource to be created."
  type        = string
}

variable "workspace_id" {
  description = "(Optional) Specifies the id of a log analytics workspace resource. Changing this forces a new resource to be created."
  type        = string
}

variable "application_type" {
  description = "(Required) Type of Application Insights. 'web' for ASP.NET/Node/SSR apps; 'other' for anything non-HTTP. Valid: ios, java, MobileCenter, Node.JS, other, phone, store, web."
  type        = string
  default     = "web"
}
