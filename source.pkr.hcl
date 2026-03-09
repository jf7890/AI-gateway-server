source "proxmox-iso" "alpine" {
  # Proxmox Auth
  proxmox_url               = var.proxmox_url
  username                  = var.proxmox_username
  token                     = var.proxmox_token
  node                      = var.proxmox_node
  insecure_skip_tls_verify  = true
  
  # ISO
  boot_iso {
    type             = "scsi"
    iso_url          = "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/x86_64/alpine-virt-3.23.2-x86_64.iso"
    iso_checksum     = "file:https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/x86_64/alpine-virt-3.23.2-x86_64.iso.sha256"
    iso_storage_pool = var.iso_storage
    iso_download_pve = true
    unmount          = true
  }

  # VM Specs
  vm_name         = "ai-gateway-server"
  template_name   = "ai-gateway-server"
  memory          = 2048
  sockets         = 1
  cores           = 2
  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true

  template_description = "AI Gateway Server (Alpine)"
  tags                 = "alpine;ai-gateway"

  
  # Network: single NIC (eth0)
  network_adapters {
    model    = "virtio"
    bridge   = var.internet_bridge
    firewall = false
  }

  disks {
    type         = "scsi"
    disk_size    = "10G"
    storage_pool = var.vm_storage_pool
    format       = "raw"
  }

  # --- HTTP Server: Serve Answer File Dynamic ---
  http_content = {
    "/answers" = templatefile("http/answers.pkrtpl.hcl", {
      ssh_public_key = var.ssh_public_key
    })
  }

  # Boot Command
  boot_wait = "10s"
  boot_command = [
    "<enter><wait>",
    "root<enter><wait>",
    "ifconfig eth0 up && udhcpc -i eth0<enter><wait5>",
    "wget -O /tmp/answers http://{{ .HTTPIP }}:{{ .HTTPPort }}/answers<enter><wait>",

    "ERASE_DISKS=/dev/sda setup-alpine -e -f /tmp/answers && mount /dev/sda3 /mnt && apk add --root /mnt qemu-guest-agent && chroot /mnt rc-update add qemu-guest-agent default && reboot<enter>"
  ]

  # --- SSH Communicator (KEY ONLY) ---
  vm_interface         = "eth0"
  ssh_username         = "root"
  ssh_private_key_file = var.ssh_private_key_file
  ssh_timeout          = "20m"

  # Cloud-init
  cloud_init              = true
  cloud_init_storage_pool = var.vm_storage_pool
}

