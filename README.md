# BA_v2
# Kubernetes-Cluster als Infrastructure as Code (Proxmox, Terraform, Ansible, RKE2)

Vollautomatischer Aufbau eines RKE2-Kubernetes-Clusters mit dediziertem Storage-Node (Longhorn). Terraform erzeugt die virtuellen Maschinen, Ansible erzeugt sein Inventory aus den Terraform-Outputs und richtet den Cluster ein. Es gibt keine fest eingetragenen IP-Adressen: Die IPs kommen per DHCP und werden über den QEMU Guest Agent ausgelesen.

Das Projekt ist so aufgebaut, dass es von einem Proxmox-Lab in ein Netz hinter einem Proxy übertragen werden kann. Umgebungsspezifische Werte stehen ausschließlich in Variablen.

## Architektur

```
 Control-Node
 ├── Terraform ──► Proxmox-API ──► klont Template ──► 4 VMs
 │                                                     │
 │      IPs über QEMU Guest Agent  ◄───────────────────┘
 │
 ├── generate_inventory.sh   (node_ips + node_roles ──► hosts.ini)
 └── Ansible ──► SSH ──► Cluster-Setup
```

| Node | Rolle | vCPU | RAM | Disk |
|---|---|---|---|---|
| rke2-server-01 | Control Plane (etcd, API-Server) | 2 | 4 GB | 32 GB |
| rke2-agent-01 | Worker | 2 | 3 GB | 32 GB |
| rke2-agent-02 | Worker | 2 | 3 GB | 32 GB |
| rke2-storage-01 | Storage (Longhorn), per Taint isoliert | 2 | 2 GB | 64 GB |

**Stack:** Proxmox VE, Terraform (Provider `bpg/proxmox`), Ansible, RKE2 v1.36.5, Calico, Longhorn, Helm

## Ablauf

1. **Template** (einmalig): Ubuntu-22.04-Cloud-Image mit vorinstalliertem `qemu-guest-agent`, als Proxmox-Template (VMID 9000).
2. **Terraform** klont das Template pro Eintrag in `cluster_nodes`. Die VMs holen sich ihre IP per DHCP, Terraform liest sie über den Guest Agent aus (`node_ips`) und gibt zusätzlich die Rollen aus (`node_roles`).
3. **Inventory:** `generate_inventory.sh` aktualisiert den Terraform-State (`apply -refresh-only`) und schreibt aus den beiden Outputs die `hosts.ini` mit den Gruppen `server`, `agent` und `storage`.
4. **Ansible** (`site.yml`) arbeitet in dieser Reihenfolge:
   1. Auf SSH und abgeschlossenes Cloud-Init warten
   2. Basis-Setup auf allen Nodes (Swap aus, Kernel-Module, sysctl, optional Proxy)
   3. RKE2-Server installieren, Join-Token auslesen
   4. RKE2-Agents installieren (Worker und Storage-Node)
   5. Storage-Node mit Taint und Labels versehen
   6. Longhorn per Helm installieren

## Projektstruktur

```
.
├── ansible.cfg
├── ansible/
│   ├── site.yml
│   ├── inventory/
│   │   ├── generate_inventory.sh      # Terraform-Outputs ──► hosts.ini
│   │   └── group_vars/all.yml         # Proxy, Netz, Server-Adresse, RKE2-Version
│   └── roles/
│       ├── common/
│       ├── rke2-server/
│       ├── rke2-agent/
│       ├── rke2-storage/
│       └── longhorn/
└── terraform/
    ├── main.tf                        # Provider und Modul-Aufruf pro Node
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars               # Node-Definitionen
    └── modules/proxmox-vm/            # wiederverwendbares VM-Modul
```

## Voraussetzungen

