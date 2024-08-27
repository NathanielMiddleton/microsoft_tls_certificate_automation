#!/bin/bash
# Organization specific variables
CA_SERVER="https://servername/certsrv"
CERT_TEMPLATE="WebServer"

show_help() {
    echo "Usage: $(basename $0) [OPTIONS]"
    echo "Options:"
    echo "  -C, --country"
    echo "  -s, --state"
    echo "  -c, --city"
    echo "  -o, --organization"
    echo "  -u, --org_unit"
    echo "  -n, --common_name     The server's fully qualified domain name"
    echo "  -e, --email           The email address of the server owner"
    echo "  -S, --server_alt_name Names that the server may be referenced as"
    echo "  -f, --csr_file        Filename for the certificate request to be saved as"
    echo "  -G, --generate_key    Specify "yes" or "no" to generate a pass key for the cert. Be sure your app supports this."
    echo "  -U, --username        The user that will authenticate against the certificate server"
    echo "  -P, --password        The password used for --username"
    echo ""
    echo "Multiple fields can be specified, fields left unspecified will prompt for input"
    echo "example: ./request_cer.sh --country US --state UNK --city Port Wenn --organization "Some Company" --org_unit IT "
}

# Read args
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -C|--country)
      COUNTRY="$2"
      shift # past argument
      shift # past value
      ;;
    -s|--state)
      STATE="$2"
      shift # past argument
      shift # past value
      ;;
    -c|--city)
      CITY="$2"
      shift # past argument
      shift # past value
      ;;
    -o|--organization)
      ORGANIZATION="$2"
      shift # past argument
      shift # past value
      ;;
    -u|--org_unit)
      ORG_UNIT="$2"
      shift # past argument
      shift # past value
      ;;
    -n|--common_name)
      COMMON_NAME="$2"
      shift # past argument
      shift # past value
      ;;
    -e|--email)
      EMAIL="$2"
      shift # past argument
      shift # past value
      ;;
    -S|--server_alt_name)
      SAN="$2"
      shift # past argument
      shift # past value
      ;;
    -f|--csr_file)
      CSR_FILE="$2"
      shift # past argument
      shift # past value
      ;;
    -G|--generate_key)
      GENERATE_KEY="$2"
      shift # past argument
      shift # past value
      ;;
    -K|--keyfile)
      KEY_FILE="$2"
      shift # past argument
      shift # past value
      ;;
    -U|--username)
      USERNAME="$2"
      shift # past argument
      shift # past value
      ;;
    -P|--password)
      PASSWORD="$2"
      shift # past argument
      shift # past value
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      POSITIONAL_ARGS+=("$1") # save positional arg
      shift # past argument
      ;;
  esac
done

# Function to prompt user for input with a default value
prompt() {
    read -p "$1 [$2]: " input
    echo ${input:-$2}
}

# Collecting information from the user
echo "Please provide the following details to generate a CSR:"
if [[ -z ${COUNTRY} ]]; then
COUNTRY=$(prompt "Country (2 letter code)" "US")
fi
if [[ -z ${STATE} ]]; then
STATE=$(prompt "State or Province" "")
fi
if [[ -z ${CITY} ]]; then
CITY=$(prompt "City or Locality" "")
fi
if [[ -z ${ORGANIZATION} ]]; then
ORGANIZATION=$(prompt "Organization Name" "")
fi
if [[ -z ${ORG_UNIT} ]]; then
ORG_UNIT=$(prompt "Organizational Unit" "")
fi
if [[ -z ${COMMON_NAME} ]]; then
COMMON_NAME=$(prompt "Common Name (e.g., your full servername.somecompany.com)" "$(hostname)")
fi
if [[ -z ${EMAIL} ]]; then
EMAIL=$(prompt "Email Address" "$(whoami)@somecompany.com")
fi
if [[ -z ${SAN} ]]; then
SAN=$(prompt "Subject Alternative Names (comma-separated, e.g., DNS:serveraltname.somecompany.com,DNS:servicename.somecompany.com)" "")
fi

