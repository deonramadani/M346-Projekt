#!/bin/bash
# Autor: Armin Hujdur
# Datum: 2025-11-23
# Erklärung: Das Skript baut eine ganze AWS-VPC und startet darin automatisch eine EC2 mit Public IP.

REGION="eu-central-1"
VPC_NAME="MeineVPC"
SUBNET_NAME="PublicSubnet"
IGW_NAME="MeineIGW"
RT_NAME="MainRouteTable"
SG_NAME="MeineSecurityGroup"
INSTANCE_NAME="MeineEC2"
INSTANCE_TYPE="t3.micro"
KEY_NAME="mein-ssh-key"
AMI_ID="ami-0c101f26f147fa7fd"   # Amazon Linux 2023 für eu-central-1

echo "Starte Erstellung der VPC + EC2 in $REGION …"

#######################################
### 1) VPC erstellen
#######################################
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --region $REGION \
  --query 'Vpc.VpcId' \
  --output text)
echo "VPC erstellt: $VPC_ID"

aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME --region $REGION


#######################################
### 2) Subnet erstellen
#######################################
SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone ${REGION}a \
  --query 'Subnet.SubnetId' \
  --output text)
echo "Subnet erstellt: $SUBNET_ID"

aws ec2 modify-subnet-attribute \
  --subnet-id $SUBNET_ID \
  --map-public-ip-on-launch \
  --region $REGION

aws ec2 create-tags --resources $SUBNET_ID --tags Key=Name,Value=$SUBNET_NAME --region $REGION


#######################################
### 3) Internet Gateway
#######################################
IGW_ID=$(aws ec2 create-internet-gateway \
  --region $REGION \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)
echo "Internet Gateway erstellt: $IGW_ID"

aws ec2 attach-internet-gateway \
  --internet-gateway-id $IGW_ID \
  --vpc-id $VPC_ID \
  --region $REGION

aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value=$IGW_NAME --region $REGION


#######################################
### 4) Routing Table
#######################################
RT_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'RouteTable.RouteTableId' \
  --output text)
echo "Route Table erstellt: $RT_ID"

aws ec2 create-tags --resources $RT_ID --tags Key=Name,Value=$RT_NAME --region $REGION

aws ec2 create-route \
  --route-table-id $RT_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID \
  --region $REGION

aws ec2 associate-route-table \
  --subnet-id $SUBNET_ID \
  --route-table-id $RT_ID \
  --region $REGION


#######################################
### 5) Security Group
#######################################
SG_ID=$(aws ec2 create-security-group \
  --group-name $SG_NAME \
  --description "Security Group für VPC" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query 'GroupId' \
  --output text)
echo "Security Group erstellt: $SG_ID"

aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 \
  --region $REGION

aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol icmp \
  --port -1 \
  --cidr 0.0.0.0/0 \
  --region $REGION


#######################################
### 6) SSH-Key erstellen (falls nicht vorhanden)
#######################################
if aws ec2 describe-key-pairs --key-names $KEY_NAME --region $REGION >/dev/null 2>&1; then
    echo "SSH-Key '$KEY_NAME' existiert bereits."
else
    echo "SSH-Key '$KEY_NAME' wird erstellt…"
    aws ec2 create-key-pair \
      --key-name $KEY_NAME \
      --region $REGION \
      --query "KeyMaterial" \
      --output text > "$KEY_NAME.pem"

    chmod 400 "$KEY_NAME.pem"
fi


#######################################
### 7) EC2-Instanz starten
#######################################
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $SG_ID \
  --subnet-id $SUBNET_ID \
  --associate-public-ip-address \
  --region $REGION \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
  --query 'Instances[0].InstanceId' \
  --output text)
echo "EC2 Instanz gestartet: $INSTANCE_ID"


#######################################
### 8) Auf Public IP warten
#######################################
echo "Warte auf Public IP…"
PUBLIC_IP=""
while [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" == "None" ]; do
    sleep 3
    PUBLIC_IP=$(aws ec2 describe-instances \
        --instance-ids $INSTANCE_ID \
        --region $REGION \
        --query "Reservations[0].Instances[0].PublicIpAddress" \
        --output text)
done

#######################################
### FERTIG
#######################################
echo
echo "=============================================="
echo "✔ VPC + EC2 erfolgreich erstellt!"
echo "VPC ID:        $VPC_ID"
echo "Subnet ID:     $SUBNET_ID"
echo "SecGroup ID:   $SG_ID"
echo "EC2-ID:        $INSTANCE_ID"
echo "Public IP:     $PUBLIC_IP"
echo
echo "SSH-Verbindung:"
echo "ssh -i $KEY_NAME.pem ec2-user@$PUBLIC_IP"
echo "=============================================="
