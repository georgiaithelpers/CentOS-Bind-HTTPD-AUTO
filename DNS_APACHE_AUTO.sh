#!/bin/bash

# Open firewall ports for DNS
firewall-cmd --add-port=53/tcp --permanent
firewall-cmd --add-port=53/udp --permanent
firewall-cmd --reload


#temporarily disable SELinux

setenforce 0

#show Network adapter name

nmcli connection show

# Prompt for network adapter name
read -p "Enter the name of the network adapter (e.g., enp0s3): " NETWORK_ADAPTER

#show ip 
ip -c a

# Prompt for the static IP address, subnet mask, gateway, and secondary DNS
read -p "Enter the static IP address: " STATIC_IP
read -p "Enter the subnet prefix length (e.g., 24): " SUBNET_PREFIX
read -p "Enter the gateway IP address: " GATEWAY
read -p "Enter secondary DNS: " DNS2
read -p "Enter domain name: " DOMAIN
read -p "Enter first level domain (e.g., com ge): " PDOMAIN
# Update network configuration using nmcli
sudo nmcli connection modify "$NETWORK_ADAPTER" ipv4.method manual ipv4.addresses $STATIC_IP/$SUBNET_PREFIX ipv4.gateway $GATEWAY ipv4.dns $STATIC_IP,$DNS2
sudo nmcli connection up "$NETWORK_ADAPTER"

# Display network configuration
echo -e "\nUpdated Network Configuration for $NETWORK_ADAPTER:"
sudo nmcli connection show "$NETWORK_ADAPTER"

# Display DNS configuration
echo -e "\nUpdated DNS Configuration:"
cat "/etc/sysconfig/network-scripts/ifcfg-$NETWORK_ADAPTER" | grep DNS

echo -e "\nNetwork successfully configured with static IP: $STATIC_IP"

# Add entry to /etc/hosts
echo -e "\nUpdating /etc/hosts with the entry for $DOMAIN"
echo "$STATIC_IP $DOMAIN.$PDOMAIN" | sudo tee -a /etc/hosts

# Restart network
sudo systemctl restart NetworkManager

# Install BIND DNS server
sudo yum install bind bind-utils -y

# Create forward zone for DNS
#DOMAIN=$(echo "$NETWORK_ADAPTER" | sed 's/\./_/g') # Use network adapter name as domain
ZONE_FILE="${DOMAIN}_zone.db"
SERIAL=$(date +"%Y%m%d%H") # Generate a serial number (YYYYMMDDHH)
cat <<EOF > "/etc/named.conf"
options {
    listen-on port 53 { any; };
    directory   "/var/named";
    dump-file   "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    allow-query     { any; };
    recursion yes;

    dnssec-enable yes;
    dnssec-validation yes;

    bindkeys-file "/etc/named.iscdlv.key";

    managed-keys-directory "/var/named/dynamic";
};

zone "$DOMAIN.$PDOMAIN" IN {
    type master;
    file "$ZONE_FILE";
    allow-update { none; };
    check-names ignore;
};
EOF

# Create forward zone file
cat <<EOF > "/var/named/$ZONE_FILE"
\$TTL 1D
@ IN SOA ns1.$DOMAIN.$PDOMAIN. admin.$DOMAIN.$PDOMAIN. (
    $SERIAL  ; Serial
    1D       ; Refresh
    1H       ; Retry
    1W       ; Expire
    3H       ; Minimum
)

@            IN    NS     ns1.$DOMAIN.$PDOMAIN.
ns1          IN    A      $STATIC_IP
www          IN    A      $STATIC_IP
EOF

# Create reverse zone file
cat <<EOF > "/var/named/reverse-$SUBNET_PREFIX.db"
\$TTL 1D
@ IN SOA ns1.$DOMAIN.$PDOMAIN. admin.$DOMAIN.$PDOMAIN. (
    $SERIAL  ; Serial
    1D       ; Refresh
    1H       ; Retry
    1W       ; Expire
    3H       ; Minimum
)

@            IN    NS     ns1.$DOMAIN.$PDOMAIN.
ns1          IN    A      $STATIC_IP
; Add reverse DNS entries here
$STATIC_IP_REV_PTR IN PTR  ns1.$DOMAIN.$PDOMAIN.
$STATIC_IP_REV_PTR IN PTR  www.$DOMAIN.$PDOMAIN.
EOF


# Restart named service
sudo systemctl restart named

echo -e "\nBIND DNS server installed and configured successfully."

# Install Apache web server
sudo yum install httpd -y

# Create Apache site configuration
SITE_CONF="/etc/httpd/conf.d/$DOMAIN.conf"
cat <<EOF > "$SITE_CONF"
<VirtualHost *:80>
    ServerAdmin webmaster@$DOMAIN
    DocumentRoot /var/www/html/$DOMAIN
    ServerName $DOMAIN.$PDOMAIN
    ErrorLog logs/$DOMAIN-error_log
    CustomLog logs/$DOMAIN-access_log common
</VirtualHost>
EOF

# Create website directory
mkdir -p "/var/www/html/$DOMAIN"
echo "<html><body><h1>Welcome to $DOMAIN!</h1></body></html>" > "/var/www/html/$DOMAIN/index.html"

# Set permissions for the website directory
chown -R apache:apache "/var/www/html/$DOMAIN"

# Restart Apache service
sudo systemctl restart httpd

echo -e "\nApache web server installed and site configured successfully."

# Check DNS resolution and open the site
echo -e "\nChecking DNS resolution for $DOMAIN:"
dig @$STATIC_IP $DOMAIN.$PDOMAIN

# Open the site via terminal
echo -e "\nOpening the site in the terminal:"
curl http://$DOMAIN.$PDOMAIN

