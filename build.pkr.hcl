build {
  sources = ["source.proxmox-iso.alpine"]

  provisioner "file" {
    source      = "files/gateway-app/"
    destination = "/opt/gateway-app"
  }

  provisioner "shell" {
    script = "scripts/provision-gateway.sh"
  }
}
