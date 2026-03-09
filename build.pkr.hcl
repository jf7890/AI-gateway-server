build {
  sources = ["source.proxmox-iso.alpine"]

  provisioner "file" {
    source      = "files/gateway-app"
    destination = "/tmp"
  }

  provisioner "shell" {
    script = "scripts/provision-gateway.sh"
  }
}
