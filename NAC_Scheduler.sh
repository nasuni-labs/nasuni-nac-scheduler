#!/bin/bash

##############################################
## Pre-Requisite(S):						##
## 		- Git, AWS CLI, JQ 					##
##		- AWS Profile Setup as nasuni		##
##############################################
DATE_WITH_TIME=$(date "+%Y%m%d-%H%M%S")
START=$(date +%s)

check_if_vpc_exists(){
INPUT_VPC_IS="$1"

# VPCS=`aws ec2 describe-vpcs | jq -r '.Vpcs[].VpcId'`
VPC_CHECK=`aws ec2 describe-vpcs --filters "Name=vpc-id,Values=$INPUT_VPC_IS" --region ${AWS_REGION} | jq -r '.Vpcs[].VpcId'`
echo "%%%%%%% $INPUT_VPC_IS %%%%%%%%%%%"$VPC_CHECK

if [ "$VPC_CHECK" == "null" ] || [ "$VPC_CHECK" == "" ]; then
	echo "ERROR ::: VPC $INPUT_VPC_IS not available. Please provide a valid VPC ID."
	exit 1
else
	echo "INFO ::: VPC $INPUT_VPC_IS is Valid" 
fi
}

check_if_pem_file_exists() {
FILE=$(echo "$1" | tr -d '"')
if [ -f "$FILE" ]; then
	echo "INFO ::: $FILE exists."
else 
	echo "ERROR ::: $FILE does not exist."
	exit 1
fi

}

validate_github() {
	GITHUB_ORGANIZATION=$1
	REPO_FOLDER=$2
	if [[ $GITHUB_ORGANIZATION == "" ]];then
		GITHUB_ORGANIZATION="nasuni-labs"
		echo "INFO ::: github_organization not provided as Secret Key-Value pair. So considering nasuni-labs as the default value !!!"
	fi 
	GIT_REPO="https://github.com/$GITHUB_ORGANIZATION/$REPO_FOLDER.git"
	echo "INFO ::: git repo $GIT_REPO"
	git ls-remote $GIT_REPO -q
	REPO_EXISTS=$?
	if [ $REPO_EXISTS -ne 0 ]; then
		echo "ERROR ::: Unable to Access the git repo $GIT_REPO. Execution STOPPED"
		exit 1
	else
		echo "INFO ::: git repo accessible. Continue . . . Provisioning . . . "
	fi
}

nmc_endpoint_accessibility() {
	NAC_SCHEDULER_NAME="$1"
	PUB_IP_ADDR_NAC_SCHEDULER="$2"
    NMC_API_ENDPOINT="$3"
	NMC_API_USERNAME="$4"
	NMC_API_PASSWORD="$5" #14-19
	PEM="$PEM_KEY_PATH"
	
	chmod 400 $PEM
	### nac_scheduler_name = from FourthArgument of NAC_Scheduler.sh, user_sec.txt
	### parse_textfile_for_user_secret_keys_values user_sec.txt
	echo "INFO ::: Inside nmc_endpoint_accessibility"
	echo "INFO ::: NAC_SCHEDULER_NAME ::: ${NAC_SCHEDULER_NAME}"
	echo "INFO ::: PUB_IP_ADDR_NAC_SCHEDULER ::: ${PUB_IP_ADDR_NAC_SCHEDULER}"
	echo "INFO ::: PEM ::: ${PEM}"
	echo "INFO ::: NMC_API_ENDPOINT ::: ${NMC_API_ENDPOINT}"
	echo "INFO ::: NMC_API_USERNAME ::: ${NMC_API_USERNAME}"
	echo "INFO ::: NMC_API_PASSWORD ::: ${NMC_API_PASSWORD}" # 31-37

	echo "INFO ::: PUB_IP_ADDR_NAC_SCHEDULER : "$PUB_IP_ADDR_NAC_SCHEDULER
	py_file_name=$(ls check_nmc_visiblity.py)
	echo "INFO ::: Executing Python code file : "$py_file_name
	cat $py_file_name | ssh -i "$PEM" ubuntu@$PUB_IP_ADDR_NAC_SCHEDULER -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null python3 - $NMC_API_USERNAME $NMC_API_PASSWORD $NMC_API_ENDPOINT
	if [ $? -eq 0 ]; then
		echo "INFO ::: NAC Scheduler with IP : ${PUB_IP_ADDR_NAC_SCHEDULER}, have access to NMC API ${NMC_API_ENDPOINT} "
	else
		echo "ERROR ::: NAC Scheduler with IP : ${PUB_IP_ADDR_NAC_SCHEDULER}, Does NOT have access to NMC API ${NMC_API_ENDPOINT}. Please configure access to NMC "
		exit 1
	fi
	echo "INFO ::: Completed NMC endpoint accessibility Check. !!!"

}
parse_4thArgument_for_nac_scheduler_name() {
	file="$1"
	if [ -f "$file" ]; then
		dos2unix $file
		while IFS="=" read -r key value; do
			case "$key" in
			"nac_scheduler_name") NAC_SCHEDULER_NAME="$value" ;;
			"pem_key_path") PEM_KEY_PATH="$value" ;;
			"github_organization") GITHUB_ORGANIZATION="$value" ;;
			"user_vpc_id") USER_VPC_ID="$value" ;;
			esac
		done <"$file"
	else
		SECRET_NAME="$file"
		SECRET_STRING=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AWS_REGION}" --profile "${AWS_PROFILE}")

		NAC_SCHEDULER_NAME=$(echo $SECRET_STRING | jq -r '.SecretString' | jq -r '.nac_scheduler_name')
		NMC_API_USERNAME=$(echo $SECRET_STRING  | jq -r '.SecretString' | jq -r '.nmc_api_username')
		NMC_API_PASSWORD=$(echo $SECRET_STRING  | jq -r '.SecretString' | jq -r '.nmc_api_password')
		NMC_API_ENDPOINT=$(echo $SECRET_STRING  | jq -r '.SecretString' | jq -r '.nmc_api_endpoint')
		PEM_KEY_PATH=$(echo $SECRET_STRING  | jq -r '.SecretString' | jq -r '.pem_key_path')
		GITHUB_ORGANIZATION=$(echo $SECRET_STRING  | jq -r '.SecretString' | jq -r '.github_organization')
		USER_VPC_ID=$(echo $SECRET_STRING  | jq -r '.SecretString' | jq -r '.user_vpc_id')
		echo "INFO ::: github_organization=$GITHUB_ORGANIZATION :: nac_scheduler_name=$NAC_SCHEDULER_NAME :: nmc_api_username=$NMC_API_USERNAME :: nmc_api_password=$NMC_API_PASSWORD :: nmc_api_endpoint=$NMC_API_ENDPOINT :: pem_key_path=$PEM_KEY_PATH"
	fi
}

