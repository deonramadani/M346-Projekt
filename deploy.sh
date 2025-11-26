#!/bin/bash
# Autor: Armin Hujdur, Jan Speck
# Datum: 2025-11-24
# Erklärung: Das Skript baut automatisch die noetige AWS-Infrastruktur auf  und startet zwei EC2-Server, auf denen Webserver, 
# Datenbank und Nextcloud mit den Init-Skripten aus dem IaC-Ordner eingerichtet werden.

set -e

#########################################################
# M346 Nextcloud Deployment Script
# - fuer AWS CloudShell in us-east-1 (N. Virginia)
# - erstellt VPC, Subnet, Routing, Security Groups
# - startet Web- und DB-Server
# - benutzt IaC/initial-webserver.sh und IaC/initial-db-server.sh
#########################################################

# Region aus AWS Konfiguration holen (CloudShell hat die schon gesetzt)
AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
if [ -z "$AWS_REGION" ]; then
  echo "Konnte keine AWS Region ermitteln. Bitte in der Console eine Region waehlen."
  exit 1
fi

PROJECT_NAME="m346-nextcloud"
VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNET_CIDR="10.0.1.0/24"
INSTANCE_TYPE="t3.micro"



# Pruefen ob die Dateien existieren
if [ ! -f "${WEB_USER_DATA_FILE}" ]; then
  echo "FEHLER: ${WEB_USER_DATA_FILE} wurde nicht gefunden."
  exit 1
fi

if [ ! -f "${DB_USER_DATA_FILE}" ]; then
  echo "FEHLER: ${DB_USER_DATA_FILE} wurde nicht gefunden."
  exit 1
fi

echo "================ DEPLOY KONFIG ================"
echo "Region:           ${AWS_REGION}"
echo "Projektname:      ${PROJECT_NAME}"
echo "VPC CIDR:         ${VPC_CIDR}"
echo "Subnet CIDR:      ${PUBLIC_SUBNET_CIDR}"
echo "Instance Type:    ${INSTANCE_TYPE}"
echo "Web User-Data:    ${WEB_USER_DATA_FILE}"
echo "DB User-Data:     ${DB_USER_DATA_FILE}"
echo "================================================"
echo

AWS="aws --region ${AWS_REGION}"

#########################################################
# Ubuntu 22.04 AMI fuer us-east-1 (N. Virginia)
#########################################################

echo "==> Setze Ubuntu 22.04 AMI fuer us-east-1 (N. Virginia)..."
AMI_ID="ami-04b4f1a9cf54c11d0"
echo "Verwende AMI_ID = ${AMI_ID}"
echo

#########################################################
# VPC und Netzwerk
#########################################################

echo "==> VPC anlegen..."
VPC_ID=$($AWS ec2 create-vpc \
  --cidr-block "${VPC_CIDR}" \
  --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${PROJECT_NAME}-vpc}]" \
  --query 'Vpc.VpcId' \
  --output text)
echo "VPC_ID = ${VPC_ID}"

# DNS Features aktivieren
$AWS ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-support "{\"Value\":true}"
$AWS ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-hostnames "{\"Value\":true}"

echo "==> Internet-Gateway anlegen und verbinden..."
IGW_ID=$($AWS ec2 create-internet-gateway \
  --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${PROJECT_NAME}-igw}]" \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)
$AWS ec2 attach-internet-gateway --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}"
echo "IGW_ID = ${IGW_ID}"

echo "==> Public Subnet anlegen..."
SUBNET_ID=$($AWS ec2 create-subnet \
  --vpc-id "${VPC_ID}" \
  --cidr-block "${PUBLIC_SUBNET_CIDR}" \
  --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-subnet}]" \
  --query 'Subnet.SubnetId' \
  --output text)
echo "SUBNET_ID = ${SUBNET_ID}"

# Public IPs automatisch vergeben
$AWS ec2 modify-subnet-attribute --subnet-id "${SUBNET_ID}" --map-public-ip-on-launch

echo "==> Route-Table fuer Internetzugang..."
ROUTE_TABLE_ID=$($AWS ec2 create-route-table \
  --vpc-id "${VPC_ID}" \
  --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${PROJECT_NAME}-public-rt}]" \
  --query 'RouteTable.RouteTableId' \
  --output text)
echo "ROUTE_TABLE_ID = ${ROUTE_TABLE_ID}"

$AWS ec2 create-route \
  --route-table-id "${ROUTE_TABLE_ID}" \
  --destination-cidr-block "0.0.0.0/0" \
  --gateway-id "${IGW_ID}" >/dev/null

$AWS ec2 associate-route-table \
  --route-table-id "${ROUTE_TABLE_ID}" \
  --subnet-id "${SUBNET_ID}" >/dev/null