# Prompt for CSR file name
if [[ -z ${CSR_FILE} ]]; then
CSR_FILE=$(prompt "Please provide the desired name for the CSR file (e.g., request.csr)" "$(hostname).csr")
fi
# Prompt user whether to generate a new private key
if [[ -z ${GENERATE_KEY} ]]; then
GENERATE_KEY=$(prompt "Do you want to generate a new private key? (yes/no)" "yes")
fi
if [[ "$GENERATE_KEY" == "yes" ]]; then
# Generate private key
    openssl genpkey -algorithm RSA -out ${CSR_FILE}_private.key
    KEY_FILE="${CSR_FILE}_private.key"
else
# Prompt for existing key file
KEY_FILE=$(prompt "Please provide the path to an existing private key file." "")
fi
if [[ ! -f "$KEY_FILE" ]]; then 
	echo ""
	echo "No key file specified, cert creation impossible. Please re-run this tool with a key defined, or generated"
	echo "How about a nice game of chess?"
	exit 0
fi
# Create a configuration file for OpenSSL
cat > csr.conf <<EOL
[ req ]
default_bits       = 2048
distinguished_name = req_distinguished_name
req_extensions     = req_ext
prompt             = no

[ req_distinguished_name ]
C  = $COUNTRY
ST = $STATE
L  = $CITY
O  = $ORGANIZATION
OU = $ORG_UNIT
CN = $COMMON_NAME
emailAddress = $EMAIL

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
EOL

# Add SANs to the configuration file
IFS=',' read -ra ADDR <<< "$SAN"
for i in "${!ADDR[@]}"; do
    echo "DNS.$((i+1)) = ${ADDR[$i]}" >> csr.conf
done

# Generate CSR
openssl req -new -key $KEY_FILE -out $CSR_FILE -config csr.conf

echo "CSR has been generated."
echo "CSR: $CSR_FILE"
if [ "$GENERATE_KEY" == "yes" ]; then
    echo "Private Key: ${CSR_FILE}_private.key"
fi

# Read the CSR content
CSR_CONTENT=$(cat $CSR_FILE)

# Prompt for username
read -p 'Username: (ex: gregd)' USERNAME

# Prompt for password (input will be hidden)
read -sp 'Password: ' PASSWORD
echo ''
read -p 'Will you need a full chain for this cert? (yes/no)' CHAIN

# Submit the CSR using curl
echo "Submitting CSR..."
RESPONSE=$(curl -s --http1.1 --user $USERNAME:$PASSWORD --ntlm -X POST "$CA_SERVER/certfnsh.asp" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "Mode=newreq" \
  --data-urlencode "CertRequest=$CSR_CONTENT" \
  --data-urlencode "CertAttrib=CertificateTemplate:$CERT_TEMPLATE" \
  --data-urlencode "TargetStoreFlags=0" \
  --data-urlencode "SaveCert=yes")

# Extract the request ID from the response
REQUEST_ID=$(echo "$RESPONSE" | grep -oP 'certnew.cer\?ReqID=\K\d+' | uniq)

# Download the issued certificate
if [[ $CHAIN == "yes" ]]; then
        echo "Downloading full chain cert: ${CSR_FILE}_chain.pem"
        curl -s -o ${CSR_FILE}.p7b --http1.1 --user $USERNAME:$PASSWORD --ntlm -H 'User-Agent: ITO_script' --ntlm "${CA_SERVER}/certnew.p7b?ReqID=${REQUEST_ID}&Enc=b64"
	if [ $? -ne 0 ]; then
  		echo "Failed downloading p7b cert. Exiting."
  		exit 1
	fi
        openssl pkcs7 -print_certs -in ${CSR_FILE}.p7b -out ${CSR_FILE}_chain.pem
else
        echo "Downloading pem cert: ${CSR_FILE}.pem"
        curl -s -o ${CSR_FILE}.pem --http1.1 --user $USERNAME:$PASSWORD --ntlm -H 'User-Agent: ITO_script' --ntlm "${CA_SERVER}/certnew.cer?ReqID=${REQUEST_ID}&Enc=b64"
	if [ $? -ne 0 ]; then
  		echo "Failed downloading pem cert. Exiting."
  		exit 1
	fi
fi
echo "Complete."