append_nac_keys_values_to_tfvars() {
	inputFile="$1" ### Read InputFile
	outFile="$2"
	dos2unix $inputFile
	# echo "INFO ::: Append nac key-value(s) to tfvars, inputFile ::: $inputFile"
	# echo "INFO ::: Append nac key-value(s) to tfvars, outFile ::: $outFile"

	while IFS="=" read -r key value; do
		echo "$key ::: $value "
		if [ ${#key} -ne 0 ]; then
			echo "$key=$value" >>$outFile
		fi
	done <"$inputFile"
	echo "INFO ::: Append NAC key-value(s) to tfvars, ::: $outFile"
}

check_if_secret_exists() {
	USER_SECRET="$1"
	AWS_PROFILE="$2"
	AWS_REGION="$3"
	# Verify the Secret Exists
	if [[ -n $USER_SECRET ]]; then
		COMMAND=`aws secretsmanager get-secret-value --secret-id ${USER_SECRET} --profile ${AWS_PROFILE} --region ${AWS_REGION}`
		RES=$?
		if [[ $RES -eq 0 ]]; then
			### echo "INFO ::: Secret ${USER_SECRET} Exists. $RES"
			echo "Y"
		else
			### echo "ERROR ::: $RES :: Secret ${USER_SECRET} Does'nt Exist in ${AWS_REGION} region. OR, Invalid Secret name passed as 4th parameter"
			echo "N"
			# exit 0
		fi
	fi
}

validate_kvp() {
	key="$1"
	val="$2"
	if [[ $val == "" ]]; then
		echo "ERROR ::: Empty Value provided. Please provide a valid value for ${key}."
		exit 1
	else
		echo "INFO ::: Value of ${key} is ${val}"
	fi
}
validate_secret_values() {
	SECRET_NAME=$1
	SECRET_KEY=$2
	AWS_REGION=$3
	AWS_PROFILE=$4
	echo "INFO ::: Validating Secret_key ::: $SECRET_KEY in secret-id $SECRET_NAME (in region $AWS_REGION)"
	SECRET_VALUE=""
	if [ "$SECRET_KEY" == "nmc_api_username" ]; then
		SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" | jq -r '.SecretString' | jq -r '.nmc_api_username')
	elif [ "$SECRET_KEY" == "nmc_api_password" ]; then
		SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" | jq -r '.SecretString' | jq -r '.nmc_api_password')
	elif [ "$SECRET_KEY" == "nac_product_key" ]; then
		SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" | jq -r '.SecretString' | jq -r '.nac_product_key')
	elif [ "$SECRET_KEY" == "nmc_api_endpoint" ]; then
		SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" | jq -r '.SecretString' | jq -r '.nmc_api_endpoint')
	elif [ "$SECRET_KEY" == "web_access_appliance_address" ]; then
		SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" | jq -r '.SecretString' | jq -r '.web_access_appliance_address')
	elif [ "$SECRET_KEY" == "destination_bucket" ]; then
		SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" | jq -r '.SecretString' | jq -r '.destination_bucket')
	elif [ "$SECRET_KEY" == "volume_key" ]; then
		SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" | jq -r '.SecretString' | jq -r '.volume_key')
	elif [ "$SECRET_KEY" == "pem_key_path" ]; then
		SECRET_VALUE=$(aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" | jq -r '.SecretString' | jq -r '.pem_key_path')
	fi
	if [ -z "$SECRET_VALUE" ] ; then
        echo "ERROR ::: Validation FAILED as, Empty String Value passed to key $SECRET_KEY = $SECRET_VALUE in secret $SECRET_NAME."
        exit 1
	else
		if [ "$SECRET_VALUE" == "null" ] ; then
			echo "ERROR ::: Validation FAILED as, Key $SECRET_KEY does not exists in secret $SECRET_NAME." 
			exit 1
		else 
			echo "INFO ::: Validation SUCCESS, as key $SECRET_KEY has value $SECRET_VALUE in secret $SECRET_NAME."
		fi
	fi
}

parse_textfile_for_user_secret_keys_values() {
	file="$1"
	while IFS="=" read -r key value; do
		case "$key" in
		"nmc_api_username") NMC_API_USERNAME="$value" ;;
		"nmc_api_password") NMC_API_PASSWORD="$value" ;;
		"nac_product_key") NAC_PRODUCT_KEY="$value" ;;
		"nmc_api_endpoint") NMC_API_ENDPOINT="$value" ;;
		"web_access_appliance_address") WEB_ACCESS_APPLIANCE_ADDRESS="$value" ;;
		"volume_key") VOLUME_KEY="$value" ;;
		"volume_key_passphrase") VOLUME_KEY_PASSPHRASE="$value" ;;
		"destination_bucket") DESTINATION_BUCKET="$value" ;;
		"pem_key_path") PEM_KEY_PATH="$value" ;;
		"github_organization") GITHUB_ORGANIZATION="$value" ;;
		"user_vpc_id") USER_VPC_ID="$value" ;;
		esac
	done <"$file"
	if [ $GITHUB_ORGANIZATION != "" ]; then
		echo "INFO ::: Value of github_organization is $GITHUB_ORGANIZATION"	
	fi
	if [ $USER_VPC_ID != "" ]; then
		echo "INFO ::: Value of user_vpc_id is $USER_VPC_ID"	
	fi
	echo "INFO ::: Validating the user data file ${file} and the provided values"
	validate_kvp nmc_api_username "${NMC_API_USERNAME}"
	validate_kvp nmc_api_password "${NMC_API_PASSWORD}"
	validate_kvp nac_product_key "${NAC_PRODUCT_KEY}"
	validate_kvp nmc_api_endpoint "${NMC_API_ENDPOINT}"
	validate_kvp web_access_appliance_address "${WEB_ACCESS_APPLIANCE_ADDRESS}"
	validate_kvp destination_bucket "${DESTINATION_BUCKET}"
	validate_kvp pem_key_path "${PEM_KEY_PATH}"
}
create_JSON_from_Input_user_KVPfile() {
	file_name=$1
	last_line=$(wc -l <$file_name)
	current_line=0
	echo "{"
	while read line; do
		current_line=$(($current_line + 1))
		if [[ $current_line -ne $last_line ]]; then
			[ -z "$line" ] && continue
			echo $line | awk -F'=' '{ print " \""$1"\" : \""$2"\","}' | grep -iv '\"#'
		else
			echo $line | awk -F'=' '{ print " \""$1"\" : \""$2"\""}' | grep -iv '\"#'
		fi
	done <$file_name
	echo "}"
}

