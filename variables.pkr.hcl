variable "proxmox_url" {
  type = string
  default = "https://192.168.1.100:8006/api2/json"
}

variable "proxmox_username" {
  type = string
}

variable "proxmox_token" {
  type      = string
  sensitive = true
  default = env("PROXMOX_TOKEN")
}

variable "proxmox_node" {
  type    = string
  default = "pve"
}

# --- SSH Key Config ---
variable "ssh_public_key" {
  type    = string
  default = env("PACKER_SSH_PUBLIC_KEY")
}

variable "ssh_private_key_file" {
  type    = string
  default = env("PACKER_SSH_PRIVATE_KEY")
}

# --- Network Config ---
variable "internet_bridge" {
  type        = string
}

# --- Storage Config ---
variable "iso_storage" {
  description = "Storage pool for ISO images and templates"
  type        = string
}

variable "vm_storage_pool" {
  description = "Storage pool for VM disks"
  type        = string
}