- Proxmox-Host mit Template (VMID 9000, Guest Agent installiert, `agent enabled=1`) und einem Netz mit DHCP
- API-Token für Terraform (ohne Privilege Separation oder mit ausreichenden Rechten)
- Control-Node mit Terraform, Ansible, `jq`, der Ansible-Collection `kubernetes.core` und dem Paket `python3-kubernetes`
- SSH-Key der Control-Node, dessen Public Key per Cloud-Init in die VMs gelangt

## Einmalige Vorbereitung

Diese zwei Schritte werden pro Umgebung einmal gemacht und danach nicht wiederholt.

### 1. VM-Template mit QEMU Guest Agent

Auf dem Proxmox-Host. Das Template ist die Grundlage für alle Cluster-Nodes. Der Guest Agent ist darin vorinstalliert, damit Proxmox und Terraform die IP-Adresse jeder geklonten VM abfragen können.

```bash
export LIBGUESTFS_BACKEND=direct
BRIDGE=vmbr1          # Bridge der Umgebung
STORAGE=local-lvm     # Storage-Pool der Umgebung
VMID=9000

cd /var/lib/vz/template/iso
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img

apt install -y libguestfs-tools
virt-customize -a jammy-server-cloudimg-amd64.img \
  --install qemu-guest-agent \
  --run-command 'systemctl enable qemu-guest-agent' \
  --truncate /etc/machine-id

qm create $VMID --name ubuntu-2204-tpl --memory 2048 --cores 2 \
  --net0 virtio,bridge=$BRIDGE --agent enabled=1 \
  --scsihw virtio-scsi-pci --ostype l26
qm importdisk $VMID jammy-server-cloudimg-amd64.img $STORAGE
qm set $VMID --scsi0 $STORAGE:vm-$VMID-disk-0
qm set $VMID --ide2 $STORAGE:cloudinit
qm set $VMID --boot order=scsi0 --serial0 socket --vga serial0
qm set $VMID --ipconfig0 ip=dhcp
qm template $VMID
```

Wichtig sind `--agent enabled=1` (sonst liefert Proxmox keine IP zurück) und das Leeren der `/etc/machine-id` (sonst können geklonte VMs dieselbe DHCP-Client-ID bekommen). Hinter einem Proxy braucht der Host für `wget` und `virt-customize` ggf. ebenfalls die Proxy-Variablen.

### 2. Control-Node

Von dieser VM aus laufen Terraform und Ansible. Sie wird einmal aus demselben Ubuntu-Cloud-Image erzeugt (2 vCPU, 2 GB RAM, 20 GB Disk) und bekommt per Cloud-Init den Benutzer `ubuntu` und einen SSH-Key. Ihre IP ist fest, weil sie der Einstiegspunkt ist.

```bash
VMID=200
STORAGE=local-lvm
BRIDGE=vmbr0
IP=192.0.2.10/24
GATEWAY=192.0.2.1

qm create $VMID --name control-node --memory 2048 --cores 2 \
  --net0 virtio,bridge=$BRIDGE
qm importdisk $VMID ubuntu-22.04-cloudimg.img $STORAGE
qm set $VMID --scsihw virtio-scsi-pci --scsi0 $STORAGE:vm-$VMID-disk-0
qm set $VMID --ide2 $STORAGE:cloudinit
qm set $VMID --boot order=scsi0 --serial0 socket --vga serial0
qm set $VMID --ipconfig0 ip=$IP,gw=$GATEWAY
qm set $VMID --ciuser ubuntu --sshkeys ~/.ssh/authorized_keys
qm resize $VMID scsi0 20G
qm start $VMID
```

Auf der Control-Node werden danach installiert:

- Terraform
- Ansible 
- `jq` und `git`
- Collection und Python-Bibliothek für die Kubernetes-Module:

```bash
ansible-galaxy collection install kubernetes.core
sudo apt install -y python3-kubernetes
```

Die Control-Node braucht einen SSH-Schlüssel (`~/.ssh/id_ed25519`). Der Public Key landet über Cloud-Init in allen Cluster-VMs, und Ansible nutzt ihn für den Zugriff.