###########Adding Local IP to Security Group which is realted to NAC Public IP Address
add_ip_to_sec_grp() {
	NAC_SCHEDULER_IP_ADDR=$1
	echo "INFO ::: Getting Public IP of the local machine."
	echo $(curl checkip.amazonaws.com) >LOCAL_IP.txt

	LOCAL_IP=$(cat LOCAL_IP.txt)
	rm -rf LOCAL_IP.txt
	echo "INFO ::: Public IP of the local machine is ${LOCAL_IP}"
	NEW_CIDR="${LOCAL_IP}"/32
	echo "INFO ::: NEW_CIDR :- ${NEW_CIDR}"
	### Get NAC Scheduler IP
	if [ "$NAC_SCHEDULER_NAME" != "" ]; then
		SECURITY_GROUP_ID=$(aws ec2 describe-instances --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,Status:State.Name,PublicIP:PublicIpAddress,SecurityGroups:SecurityGroups[*]}" --filters "Name=tag:Name,Values='$NAC_SCHEDULER_NAME'" "Name=instance-state-name,Values=running" --region $AWS_REGION --profile "${AWS_PROFILE}" | grep -e "GroupId" | cut -d":" -f 2 | tr -d '"')
		echo $SECURITY_GROUP_ID
		echo "INFO ::: Security group of $NAC_SCHEDULER_NAME is $SECURITY_GROUP_ID"
	else
		echo "INFO ::: NAC Scheduler Instance $NAC_SCHEDULER_NAME is present .So fetching its security group . . . . . "
		SECURITY_GROUP_ID=$(aws ec2 describe-instances --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,Status:State.Name,PublicIP:PublicIpAddress,SecurityGroups:SecurityGroups[*]}" --filters "Name=tag:Name,Values='NACScheduler'" "Name=instance-state-name,Values=running" --region $AWS_REGION --profile "${AWS_PROFILE}" | grep -e "GroupId" | cut -d":" -f 2 | tr -d '"')
		echo $SECURITY_GROUP_ID
		echo "INFO ::: Security group of NAC Scheduler Instance $NAC_SCHEDULER_NAME is $SECURITY_GROUP_ID"
	fi
	status=$(aws ec2 authorize-security-group-ingress --group-id ${SECURITY_GROUP_ID} --profile "${AWS_PROFILE}" --protocol tcp --port 22 --cidr ${NEW_CIDR} 2>/dev/null)
	if [ $? -eq 0 ]; then
		echo "INFO ::: Local Computer IP $NEW_CIDR updated to inbound rule of Security Group $SECURITY_GROUP_ID"
	else
		echo "INFO ::: IP $NEW_CIDR already available in inbound rule of Security Group $SECURITY_GROUP_ID"
	fi

}

