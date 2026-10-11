#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$SCRIPT_DIR/../../terraform"
OUTPUT_FILE="$SCRIPT_DIR/hosts.ini"

# IPs vom Guest Agent neu einlesen (der State kann veraltet sein, z. B. nach Reboot/neuem Lease)
terraform -chdir="$TF_DIR" apply -refresh-only -auto-approve >/dev/null

IPS=$(terraform -chdir="$TF_DIR" output -json node_ips)
ROLES=$(terraform -chdir="$TF_DIR" output -json node_roles)

# Abbruch, wenn ein Node noch keine IP gemeldet hat
if echo "$IPS" | jq -e 'to_entries | map(select(.value == null or .value == "")) | length > 0' >/dev/null; then
  echo "Mindestens ein Node hat keine IP (Agent läuft noch nicht?):" >&2
  echo "$IPS" >&2
  exit 1
fi

{
  echo "# Automatisch generiert — nicht manuell bearbeiten!"
  for role in server agent storage; do
    echo ""
    echo "[$role]"
    jq -rn --argjson ips "$IPS" --argjson roles "$ROLES" --arg role "$role" \
      '$roles | to_entries[] | select(.value == $role)
       | "\(.key) ansible_host=\($ips[.key]) ansible_user=ubuntu"'
  done
} > "$OUTPUT_FILE"

cat "$OUTPUT_FILE"