## Benutzung

Token in `terraform/secrets.auto.tfvars` ablegen (liegt nicht im Repository):

```hcl
proxmox_api_token = "USER@REALM!TOKENID=SECRET"
```

Bei Bedarf in `terraform/main.tf` den `endpoint` des Proxmox-Hosts anpassen. Dann:

```bash
cd terraform
terraform init
terraform apply
cd ..

./ansible/inventory/generate_inventory.sh
ansible all -m ping
ansible-playbook ansible/site.yml
```

Prüfen auf dem Server-Node (nach einem neuen SSH-Login, denn `kubectl` und `KUBECONFIG` werden von Ansible über `/etc/profile.d/rke2.sh` bereitgestellt):

```bash
kubectl get nodes
```

## Einsatz im Netz hinter einem Proxy

Alle umgebungsspezifischen Werte stehen in `ansible/inventory/group_vars/all.yml`. Der Proxy ist im Standard ausgeschaltet und wird per Variable aktiviert:

```bash
ansible-playbook ansible/site.yml \
  -e proxy_enabled=true \
  -e proxy_url=http://PROXY:PORT \
  -e node_cidr=10.0.0.0/24
```

Bei aktivem Proxy setzt die Rolle `common` die systemweiten Proxy-Variablen und die APT-Konfiguration. Für RKE2 legt sie ein systemd-Drop-in an, damit auch containerd beim Laden der Images den Proxy nutzt. Cluster-interner Verkehr (Node-, Pod- und Service-Netz) ist in `NO_PROXY` ausgenommen.

Beim Umzug in eine andere Umgebung ändern sich außerdem nur diese Werte:

- Terraform: `endpoint`, API-Token, sowie `node_name`, `datastore_id`, `bridge` und `template_vmid` des Moduls
- Ansible: `rke2_server_address` (hier einen DNS-Namen eintragen, falls sich die IP des Servers ändern kann)
- Auf dem Terraform-Host für `terraform init`: `HTTPS_PROXY`, und die IP des Proxmox-Hosts in `NO_PROXY`

## Designentscheidungen

- **Keine festen IPs:** Terraform fragt die IPs über den QEMU Guest Agent ab. Das Inventory ist dadurch immer synchron mit der tatsächlichen Infrastruktur.
- **Eine Quelle für die Wahrheit:** Die Node-Liste steht nur in `terraform.tfvars`. Rollen und Inventory-Gruppen werden daraus abgeleitet.
- **Wiederverwendbares Modul:** Eine VM-Beschreibung für alle Nodes über `for_each`.
- **Storage-Isolation:** Der Storage-Node trägt einen `NoSchedule`-Taint, damit dort keine Anwendungs-Pods landen.
- **Feste RKE2-Version** statt `stable`: reproduzierbarer Aufbau, Server und Agents haben garantiert dieselbe Version.
- **Idempotente Rollen:** Ein erneuter Lauf von `site.yml` ändert nichts, was schon stimmt.
- **Handler vor Service-Start** (`flush_handlers`): Der Proxy-Drop-in ist aktiv, bevor RKE2 zum ersten Mal startet.

## Bekannte Einschränkungen

- Ändert sich die IP des Servers nach dem Aufbau, müssen die Agents neu konfiguriert werden. Abhilfe: DNS-Name in `rke2_server_address` oder eine DHCP-Reservierung.
- Der Terraform-State liegt lokal. Für den Teambetrieb wäre ein Remote-Backend nötig.
- Der Provider ist mit `insecure = true` konfiguriert, weil der Lab-Proxmox ein selbstsigniertes Zertifikat nutzt.
- Eine einzelne Control-Plane-Node und eine einzelne Storage-Node sind keine Hochverfügbarkeit. Longhorn läuft mit einer Replika.

## Nicht im Repository

`secrets.auto.tfvars`, Terraform-State, `.terraform/` und die generierte `hosts.ini` stehen in der `.gitignore`.