AWS_PROFILE="nasuni"
AWS_REGION=""
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
ARG_COUNT="$#"
######################## Validating AWS profile for NAC ####################################
validate_aws_profile() {
	echo "INFO ::: Validating AWS profile ${AWS_PROFILE} for NAC  . . . . . . . . . . . . . . . . !!!"

	if [[ "$(grep '^[[]profile' <~/.aws/config | awk '{print $2}' | sed 's/]$//' | grep "${AWS_PROFILE}")" == "" ]]; then
		echo "ERROR ::: AWS profile ${AWS_PROFILE} does not exists. To Create AWS PROFILE, Run cli command - aws configure "
		exit 1
	else # AWS Profile nasuni available in local machine
		AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id --profile ${AWS_PROFILE})
		AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key --profile ${AWS_PROFILE})
		AWS_REGION=`aws configure get region --profile ${AWS_PROFILE}`
	fi

	echo "INFO ::: AWS_REGION=$AWS_REGION"
	echo "INFO ::: NMC_VOLUME_NAME=$NMC_VOLUME_NAME"
	echo "INFO ::: AWS profile Validation SUCCESS !!!"
}
########################## Create CRON ############################################################
Schedule_CRON_JOB() {
	NAC_SCHEDULER_IP_ADDR=$1
	PEM="$PEM_KEY_PATH"
	check_if_pem_file_exists $PEM

	chmod 400 $PEM

	echo "INFO ::: Public IP Address:- $NAC_SCHEDULER_IP_ADDR"
	echo "ssh -i "$PEM" ubuntu@$NAC_SCHEDULER_IP_ADDR -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null"
	### Create TFVARS File for PROVISION_NAC.SH which is Used by CRON JOB - to Provision NAC Stack
	CRON_DIR_NAME="${NMC_VOLUME_NAME}_${ANALYTICS_SERVICE}"
	TFVARS_FILE_NAME="${CRON_DIR_NAME}.tfvars"
	rm -rf "$TFVARS_FILE_NAME"
	echo "aws_profile="\"$AWS_PROFILE\" >>$TFVARS_FILE_NAME
	echo "region="\"$AWS_REGION\" >>$TFVARS_FILE_NAME
	echo "volume_name="\"$NMC_VOLUME_NAME\" >>$TFVARS_FILE_NAME
	echo "user_secret="\"$USER_SECRET\" >>$TFVARS_FILE_NAME
	echo "github_organization="\"$GITHUB_ORGANIZATION\" >>$TFVARS_FILE_NAME
	if [ $ARG_COUNT -eq 5 ]; then
		echo "INFO ::: $ARG_COUNT th Argument is supplied as ::: $NAC_INPUT_KVP"
		append_nac_keys_values_to_tfvars $NAC_INPUT_KVP $TFVARS_FILE_NAME
	fi
	### Create Directory for each Volume
	ssh -i "$PEM" ubuntu@"$NAC_SCHEDULER_IP_ADDR" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "[ ! -d $CRON_DIR_NAME ] && mkdir $CRON_DIR_NAME "
	### Copy TFVARS and provision_nac.sh to NACScheduler
	scp -i "$PEM" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null provision_nac.sh "$TFVARS_FILE_NAME" ubuntu@$NAC_SCHEDULER_IP_ADDR:~/$CRON_DIR_NAME
	RES="$?"
	if [ $RES -ne 0 ]; then
		echo "ERROR ::: Failed to Copy $TFVARS_FILE_NAME to NAC_Scheduer Instance."
		exit 1
	elif [ $RES -eq 0 ]; then
		echo "INFO ::: $TFVARS_FILE_NAME Uploaded Successfully to NAC_Scheduer Instance."
	fi
	rm -rf $TFVARS_FILE_NAME
	#dos2unix command execute
	ssh -i "$PEM" ubuntu@"$NAC_SCHEDULER_IP_ADDR" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "dos2unix ~/$CRON_DIR_NAME/provision_nac.sh"
	### Check If CRON JOB is running for a specific VOLUME_NAME
	CRON_VOL=$(ssh -i "$PEM" -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null ubuntu@"$NAC_SCHEDULER_IP_ADDR" "crontab -l |grep /home/ubuntu/$CRON_DIR_NAME/$TFVARS_FILE_NAME")
	if [ "$CRON_VOL" != "" ]; then
		### DO Nothing. CRON JOB takes care of NAC Provisioning
		echo "INFO ::: crontab does not require volume entry.As it is already present.:::::"
	else
		### Set up a new CRON JOB for NAC Provisioning

		echo "INFO ::: Setting CRON JOB for $CRON_DIR_NAME as it is not present"
		ssh -i "$PEM" ubuntu@$NAC_SCHEDULER_IP_ADDR -oStrictHostKeyChecking=no -oUserKnownHostsFile=/dev/null "(crontab -l ; echo '*/$FREQUENCY * * * * sh ~/$CRON_DIR_NAME/provision_nac.sh  ~/$CRON_DIR_NAME/$TFVARS_FILE_NAME >> ~/$CRON_DIR_NAME/CRON_log-$CRON_DIR_NAME-$DATE_WITH_TIME.log') | sort - | uniq - | crontab -"
		if [ $? -eq 0 ]; then
			echo "INFO ::: CRON JOB Scheduled for NMC VOLUME and Service :: $CRON_DIR_NAME"
			exit 0
		else
			echo "ERROR ::: FAILED to Schedule CRON JOB for NMC VOLUME and Service :: $CRON_DIR_NAME"
			exit 1
		fi
	fi

}
##################################### START - SCRIPT Execution HERE ##################################################

