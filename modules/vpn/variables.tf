variable "name_prefix" { type = string }
variable "region" { type = string }
variable "vpc_id" { type = string }
variable "vpc_cidr" { type = string }
variable "private_subnet_ids" { type = list(string) }

variable "client_cidr" {
  description = "CIDR handed out to connected clients. Must not overlap the VPC CIDR."
  type        = string
}

variable "write_local_profile" {
  description = "Also write the rendered .ovpn profile to disk (<name_prefix>-vpn.ovpn) next to the root module."
  type        = bool
  default     = true
}
