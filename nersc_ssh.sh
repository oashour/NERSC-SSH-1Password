#!/bin/bash

####################################################################################
# A script that integrates 1Password with NERSC's sshproxy service.
# Can also use without 1P to get automatic connection with credentials prompt every 
# 24 hours.
# Please read the README.md and what's linked within.
#
# Script written by Omar A. Ashour, UC Berkeley, Physics Department
# and Lawrence Berkeley National Lab, Molecular Foundry and Materials Sciences Division
# Original version was written on 2019/09/06.
#
# Currently hosted and updated on GitHub oashour/NERSC-SSH-1Password
####################################################################################

# Set up colors
R=$'\e[31m' # Red
G=$'\e[32m' # Green
Y=$'\e[33m' # Yellow
B=$'\e[36m' # Blue (actually Cyan)
RS=$'\e[0m' # Reset

# Specify Defaults
NERSC_USER=${USER}
CLUSTER=perlmutter # RIP Cori 2017-2023
CERTNAME=nersc
# Figure out where the script is installed
ROOT=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
SSHPROXY=${ROOT}/sshproxy.sh
PUTTY=" "

# Usage function
usage () {
    printf "Usage: $(basename $0) [flags]\n\n"
	printf "\t -u, --user <username>\t\t\tNERSC username\n"
	printf "\t\t\t\t\t\t(default: ${USER})\n"
    printf "\t -c, --cluster <cluster>\t\tNERSC Cluster (Perlmutter or Cori)\n"
	printf "\t\t\t\t\t\t(default: ${CLUSTER})\n"
	printf "\t -o, --cert <certname>\t\t\tFilename for private key\n"
	printf "\t\t\t\t\t\t(default: ${CERTNAME})\n"
	printf "\t -s, --sshproxy <sshproxy>\t\tAbsolute path for sshproxy.sh script\n"
	printf "\t\t\t\t\t\t(default: ${SSHPROXY})\n"
	printf "\t -w, --onepass <1password_entry>\tName of the 1password entry with NERSC credentials\n"
	printf "\t -p, --putty\t\t\t\tGet keys in PuTTY compatible (ppk) format.\n"
	printf "\t\t\t\t\t\t(This flag is sort of pointless since this is a *nix script)\n"
	printf "\t -h, --help \t\t\t\tPrint this usage message and exit\n"
	printf "\n"
	
	exit 0
}

# Parse flags
while [[ $# -gt 0 ]]; do
  case $1 in
    -u|--user)
      NERSC_USER="${2}"
      if [ -z ${NERSC_USER} ]; then
          echo -e "${R}${1} needs an argument.${RS}"
          usage
          exit 1
      fi
      shift 
      shift
      ;;
    -c|--cluster)
      CLUSTER="${2}"
      if [ -z ${CLUSTER} ]; then
          echo -e "${R}${1} needs an argument.${RS}"
          usage
          exit 1
      fi
      # Check validity of supplied cluster
      case $CLUSTER in
        cori|perlmutter) 
            shift
            shift
            ;;
        *) 
            echo -e "${R}Unknown cluster ${CLUSTER}${RS}"
            usage
            exit 1 
            ;;
      esac
      ;;
    -o|--cert)
      CERTNAME="${2}"
      if [ -z ${CERTNAME} ]; then
          echo -e "${R}${1} needs an argument.${RS}"
          usage
          exit 1
      fi
      shift
      shift
      ;;
    -s|--sshproxy)
      SSHPROXY="${2}"
      if [ -z ${SSHPROXY} ]; then
          echo -e "${R}${1} needs an argument.${RS}"
          usage
          exit 1
      fi
      shift
      shift
      ;;
    -p|--putty)
      PUTTY=" -p "
      shift
      ;;
    -w|--onepass)
      ONEPASS="${2}"
      if [ -z ${ONEPASS} ]; then
          echo -e "${R}${1} needs an argument.${RS}"
          usage
          exit 1
      fi
      shift
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*|--*)
      usage
      echo -e "${R}Invalid option: ${1}${RS}" >&2
      exit 1
      ;;
    *)
      echo -e "${R}This script does not take positional arguments.${RS}" >&2
      usage
      exit 1
      ;;
  esac
done

# Certificate path
CERTPATH="${HOME}/.ssh/"
# Pub key file name
PUBCERT="${CERTNAME}-cert.pub"
# Boolean for Putty
if [[ ${PUTTY} = *[!\ ]* ]]; then
    PUTTY_BOOL="True"