if [ $# -eq 0 ]; then
	echo "ERROR ::: No argument(s) supplied. This Script Takes 4 Mandatory Arguments 1) NMC Volume_Name, 2) Service, 3) Frequency and 4) User Secret(either Existing Secret Name Or Secret KVPs in a text file)"
	exit 1
elif [ $# -lt 4 ]; then
	echo "ERROR ::: $# argument(s) supplied. This Script Takes 4 Mandatory Arguments 1) NMC Volume_Name, 2) Service, 3) Frequency and 4) User Secret(either Existing Secret Name Or Secret KVPs in a text file)"
	exit 1
fi
#################### Validate Arguments Passed to NAC_Scheduler.sh ####################
NMC_VOLUME_NAME="$1"   ### 1st argument  ::: NMC_VOLUME_NAME
ANALYTICS_SERVICE="$2" ### 2nd argument  ::: ANALYTICS_SERVICE
FREQUENCY="$3"         ### 3rd argument  ::: FREQUENCY
FOURTH_ARG="$4"        ### 4th argument  ::: User Secret a KVP file Or an existing Secret
NAC_INPUT_KVP="$5"     ### 5th argument  ::: User defined KVP file for passing arguments to NAC
echo "INFO ::: Validating Arguments Passed to NAC_Scheduler.sh"
if [ "${#NMC_VOLUME_NAME}" -lt 3 ]; then
	echo "ERROR ::: Something went wrong. Please re-check 1st argument and provide a valid NMC Volume Name."
	exit 1
fi
if [[ "${#ANALYTICS_SERVICE}" -lt 2 ]]; then
	echo "INFO ::: The length of Service name provided as 2nd argument is too small, So, It will consider ES as the default Analytics Service."
	ANALYTICS_SERVICE="ES" # ElasticSearch Service as default
fi
if [[ "${#FREQUENCY}" -lt 2 ]]; then
	echo "ERROR ::: Mandatory 3rd argument is invalid"
	exit 1
else
	REX="^[0-9]+([.][0-9]+)?$"
	if ! [[ $FREQUENCY =~ $REX ]]; then
		echo "ERROR ::: the 3rd Argument is Not a number" >&2
		exit 1
	fi
fi

### Validate aws_profile
validate_aws_profile
########## Check If fourth argument is provided
USER_SECRET_EXISTS="N"
if [[ -n "$FOURTH_ARG" ]]; then
	### Check If fourth argument is a file
	if [ -f "$FOURTH_ARG" ]; then
		echo "INFO ::: Fourth argument is a File ${FOURTH_ARG}"

		### Parse the user data - KVP
		parse_textfile_for_user_secret_keys_values "$FOURTH_ARG"
		### Validate the user data file and the provided values
		check_if_pem_file_exists $PEM_KEY_PATH
		### nac_scheduler_name   - Get the value -- If its not null / "" then NAC_SCHEDULER_NAME = ${nac_scheduler_name}
		create_JSON_from_Input_user_KVPfile $FOURTH_ARG >user_creds_"${NMC_VOLUME_NAME}"_"${ANALYTICS_SERVICE}".json
		### Formation of User Secret Name
		USER_SECRET="prod/nac/admin/$NMC_VOLUME_NAME/$ANALYTICS_SERVICE"
		### Verify the Secret Exists
		USER_SECRET_EXISTS=$(check_if_secret_exists $USER_SECRET $AWS_PROFILE $AWS_REGION)
		echo "INFO ::: USER_SECRET_EXISTS ::: $USER_SECRET_EXISTS "
		if [ "$USER_SECRET_EXISTS" != "N" ]; then
			echo "INFO ::: Fourth argument is a File && the User Secret exists ==> User wants to Update the Secret Values"
			### Update Secret
			echo "INFO ::: Update Secret $USER_SECRET "
			### Update Secret
			aws secretsmanager update-secret --secret-id "${USER_SECRET}" \
			--secret-string file://user_creds_"${NMC_VOLUME_NAME}"_"${ANALYTICS_SERVICE}".json \
			--region "${AWS_REGION}" --profile "${AWS_PROFILE}"
			RES="$?"
			if [ $RES -ne 0 ]; then
				echo "INFO ::: $RES Failed to Update Secret $USER_SECRET."
				exit 1
			elif [ $RES -eq 0 ]; then
				echo "INFO ::: Secret $USER_SECRET Updated SUCCESSFULLY"
			fi
		else
			## Fourth argument is a File && the User Secret Doesn't exist ==> User wants to Create a new Secret
			### Create Secret
			echo "INFO ::: Create Secret $USER_SECRET"
			aws secretsmanager create-secret --name "${USER_SECRET}" \
			--description "Preserving User specific data/secrets to be used for NAC Scheduling" \
			--secret-string file://user_creds_"${NMC_VOLUME_NAME}"_"${ANALYTICS_SERVICE}".json \
			--region "${AWS_REGION}" --profile "${AWS_PROFILE}"
			RES="$?"
			if [ $RES -ne 0 ]; then
				echo "ERROR ::: $RES Failed to Create Secret $USER_SECRET as, its already exists."
				exit 1
			elif [ $RES -eq 0 ]; then
				echo "INFO ::: Secret $USER_SECRET Created"
			fi
		fi
		rm -rf *"${NMC_VOLUME_NAME}"_"${ANALYTICS_SERVICE}".json
	else ####  Fourth Argument is passed as User Secret Name
		echo "INFO ::: Fourth Argument $FOURTH_ARG is passed as User Secret Name"
		USER_SECRET="$FOURTH_ARG"
		
		### Verify the Secret Exists
		USER_SECRET_EXISTS=$(check_if_secret_exists $USER_SECRET ${AWS_PROFILE} ${AWS_REGION}) # | jq -r .Name)
		echo "INFO ::: User secret Exists:: $USER_SECRET_EXISTS"
		# if [ "${#USER_SECRET_EXISTS}" -gt 0 ]; then
		if [ "$USER_SECRET_EXISTS" == "Y" ]; then
			### Validate Keys in the Secret
			echo "INFO ::: Check if all Keys are provided"
			validate_secret_values "$USER_SECRET" nmc_api_username "$AWS_REGION" "$AWS_PROFILE"
			validate_secret_values "$USER_SECRET" nmc_api_password "$AWS_REGION" "$AWS_PROFILE"
			validate_secret_values "$USER_SECRET" nac_product_key "$AWS_REGION" "$AWS_PROFILE"
			validate_secret_values "$USER_SECRET" nmc_api_endpoint "$AWS_REGION" "$AWS_PROFILE"
			validate_secret_values "$USER_SECRET" web_access_appliance_address "$AWS_REGION" "$AWS_PROFILE"
			validate_secret_values "$USER_SECRET" destination_bucket "$AWS_REGION" "$AWS_PROFILE"
			validate_secret_values "$USER_SECRET" volume_key "$AWS_REGION" "$AWS_PROFILE"
			validate_secret_values "$USER_SECRET" pem_key_path "$AWS_REGION" "$AWS_PROFILE"
			echo "INFO ::: Validation SUCCESS for all mandatory Secret-Keys !!!" 
		fi
	fi
else
	echo "INFO ::: Fourth argument is NOT provided, So, It will consider prod/nac/admin as the default user secret."
fi

echo "INFO ::: Get IP Address of NAC Scheduler Instance"
######################  NAC Scheduler Instance is Available ##############################

NAC_SCHEDULER_NAME=""
# parse_textfile_for_nac_scheduler_name "$FOURTH_ARG"
parse_4thArgument_for_nac_scheduler_name "$FOURTH_ARG"
# echo INFO ::: USER_VPC_ID = $USER_VPC_ID
if [ "$USER_VPC_ID" == "" ] || [ "$USER_VPC_ID" == "null" ]; then
	echo "INFO ::: user_vpc_id not provided in the user Secret, Provisioning will be done in the Default VPC"  
# elif [ "$USER_VPC_ID" == "null" ]; then
	# echo "INFO ::: user_vpc_id not provided in the user Secret, Provisioning will be done in the Default VPC"  
else
	echo "INFO ::: user_vpc_id provided in the user Secret, VPC_ID=$USER_VPC_ID"  
	check_if_vpc_exists $USER_VPC_ID
fi
echo "INFO ::: nac_scheduler_name = $NAC_SCHEDULER_NAME "
if [ "$NAC_SCHEDULER_NAME" != "" ]; then
	### User has provided the NACScheduler Name as Key-Value from 4th Argument
	PUB_IP_ADDR_NAC_SCHEDULER=$(aws ec2 describe-instances --query "Reservations[*].Instances[*].{Name:Tags[?Key=='Name']|[0].Value,Status:State.Name,PublicIP:PublicIpAddress}" --filters "Name=tag:Name,Values='$NAC_SCHEDULER_NAME'" "Name=instance-state-name,Values=running" --region "${AWS_REGION}" --profile ${AWS_PROFILE}| grep -e "PublicIP" | cut -d":" -f 2 | tr -d '"' | tr -d ' ')
else
	PUB_IP_ADDR_NAC_SCHEDULER=$(aws ec2 describe-instances --query "Reservations[*].Instances[*].{Name:Tags[?Key=='Name']|[0].Value,Status:State.Name,PublicIP:PublicIpAddress}" --filters "Name=tag:Name,Values='NACScheduler'" "Name=instance-state-name,Values=running" --region "${AWS_REGION}" --profile ${AWS_PROFILE}| grep -e "PublicIP" | cut -d":" -f 2 | tr -d '"' | tr -d ' ')
fi
echo "INFO ::: PUB_IP_ADDR_NAC_SCHEDULER ::: ${PUB_IP_ADDR_NAC_SCHEDULER}"
if [ "$PUB_IP_ADDR_NAC_SCHEDULER" != "" ]; then
	echo "INFO ::: NAC Scheduler Instance is Available. IP Address: $PUB_IP_ADDR_NAC_SCHEDULER"
	### Call this function to add Local public IP to Security group of NAC_SCHEDULER IP
	add_ip_to_sec_grp $PUB_IP_ADDR_NAC_SCHEDULER $NAC_SCHEDULER_NAME
	### nmc endpoint accessibility $NAC_SCHEDULER_NAME $PUB_IP_ADDR_NAC_SCHEDULER
	nmc_endpoint_accessibility  $NAC_SCHEDULER_NAME $PUB_IP_ADDR_NAC_SCHEDULER $NMC_API_ENDPOINT $NMC_API_USERNAME $NMC_API_PASSWORD #458
	Schedule_CRON_JOB $PUB_IP_ADDR_NAC_SCHEDULER

###################### NAC Scheduler EC2 Instance is NOT Available ##############################
else
	## "NAC Scheduler is not present. Creating new EC2 machine."
	echo "INFO ::: NAC Scheduler Instance is not present. Creating new EC2 machine."
	########## Download NAC Scheduler Instance Provisioning Code from GitHub ##########
	### GITHUB_ORGANIZATION defaults to nasuni-labs
	REPO_FOLDER="nasuni-analyticsconnector-manager"
	validate_github $GITHUB_ORGANIZATION $REPO_FOLDER 
	GIT_REPO_NAME=$(echo ${GIT_REPO} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
	echo "INFO ::: Begin - Git Clone to ${GIT_REPO}"
	echo "INFO ::: $GIT_REPO"
	echo "INFO ::: GIT_REPO_NAME - $GIT_REPO_NAME"
	pwd
	# ls
	rm -rf "${GIT_REPO_NAME}"
	COMMAND="git clone -b main ${GIT_REPO}"
	$COMMAND
	RESULT=$?
	if [ $RESULT -eq 0 ]; then
		echo "INFO ::: git clone SUCCESS for repo ::: $GIT_REPO_NAME"
		cd "${GIT_REPO_NAME}"
	elif [ $RESULT -eq 128 ]; then
		cd "${GIT_REPO_NAME}"
		echo "$GIT_REPO_NAME"
		COMMAND="git pull origin main"
		$COMMAND
	fi
	### Download Provisioning Code from GitHub completed
	echo "INFO ::: NAC Scheduler EC2 provisioning ::: BEGIN - Executing ::: Terraform init . . . . . . . . "
	COMMAND="terraform init"
	$COMMAND
	echo "INFO ::: NAC Scheduler EC2 provisioning ::: FINISH - Executing ::: Terraform init."
	echo "INFO ::: NAC Scheduler EC2 provisioning ::: BEGIN - Executing ::: Terraform apply . . . . . . . . . . . . . . . . . . ."
	### Create .tfvars file to be used by the NACScheduler Instance Provisioning
	pwd
	TFVARS_NAC_SCHEDULER="NACScheduler.tfvars"
	rm -rf "$TFVARS_NAC_SCHEDULER"
    AWS_KEY=$(echo ${PEM_KEY_PATH} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
	echo $AWS_KEY
	PEM="$AWS_KEY.pem"
	### Copy the Pem Key from provided path to current folder
	cp $PEM_KEY_PATH ./
	chmod 400 $PEM
	echo "aws_profile="\"$AWS_PROFILE\" >>$TFVARS_NAC_SCHEDULER
	echo "region="\"$AWS_REGION\" >>$TFVARS_NAC_SCHEDULER
	if [[ "$NAC_SCHEDULER_NAME" != "" ]]; then
		echo "nac_scheduler_name="\"$NAC_SCHEDULER_NAME\" >>$TFVARS_NAC_SCHEDULER
		### Create entries about the Pem Key in the TFVARS File
		echo "pem_key_file="\"$PEM\" >>$TFVARS_NAC_SCHEDULER
		echo "aws_key="\"$AWS_KEY\" >>$TFVARS_NAC_SCHEDULER
	fi
	echo "github_organization="\"$GITHUB_ORGANIZATION\" >>$TFVARS_NAC_SCHEDULER
	if [[ "$USER_VPC_ID" != "" ]]; then
		echo "user_vpc_id="\"$USER_VPC_ID\" >>$TFVARS_NAC_SCHEDULER
	fi
	dos2unix $TFVARS_NAC_SCHEDULER
	COMMAND="terraform apply -var-file=$TFVARS_NAC_SCHEDULER -auto-approve"
	$COMMAND
	if [ $? -eq 0 ]; then
		echo "INFO ::: NAC Scheduler EC2 provisioning ::: FINISH - Executing ::: Terraform apply ::: SUCCESS."
	else
		echo "ERROR ::: NAC Scheduler EC2 provisioning ::: FINISH - Executing ::: Terraform apply ::: FAILED."
		exit 1
	fi
	ip=$(cat NACScheduler_IP.txt)
	NAC_SCHEDULER_IP_ADDR=$ip
	echo 'INFO ::: New pubilc IP just created:-'$ip
	pwd
	cd ../
	pwd
	## Call this function to add Local public IP to Security group of NAC_SCHEDULER IP
	add_ip_to_sec_grp ${NAC_SCHEDULER_IP_ADDR}
	## nmc endpoint accessibility $NAC_SCHEDULER_NAME $PUB_IP_ADDR_NAC_SCHEDULER
	nmc_endpoint_accessibility  $NAC_SCHEDULER_NAME ${NAC_SCHEDULER_IP_ADDR} $NMC_API_ENDPOINT $NMC_API_USERNAME $NMC_API_PASSWORD #458
	Schedule_CRON_JOB $NAC_SCHEDULER_IP_ADDR
	## Setup_Search_Lambda
	## Setup_Search_UI

fi

END=$(date +%s)
secs=$((END - START))
DIFF=$(printf '%02dh:%02dm:%02ds\n' $((secs / 3600)) $((secs % 3600 / 60)) $((secs % 60)))
echo "INFO ::: Total execution Time ::: $DIFF"
#exit 0