#########################################################
# Security Groups
#########################################################

echo "==> Security Groups erstellen..."

# Webserver SG: HTTP/HTTPS aus dem Internet
WEB_SG_ID=$($AWS ec2 create-security-group \
  --group-name "${PROJECT_NAME}-web-sg" \
  --description "Security Group fuer Webserver" \
  --vpc-id "${VPC_ID}" \
  --query 'GroupId' \
  --output text)
$AWS ec2 create-tags --resources "${WEB_SG_ID}" --tags Key=Name,Value="${PROJECT_NAME}-web-sg"

# HTTP
$AWS ec2 authorize-security-group-ingress \
  --group-id "${WEB_SG_ID}" \
  --ip-permissions IpProtocol=tcp,FromPort=80,ToPort=80,IpRanges="[{CidrIp=0.0.0.0/0}]"

# HTTPS (falls spaeter TLS)
$AWS ec2 authorize-security-group-ingress \
  --group-id "${WEB_SG_ID}" \
  --ip-permissions IpProtocol=tcp,FromPort=443,ToPort=443,IpRanges="[{CidrIp=0.0.0.0/0}]"

# DB SG: MySQL nur aus VPC (inkl. Webserver)
DB_SG_ID=$($AWS ec2 create-security-group \
  --group-name "${PROJECT_NAME}-db-sg" \
  --description "Security Group fuer DB-Server" \
  --vpc-id "${VPC_ID}" \
  --query 'GroupId' \
  --output text)
$AWS ec2 create-tags --resources "${DB_SG_ID}" --tags Key=Name,Value="${PROJECT_NAME}-db-sg"

# MySQL/MariaDB nur aus dem VPC Netz
$AWS ec2 authorize-security-group-ingress \
  --group-id "${DB_SG_ID}" \
  --ip-permissions IpProtocol=tcp,FromPort=3306,ToPort=3306,IpRanges="[{CidrIp=${VPC_CIDR}}]"

echo "WEB_SG_ID = ${WEB_SG_ID}"
echo "DB_SG_ID  = ${DB_SG_ID}"
echo

#########################################################
# EC2 Instanzen (Web + DB)
#########################################################

echo "==> Webserver Instanz starten..."
WEB_INSTANCE_ID=$($AWS ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type "${INSTANCE_TYPE}" \
  --subnet-id "${SUBNET_ID}" \
  --security-group-ids "${WEB_SG_ID}" \
  --associate-public-ip-address \
  --user-data file://./IaC/initial-webserver.sh \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-web},{Key=Role,Value=web}]" \
  --query 'Instances[0].InstanceId' \
  --output text)
echo "WEB_INSTANCE_ID = ${WEB_INSTANCE_ID}"

echo "==> DB Instanz starten..."
DB_INSTANCE_ID=$($AWS ec2 run-instances \
  --image-id "${AMI_ID}" \
  --instance-type "${INSTANCE_TYPE}" \
  --subnet-id "${SUBNET_ID}" \
  --security-group-ids "${DB_SG_ID}" \
  --associate-public-ip-address \
  --user-data file://./IaC/initial-db-server.sh \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT_NAME}-db},{Key=Role,Value=db}]" \
  --query 'Instances[0].InstanceId' \
  --output text)
echo "DB_INSTANCE_ID = ${DB_INSTANCE_ID}"

#########################################################
# Warten bis Instanzen laufen
#########################################################

echo "==> Warte bis Instanzen im Status 'running' sind..."
$AWS ec2 wait instance-running --instance-ids "${WEB_INSTANCE_ID}" "${DB_INSTANCE_ID}"

#########################################################
# IP Adressen ausgeben
#########################################################

WEB_PUBLIC_IP=$($AWS ec2 describe-instances \
  --instance-ids "${WEB_INSTANCE_ID}" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

DB_PRIVATE_IP=$($AWS ec2 describe-instances \
  --instance-ids "${DB_INSTANCE_ID}" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

echo
echo "============== DEPLOYMENT FERTIG =============="
echo "Webserver oeffentliche IP:   ${WEB_PUBLIC_IP}"
echo "DB Server private IP:       ${DB_PRIVATE_IP}"
echo
echo "Rufe im Browser auf:  http://${WEB_PUBLIC_IP}"
echo
echo "Im Nextcloud Installer tragt ihr ein:"
echo "  Datenbank-Host:     ${DB_PRIVATE_IP}"
echo "  Datenbank-Name:     nextcloud"
echo "  Datenbank-Benutzer: nextcloud"
echo "  Datenbank-Passwort: nextcloud-pass"
echo "==============================================="
