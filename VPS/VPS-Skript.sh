#!/bin/bash
# Autor: Armin Hujdur
# Datum: 2025-11-23
# Erklärung: Das Skript erstellt automatisch eine EC2-Instanz inklusive Zugriff und zeigt dir die Public IP an.

### Konfiguration ###
REGION="eu-central-1"
INSTANCE_NAME="meine-ssh-vps"
INSTANCE_TYPE="t3.micro"                         
AMI_ID="ami-0c101f26f147fa7fd"                   # Amazon Linux 2023 (eu-central-1)
KEY_NAME="mein-ssh-key"
SG_NAME="vps-sg"

echo "Starte Erstellung der VPS in $REGION …"

### 1) Prüfen, ob SSH-Key existiert ###
if aws ec2 describe-key-pairs --key-names $KEY_NAME --region $REGION >/dev/null 2>&1; then
    echo "SSH-Key '$KEY_NAME' existiert bereits."
else
    echo "SSH-Key '$KEY_NAME' existiert nicht, wird erstellt…"
    aws ec2 create-key-pair \
      --key-name $KEY_NAME \
      --region $REGION \
      --query "KeyMaterial" \
      --output text > "$KEY_NAME.pem"

    chmod 400 "$KEY_NAME.pem"
    echo "SSH-Key $KEY_NAME.pem gespeichert."
fi

### 2) Security Group erstellen ###
SG_ID=$(aws ec2 create-security-group \
  --group-name $SG_NAME \
  --description "Security Group für VPS" \
  --region $REGION \
  --query 'GroupId' \
  --output text)

echo "Security Group erstellt: $SG_ID"

### 3) SSH-Port öffnen ###
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 \
  --region $REGION

echo "Port 22 (SSH) freigegeben."

### 4) EC2 Instanz erstellen ###
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --count 1 \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --region $REGION \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
  --query "Instances[0].InstanceId" \
  --output text)

echo "EC2-Instanz gestartet: $INSTANCE_ID"

### 5) Auf öffentliche IP warten ###
echo "Warte auf Zuweisung einer Public IP…"

PUBLIC_IP=""
while [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" == "None" ]; do
    sleep 3
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --region $REGION \
        --query "Reservations[0].Instances[0].PublicIpAddress" \
        --output text)
done

echo "VPS ist bereit!"
echo "Public IP: $PUBLIC_IP"
echo
echo "Verbinde dich so:"
echo "ssh -i $KEY_NAME.pem ec2-user@$PUBLIC_IP"