else
    PUTTY_BOOL="False"
fi

# Print outputs to user
echo -e "${Y}NERSC username:${RS} ${NERSC_USER}"
echo -e "${Y}Cluster:${RS} ${CLUSTER}"
echo -e "${Y}Certificate name:${RS} ${CERTNAME}"
echo -e "${Y}putty:${RS} ${PUTTY_BOOL}"
if [[ ! -z ${ONEPASS} ]]; then
    echo "${Y}1password entry:${RS} ${ONEPASS}"
fi

# Generate new certificate
function gen_cert {
    echo -e "${B}Generating new certificate.${RS}"
    # Check if file existsw
    if [ -f ${SSHPROXY} ]; then
        { # try
            # if 1Password mode is enabled
            if [[ ! -z ${ONEPASS} ]]; then
                echo -e "${B}1Password mode detected, retrieving credentials.${RS}"
                NERSC_PASS=$(op item get ${ONEPASS} --field password)
                # Check if 1P authenticated properly
                if [ ! $? -eq 0 ]; then
                    echo "${R}1Password CLI failed. Unable to obtain password.${RS}"; return 1;
                fi
                NERSC_OTP=$(op item get ${ONEPASS} --otp)
                # Check if OTP was obtained successfully
                # Normally if you authenticate the first time this will automatically work.
                if [ ! $? -eq 0 ]; then
                    echo "${R}1Password CLI failed. Unable to obtain OTP.${RS}"; return 1;
                fi
                cmd="${SSHPROXY} -u ${NERSC_USER}${PUTTY}-o ${CERTPATH}${CERTNAME} -w ${NERSC_PASS}${NERSC_OTP}"
            else
                cmd="${SSHPROXY} -u ${NERSC_USER}${PUTTY}-o ${CERTPATH}${CERTNAME}"
            fi
            eval "$cmd" && { echo -e "${G}New Certificate Generated${RS}"; return 0; }
        } || { # catch
            echo -e "${R}Certificate generation failed.${RS}"; return 1;
        }
    else
        echo -e "${R}File ${SSHPROXY} does not exist.${RS}"; return 1;
    fi
}

# Checks the certificate and generates a new one if needed
function cert_check {
    # Check if the file exists
    if [ -f "${CERTPATH}${PUBCERT}" ]
    then
        echo -e "${B}Certificate file found, checking validity.${RS}"
        # Get certificate expiry date and convert to seconds since epoch
        string=$(ssh-keygen -L -f "${CERTPATH}${PUBCERT}" | grep Valid)
        date=${string##*to }
        expiry=$(date -j -f "%Y-%m-%dT%H:%M:%S" ${date} "+%s")
        # If within 5 minutes of of expiry
        expiry=$((${expiry}-300))
        # seconds from epoch till now 
        now=$(date -j -f "%a %b %d %T %Z %Y" "$(date)" "+%s")
        # Some formatted strings for printing
        expdate=$(date -j -f "%Y-%m-%dT%H:%M:%S" ${date} "+%Y-%m-%d")
        exptime=$(date -j -f "%Y-%m-%dT%H:%M:%S" ${date} "+%H:%M:%S")
        if [ ${now} -ge ${expiry} ]; then
            echo -e "${R}Certificate expired on ${expdate} at ${exptime}!${RS}"
            { # try
                echo "------------------------------------------"
                gen_cert && { echo -e "${B}Proceeding with connection.${RS}"; return 0; }
                #echo "------------------------------------------"
            } || { # catch
                return 1
            }
        else
            echo -e "${G}Certificate valid till ${expdate} at ${exptime}! Proceeding with connection.${RS}"; return 0
        fi 
    else
        echo -e "${R}Certificate file not found.${RS}"
        { # try
            echo "------------------------------------------"
            gen_cert && { echo -e "${B}Proceeding with connection.${RS}"; return 0; }
            #echo "------------------------------------------"
        } || { # catch
            return 1
        }
    fi
}

# Determine cluster address
if [ "${CLUSTER}" = "perlmutter" ]
then
    HOST="perlmutter-p1.nersc.gov"
else
    HOST="cori.nersc.gov"
fi

# Run certificate check and connect
cert_check && ssh ${NERSC_USER}@${HOST}
