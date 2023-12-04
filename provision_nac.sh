#!/bin/bash
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
#############################################################################################
#### This Script Targets NAC Deployment from any Linux Box
#### Prequisites:
####       1- Software need to be Installed:
####             a- AWS CLI V2
####             b- Python 3
####             c- curl
####             d- git
####             e- jq
####             f- wget
####             e- Terraform V 1.0.7
####       2- AWS User Profile should be configured
####             a- If not configured run the command as below and provide correct values:
####                  aws configure --profile nasuni
####       3- NMC Volume
####       5- User Specific AWS UserSecret
####             a- User need to provide/Update valid values for below keys:
####
#############################################################################################
set -e
DATE_WITH_TIME=$(date "+%Y%m%d-%H%M%S")
LOG_FILE=provision_nac_$DATE_WITH_TIME.log
(
START=$(date +%s)
{
	TFVARS_FILE=$1
	read_TFVARS() {
		file="$TFVARS_FILE"
		while IFS="=" read -r key value; do
			case "$key" in
				"aws_profile") AWS_PROFILE="$value" ;;
				"region") AWS_REGION="$value" ;;
				"volume_name") NMC_VOLUME_NAME="$value" ;;
				"github_organization") GITHUB_ORGANIZATION="$value" ;;
				"git_branch") GIT_BRANCH="$value" ;;
				"user_vpc_id") USER_VPC_ID="$value" ;;
				"user_subnet_id") USER_SUBNET_ID="$value" ;;
				"user_secret") USER_SECRETFROM_TFVARS="$value" ;;
				"use_private_ip") USE_PRIVATE_IP="$value" ;;
				"frequency") FREQUENCY="$value" ;;
				"nac_scheduler_name") NAC_SCHEDULER_NAME="$value" ;;
				"nac_es_securitygroup") NAC_ES_SECURITYGROUP="$value" ;;
				"service_name") SERVICE_NAME="$value" ;;

			esac
		done < "$file"
	}

generate_tracker_json_kendra(){
	echo "INFO ::: Updating TRACKER JSON ... "
	INDEX_NAME=$1
	INDEX_ID=$2
	DEFAULT_URL=$3
	FREQUENCY=$4
	USER_SECRET=$5
	CREATED_ON=$6
	TRACKER_NMC_VOLUME_NAME=$7
	ANALYTICS_SERVICE=$8
	MOST_RECENT_RUN=${9}
	CURRENT_STATE=${10}
	LATEST_TOC_HANDLE_PROCESSED=${11}
	NAC_SCHEDULER_NAME=$(echo "${12}" | tr -d '"')
	KENDRA_URL=${13}
	#sudo chmod -R 777 /home/ubuntu/kendra_tracker_json_folder/
	sudo chmod -R 777 /var/www/Tracker_UI/docs/

	echo "INFO ::: NAC_SCHEDULER_NAME $NAC_SCHEDULER_NAME generate_tracker_json_kendra"
	
	python3 /var/www/Tracker_UI/docs/tracker_json_kendra.py $INDEX_NAME $INDEX_ID $DEFAULT_URL $FREQUENCY $USER_SECRET  $CREATED_ON $TRACKER_NMC_VOLUME_NAME $ANALYTICS_SERVICE $MOST_RECENT_RUN $CURRENT_STATE $LATEST_TOC_HANDLE_PROCESSED $NAC_SCHEDULER_NAME $KENDRA_URL
	echo "INFO ::: TRACKER JSON  Updated"

}

generate_tracker_json(){
	echo "INFO ::: Updating TRACKER JSON ... "
	OS_URL=$1
	KIBANA_URL=$2
	DEFAULT_URL=$3
	FREQUENCY=$4
	USER_SECRET=$5
	CREATED_BY=$6
	CREATED_ON=$7
	TRACKER_NMC_VOLUME_NAME=$8
	ANALYTICS_SERVICE=$9
	MOST_RECENT_RUN=${10}
	CURRENT_STATE=${11}
	LATEST_TOC_HANDLE_PROCESSED=${12}
	NAC_SCHEDULER_NAME=$(echo "${13}" | tr -d '"')
	sudo chmod -R 777 /var/www/Tracker_UI/docs/
	python3 /var/www/Tracker_UI/docs/tracker_json.py $OS_URL $KIBANA_URL $DEFAULT_URL $FREQUENCY $USER_SECRET $CREATED_BY $CREATED_ON $TRACKER_NMC_VOLUME_NAME $ANALYTICS_SERVICE $MOST_RECENT_RUN $CURRENT_STATE $LATEST_TOC_HANDLE_PROCESSED $NAC_SCHEDULER_NAME
	echo "INFO ::: TRACKER JSON  Updated"
}


check_if_secret_exists() {
	USER_SECRET="$1"
	AWS_PROFILE="$2"
	AWS_REGION="$3"
	# Verify the Secret Exists
	if [[ -n $USER_SECRET ]]; then
		COMMAND=$(aws secretsmanager get-secret-value --secret-id ${USER_SECRET} --profile ${AWS_PROFILE} --region ${AWS_REGION})
		#$COMMAND ###SSA
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

############################### START - Execution ############################################

read_TFVARS "$TFVARS_FILE"

AWS_PROFILE=$(echo "$AWS_PROFILE" | tr -d '"')
AWS_REGION=$(echo "$AWS_REGION" | tr -d '"')
NMC_VOLUME_NAME=$(echo "$NMC_VOLUME_NAME" | tr -d '"')
GIT_BRANCH=$(echo "$GIT_BRANCH" | tr -d '"')
GITHUB_ORGANIZATION=$(echo "$GITHUB_ORGANIZATION" | tr -d '"')
NAC_SCHEDULER_NAME=$(echo "$NAC_SCHEDULER_NAME" | tr -d '"')
NAC_ES_SECURITYGROUP=$(echo "$NAC_ES_SECURITYGROUP" | tr -d '"')
SERVICE_NAME=$(echo "$SERVICE_NAME" | tr -d '"')

echo NAC_SCHDULER_NAME $NAC_SCHEDULER_NAME
echo SERVICE_NAME $SERVICE_NAME


if [ "${SERVICE_NAME^^}" = "ES" ] || [ "${SERVICE_NAME^^}" = "OS" ]; then
	OS_ADMIIN_SECRET="nasuni-labs-os-admin"
elif [ "${SERVICE_NAME^^}" = "KENDRA" ];then
	OS_ADMIIN_SECRET="nasuni-labs-kendra-admin"
else
	OS_ADMIIN_SECRET="export-only"
fi
##################################### START TRACKER JSON Creation ###################################################################

echo "INFO ::: NAC_Activity : Starting Export Process"
KENDRA_URL=""
###Req generate_tracker_json.py start put it in if
if [ "${SERVICE_NAME^^}" = "ES" ] || [ "${SERVICE_NAME^^}" = "OS" ]; then
	echo "INFO ::: Initializing Export to Destination Bucket - OpenSearch_Flow . . . .   "
	OS_URL=$(aws secretsmanager get-secret-value --secret-id $OS_ADMIIN_SECRET --region "${AWS_REGION}" --profile "${AWS_PROFILE}" | jq -r '.SecretString' | jq -r '.nac_es_url')
	KIBANA_URL=$(aws secretsmanager get-secret-value --secret-id $OS_ADMIIN_SECRET --region "${AWS_REGION}" --profile "${AWS_PROFILE}" | jq -r '.SecretString' | jq -r '.nac_kibana_url')
	DEFAULT_URL="/search/index.html"
	USER_SECRET=$OS_ADMIIN_SECRET
	CREATED_BY=$(aws secretsmanager get-secret-value --secret-id $OS_ADMIIN_SECRET --region "${AWS_REGION}" --profile "${AWS_PROFILE}" | jq -r '.SecretString' | jq -r '.nac_es_admin_user')
	CREATED_ON=$(date "+%Y%m%d-%H%M%S")
	TRACKER_NMC_VOLUME_NAME=$NMC_VOLUME_NAME
	ANALYTICS_SERVICE=(${TFVARS_FILE//_/ })
	ANALYTICS_SERVICE=$(echo "${ANALYTICS_SERVICE[-1]}" | cut -d'.' -f 1)
	MOST_RECENT_RUN=$(date "+%Y:%m:%d-%H:%M:%S")
	CURRENT_STATE="Export-In-progress"
	LATEST_TOC_HANDLE_PROCESSED="-"
	echo "INFO ::: Nach sheduler name: " ${NAC_SCHEDULER_NAME}
	JSON_FILE_PATH="/var/www/Tracker_UI/docs/${NAC_SCHEDULER_NAME}_tracker_ES.json"
	echo "INFO ::: JSON_FILE_PATH:" $JSON_FILE_PATH
	if [ -f "$JSON_FILE_PATH" ] ; then
		TRACEPATH="${NMC_VOLUME_NAME}_${ANALYTICS_SERVICE}"
		TRACKER_JSON=$(cat $JSON_FILE_PATH)
		echo "INFO ::: Tracker json" $TRACKER_JSON
		LATEST_TOC_HANDLE_PROCESSED=$(echo $TRACKER_JSON | jq -r .INTEGRATIONS.\"$TRACEPATH\"._NAC_activity.latest_toc_handle_processed)
		#if [ -z "$LATEST_TOC_HANDLE_PROCESSED" -a "$LATEST_TOC_HANDLE_PROCESSED" == " " ]; then	
		if [ -z "$LATEST_TOC_HANDLE_PROCESSED" ] || [ "$LATEST_TOC_HANDLE_PROCESSED" == " " ] || [ "$LATEST_TOC_HANDLE_PROCESSED" == "null" ]; then	
 			LATEST_TOC_HANDLE_PROCESSED="-"
		fi
		echo "INFO LATEST_TOC_HANDLE PROCESSED"  $LATEST_TOC_HANDLE_PROCESSED
	fi

	generate_tracker_json $OS_URL $KIBANA_URL $DEFAULT_URL $FREQUENCY $USER_SECRET $CREATED_BY $CREATED_ON $TRACKER_NMC_VOLUME_NAME $ANALYTICS_SERVICE $MOST_RECENT_RUN $CURRENT_STATE $LATEST_TOC_HANDLE_PROCESSED $NAC_SCHEDULER_NAME
elif [ "${SERVICE_NAME^^}" = "EXP" ]; then
	echo "INFO ::: Initializing Export Only to Destination Bucket - Export Only.   "
	JSON_FILE_PATH="~/${NAC_SCHEDULER_NAME}_tracker_ExportOny.json"

	echo "INFO ::: JSON_FILE_PATH:" $JSON_FILE_PATH
else
	echo "INFO ::: Initializing Export to Destination Bucket - Kendra_flow . . . .  "
	INDEX_NAME=$(aws secretsmanager get-secret-value --secret-id $OS_ADMIIN_SECRET --region "${AWS_REGION}" --profile "${AWS_PROFILE}" | jq -r '.SecretString' | jq -r '.index_name')
	INDEX_ID=$(aws secretsmanager get-secret-value --secret-id $OS_ADMIIN_SECRET --region "${AWS_REGION}" --profile "${AWS_PROFILE}" | jq -r '.SecretString' | jq -r '.index_id')
	DEFAULT_URL="/search/index.html"
	USER_SECRET=$OS_ADMIIN_SECRET
	CREATED_ON=$(date "+%Y%m%d-%H%M%S")
	TRACKER_NMC_VOLUME_NAME=$NMC_VOLUME_NAME
	ANALYTICS_SERVICE=(${TFVARS_FILE//_/ })
	ANALYTICS_SERVICE=$(echo "${ANALYTICS_SERVICE[-1]}" | cut -d'.' -f 1)
	MOST_RECENT_RUN=$(date "+%Y:%m:%d-%H:%M:%S")
	CURRENT_STATE="Export-In-progress"
	LATEST_TOC_HANDLE_PROCESSED="-"
	echo "INFO ::: Nach sheduler name: " ${NAC_SCHEDULER_NAME}
	#JSON_FILE_PATH="/home/ubuntu/kendra_tracker_json_folder/${NAC_SCHEDULER_NAME}_tracker_KENDRA.json"
	JSON_FILE_PATH="/var/www/Tracker_UI/docs/${NAC_SCHEDULER_NAME}_tracker_KENDRA.json"

	echo "INFO ::: JSON_FILE_PATH:" $JSON_FILE_PATH
	KENDRA_URL="https://$AWS_REGION.console.aws.amazon.com/kendra/home?region=$AWS_REGION#indexes/$INDEX_ID/search"
	if [ -f "$JSON_FILE_PATH" ] ; then 
		TRACEPATH="${NMC_VOLUME_NAME}_${ANALYTICS_SERVICE}"
		TRACKER_JSON=$(cat $JSON_FILE_PATH)
		echo "INFO ::: Tracker json" $TRACKER_JSON
		LATEST_TOC_HANDLE_PROCESSED=$(echo $TRACKER_JSON | jq -r .INTEGRATIONS.\"$TRACEPATH\"._NAC_activity.latest_toc_handle_processed)
		#if [ -z "$LATEST_TOC_HANDLE_PROCESSED" -a "$LATEST_TOC_HANDLE_PROCESSED" == " " ]; then	
		if [ -z "$LATEST_TOC_HANDLE_PROCESSED" ] || [ "$LATEST_TOC_HANDLE_PROCESSED" == " " ] || [ "$LATEST_TOC_HANDLE_PROCESSED" == "null" ]; then	
 			LATEST_TOC_HANDLE_PROCESSED="-"
		fi
		echo "INFO ::: LATEST_TOC_HANDLE PROCESSED"  $LATEST_TOC_HANDLE_PROCESSED
	fi
	echo "INFO ::: INDEX_ID :: $INDEX_ID"
	generate_tracker_json_kendra $INDEX_NAME $INDEX_ID $DEFAULT_URL $FREQUENCY $USER_SECRET  $CREATED_ON $TRACKER_NMC_VOLUME_NAME $ANALYTICS_SERVICE $MOST_RECENT_RUN $CURRENT_STATE $LATEST_TOC_HANDLE_PROCESSED $NAC_SCHEDULER_NAME $KENDRA_URL
	
fi
pwd

echo "INFO ::: current user :-"`whoami`
########## Download NAC Provisioning Code from GitHub ##########
### GITHUB_ORGANIZATION defaults to nasuni-labs
### REPO_FOLDER="nasuni-analyticsconnector-opensearch"
if [ "${SERVICE_NAME^^}" = "ES" ] || [ "${SERVICE_NAME^^}" = "OS" ]; then 
	if [ "$USE_PRIVATE_IP" == "N" ] || [ "$USE_PRIVATE_IP" == null ] || [ "$USE_PRIVATE_IP" == "" ]; then
        	REPO_FOLDER="nasuni-analyticsconnector-opensearch-public"
	else
	        REPO_FOLDER="nasuni-analyticsconnector-opensearch"
	fi
elif [ "${SERVICE_NAME^^}" = "EXP" ];then
	REPO_FOLDER="nasuni-analyticsconnector-exportonly"
else
	REPO_FOLDER="nasuni-analyticsconnector-kendra"
fi
echo "INFO ::: REPO_FOLDER - $REPO_FOLDER !!!"
validate_github $GITHUB_ORGANIZATION $REPO_FOLDER
########################### Git Clone : NAC Provisioning Repo ###############################################################
echo "INFO ::: BEGIN - Git Clone !!!"
### Download Provisioning Code from GitHub
GIT_REPO_NAME=$(echo ${GIT_REPO} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
echo "INFO ::: GIT_REPO : $GIT_REPO"
echo "INFO ::: GIT_REPO_NAME : $GIT_REPO_NAME"
pwd
echo "INFO ::: Deleting the Directory: ${GIT_REPO_NAME}"
rm -rf "${GIT_REPO_NAME}"
pwd
COMMAND="git clone -b $GIT_BRANCH $GIT_REPO"
$COMMAND
RESULT=$?
if [ $RESULT -eq 0 ]; then
	echo "INFO ::: FINISH ::: GIT clone SUCCESS for repo ::: $GIT_REPO_NAME"
else
	echo "ERROR ::: FINISH ::: GIT Clone FAILED for repo ::: $GIT_REPO_NAME"
	echo "ERROR ::: Unable to Proceed with NAC Provisioning."
	exit 1
fi
pwd
########################### Completed - Git Clone  ###############################################################
echo "INFO ::: Copy TFVARS file to ${GIT_REPO_NAME}/${TFVARS_FILE}"
cp "${TFVARS_FILE}" "${GIT_REPO_NAME}"/
cd "${GIT_REPO_NAME}"
chmod 755 $(pwd)/*
NMC_VOLUME_NAME_1=$(echo $NMC_VOLUME_NAME|tr -d '"')
ANALYTICS_SERVICE_1=$(echo $ANALYTICS_SERVICE|tr -d '"')
NAC_SCHEDULER_NAME_1=$(echo $NAC_SCHEDULER_NAME|tr -d '"')
USER_SECRETFROM_TFVARS_1=$(echo $USER_SECRETFROM_TFVARS|tr -d '"')
RND_IN=$(( $RANDOM % 1000000 )); 

###JSON_FILE_PATH="$HOME/TrackerJson/${NAC_SCHEDULER_NAME_1}_tracker.json"

######Req for generate_tracker_json for kendra if condition
if [ "${SERVICE_NAME^^}" = "ES" ] || [ "${SERVICE_NAME^^}" = "OS" ]; then
	echo "INFO ::: tracker_json for OpenSearch_flow $JSON_FILE_PATH "
	LATEST_TOC_HANDLE=""
	if [ -f "$JSON_FILE_PATH" ] ; then
		TRACEPATH="${NMC_VOLUME_NAME_1}_${ANALYTICS_SERVICE_1}"
		echo "INFO ::: TracePath of Tracker Json : $TRACEPATH"
		TRACKER_JSON=$(cat $JSON_FILE_PATH)
		echo "INFO ::: Tracker json" $TRACKER_JSON
		LATEST_TOC_HANDLE=$(echo $TRACKER_JSON | jq -r .INTEGRATIONS.\"$TRACEPATH\"._NAC_activity.latest_toc_handle_processed)
		if [ "$LATEST_TOC_HANDLE" =  "-" ] ; then
			LATEST_TOC_HANDLE=""
		fi
		echo "INFO ::: LATEST_TOC_HANDLE: $LATEST_TOC_HANDLE"
	else
		LATEST_TOC_HANDLE=""
		echo "ERROR ::: Tracker JSON folder Not present"
	fi

	echo "INFO ::: LATEST_TOC_HANDLE" $LATEST_TOC_HANDLE
	LATEST_TOC_HANDLE_PROCESSED=$LATEST_TOC_HANDLE

	FOLDER_PATH=`pwd`

	###appending latest_toc_handle_processed to TFVARS_FILE
	echo "PrevUniFSTOCHandle="\"$LATEST_TOC_HANDLE\" >>$FOLDER_PATH/$TFVARS_FILE
elif [ "${SERVICE_NAME^^}" = "EXP" ];then 
	echo "INFO ::: LATEST_TOC_HANDLE" $LATEST_TOC_HANDLE
	# LATEST_TOC_HANDLE=""

	TFVARS_FILE="${NMC_VOLUME_NAME}_${SERVICE_NAME}.tfvars"
	pwd
	echo "RndIN="\"$RND_IN\" >>$TFVARS_FILE

	python3 $(pwd)/fetch_volume_data_from_nmc_api.py $USER_SECRETFROM_TFVARS_1 $AWS_REGION $NMC_VOLUME_NAME_1 $RND_IN && echo nasuni-labs-internal-$RND_IN > nac_uniqui_id.txt

	FOLDER_PATH=`pwd`
	echo "PrevUniFSTOCHandle="\"$LATEST_TOC_HANDLE\" >$FOLDER_PATH/PreviousTocHandle.txt
	echo "PrevUniFSTOCHandle="\"$LATEST_TOC_HANDLE\" >>$FOLDER_PATH/$TFVARS_FILE
elif [ "${SERVICE_NAME^^}" = "KENDRA" ];then 
	echo "INFO ::: Kendra stuff"
	echo "INFO ::: tracker_json for Kendra_flow $JSON_FILE_PATH "
	LATEST_TOC_HANDLE=""
	if [ -f "$JSON_FILE_PATH" ] ; then
		TRACEPATH="${NMC_VOLUME_NAME_1}_${ANALYTICS_SERVICE_1}"
		echo $TRACEPATH
		TRACKER_JSON=$(cat $JSON_FILE_PATH)
		echo "INFO ::: Tracker json" $TRACKER_JSON
		LATEST_TOC_HANDLE=$(echo $TRACKER_JSON | jq -r .INTEGRATIONS.\"$TRACEPATH\"._NAC_activity.latest_toc_handle_processed)
		if [ "$LATEST_TOC_HANDLE" =  "-" ] ; then
			LATEST_TOC_HANDLE=""
		fi
		echo "INFO ::: LATEST_TOC_HANDLE: $LATEST_TOC_HANDLE"
	else
		LATEST_TOC_HANDLE=""
		echo "ERROR ::: Tracker JSON folder Not present"
	fi

	echo "INFO ::: LATEST_TOC_HANDLE" $LATEST_TOC_HANDLE
	LATEST_TOC_HANDLE_PROCESSED=$LATEST_TOC_HANDLE

	FOLDER_PATH=`pwd`

	##appending latest_toc_handle_processed to TFVARS_FILE
	echo "PrevUniFSTOCHandle="\"$LATEST_TOC_HANDLE\" >>$FOLDER_PATH/$TFVARS_FILE

fi

##### RUN terraform init
echo "INFO ::: NAC provisioning ::: BEGIN - Executing ::: Terraform init."
COMMAND="terraform init"
$COMMAND
chmod 755 $(pwd)/*
# ls -alt
# exit 1
echo "INFO ::: NAC provisioning ::: FINISH - Executing ::: Terraform init."
echo "INFO ::: NAC provisioning ::: BEGIN - Executing ::: Terraform Apply . . . . . . . . . . . "
COMMAND="terraform apply -var-file=${TFVARS_FILE} -auto-approve"
# COMMAND="terraform validate"
$COMMAND
if [ $? -eq 0 ]; then
	echo "INFO ::: NAC provisioning ::: FINISH ::: Terraform apply ::: SUCCESS"
	
	######Req for generate_tracker_json for kendra if condition
	if [ "${SERVICE_NAME^^}" = "ES" ] || [ "${SERVICE_NAME^^}" = "OS" ] ; then

		echo "INFO ::: NAC_Activity : Export Completed. Indexing in Progress"
		CURRENT_STATE="Export-completed-And-Indexing-In-progress"
		LATEST_TOC_HANDLE_PROCESSED=$(terraform output -raw latest_toc_handle_processed)
		echo "INFO ::: LATEST_TOC_HANDLE_PROCESSED for NAC Discovery is : $LATEST_TOC_HANDLE_PROCESSED"
		generate_tracker_json $OS_URL $KIBANA_URL $DEFAULT_URL $FREQUENCY $USER_SECRET $CREATED_BY $CREATED_ON $TRACKER_NMC_VOLUME_NAME $ANALYTICS_SERVICE $MOST_RECENT_RUN $CURRENT_STATE $LATEST_TOC_HANDLE_PROCESSED $NAC_SCHEDULER_NAME
	elif [ "${SERVICE_NAME^^}" = "EXP" ] ; then

		echo "INFO ::: NAC_Activity : Export Completed."
		CURRENT_STATE="Export-completed"
		LATEST_TOC_HANDLE_PROCESSED=$(terraform output -raw latest_toc_handle_processed)
		echo "INFO ::: Latest Processed Snapshot ID (i.e. latest_toc_handle_processed) is : $LATEST_TOC_HANDLE_PROCESSED"
               
	elif [ "${SERVICE_NAME^^}" = "KENDRA" ];then 
		echo "INFO ::: Kendra Execution"
		echo "INFO ::: NAC_Activity : Export Completed. Indexing in Progress"
		CURRENT_STATE="Export-completed-And-Indexing-In-progress"
		LATEST_TOC_HANDLE_PROCESSED=$(terraform output -raw latest_toc_handle_processed)
		echo "INFO ::: LATEST_TOC_HANDLE_PROCESSED for NAC Discovery is : $LATEST_TOC_HANDLE_PROCESSED"
		generate_tracker_json_kendra $INDEX_NAME $INDEX_ID $DEFAULT_URL $FREQUENCY $USER_SECRET  $CREATED_ON $TRACKER_NMC_VOLUME_NAME $ANALYTICS_SERVICE $MOST_RECENT_RUN $CURRENT_STATE $LATEST_TOC_HANDLE_PROCESSED $NAC_SCHEDULER_NAME $KENDRA_URL

	fi
else
	echo "INFO ::: NAC provisioning ::: FINISH ::: Terraform apply ::: FAILED"

	######Req for generate_tracker_json for kendra if condition
	if [ "${SERVICE_NAME^^}" = "ES" ] || [ "${SERVICE_NAME^^}" = "OS" ]; then

		echo "INFO ::: NAC_Activity : Export Failed/Indexing Failed"
		CURRENT_STATE="Export-Failed-And-Indexing-Failed"
		generate_tracker_json $OS_URL $KIBANA_URL $DEFAULT_URL $FREQUENCY $USER_SECRET $CREATED_BY $CREATED_ON $TRACKER_NMC_VOLUME_NAME $ANALYTICS_SERVICE $MOST_RECENT_RUN $CURRENT_STATE $LATEST_TOC_HANDLE_PROCESSED $NAC_SCHEDULER_NAME
	##exit 1
	elif [ "${SERVICE_NAME^^}" = "EXP" ] ; then
		echo "INFO ::: NAC_Activity : Export Failed"
		echo "INFO ::: STARTED ::: CLEANUP NAC STACK and dependent resources . . . . . . . . . . . . . . . . . . . . ."
	
		# ##### RUN terraform destroy to CLEANUP NAC STACK and dependent resources
		COMMAND="terraform destroy -var-file=${TFVARS_FILE} -auto-approve"
		$COMMAND
		echo "INFO ::: COMPLETED ::: CLEANUP NAC STACK and dependent resources ! ! ! ! "

		END=$(date +%s)
		secs=$((END - START))
		DIFF=$(printf '%02dh:%02dm:%02ds\n' $((secs/3600)) $((secs%3600/60)) $((secs%60)))
		echo "INFO ::: Total execution Time ::: $DIFF"
		exit 1
	else
		echo "INFO ::: Kendra Execution"
		echo "INFO ::: NAC_Activity : Export Failed/Indexing Failed"
		CURRENT_STATE="Export-Failed-And-Indexing-Failed"
		generate_tracker_json_kendra $INDEX_NAME $INDEX_ID $DEFAULT_URL $FREQUENCY $USER_SECRET  $CREATED_ON $TRACKER_NMC_VOLUME_NAME $ANALYTICS_SERVICE $MOST_RECENT_RUN $CURRENT_STATE $LATEST_TOC_HANDLE_PROCESSED $NAC_SCHEDULER_NAME $KENDRA_URL

	fi
fi

sleep 300
if [ "${SERVICE_NAME^^}" = "EXP" ] ; then
	echo "INFO ::: EXPORT Completed"
	echo "INFO ::: STARTED ::: CLEANUP NAC STACK and dependent resources . . . . . . . . . . . . . . . . . . . . ."
	
	# ##### RUN terraform destroy to CLEANUP NAC STACK and dependent resources
	COMMAND="terraform destroy -var-file=${TFVARS_FILE} -auto-approve"
	$COMMAND
	echo "INFO ::: COMPLETED ::: CLEANUP NAC STACK and dependent resources ! ! ! ! "

	END=$(date +%s)
	secs=$((END - START))
	DIFF=$(printf '%02dh:%02dm:%02ds\n' $((secs/3600)) $((secs%3600/60)) $((secs%60)))
	echo "INFO ::: Total execution Time ::: $DIFF"
else
	echo "INFO ::: NAC_Activity : Indexing Completed"
	MOST_RECENT_RUN=$(date "+%Y:%m:%d-%H:%M:%S")
	CURRENT_STATE="Indexing-Completed"

	INTERNAL_SECRET=$(head -n 1 nac_uniqui_id.txt  | tr -d "'")
	echo "INFO ::: Internal secret for NAC Discovery is : $INTERNAL_SECRET"

	######Req for generate_tracker_json for kendra if condition
	if [ "${SERVICE_NAME^^}" = "ES" ] || [ "${SERVICE_NAME^^}" = "OS" ]; then
		generate_tracker_json $OS_URL $KIBANA_URL $DEFAULT_URL $FREQUENCY $USER_SECRET $CREATED_BY $CREATED_ON $TRACKER_NMC_VOLUME_NAME $ANALYTICS_SERVICE $MOST_RECENT_RUN $CURRENT_STATE $LATEST_TOC_HANDLE_PROCESSED $NAC_SCHEDULER_NAME
	else
		echo "INFO ::: Kendra execution"
		generate_tracker_json_kendra $INDEX_NAME $INDEX_ID $DEFAULT_URL $FREQUENCY $USER_SECRET  $CREATED_ON $TRACKER_NMC_VOLUME_NAME $ANALYTICS_SERVICE $MOST_RECENT_RUN $CURRENT_STATE $LATEST_TOC_HANDLE_PROCESSED $NAC_SCHEDULER_NAME $KENDRA_URL
	fi	   
	######Req for generate_tracker_json for kendra if condition


	##Get the NAC discovery lambda function name
	DISCOVERY_LAMBDA_NAME=$(aws secretsmanager get-secret-value --secret-id "$INTERNAL_SECRET" --region "${AWS_REGION}"  --profile "${AWS_PROFILE}" | jq -r '.SecretString' | jq -r '.discovery_lambda_name')

	if [ -n "$DISCOVERY_LAMBDA_NAME" ]; then
		echo "INFO ::: Discovery lambda name :::not empty"
	else
		echo "INFO ::: Discovery lambda name :::empty"
	fi

	echo "INFO ::: Discovery lambda name ::: ${DISCOVERY_LAMBDA_NAME}"
	i_cnt=0
	### Check If Lambda Execution Completed ?
	LAST_UPDATE_STATUS="running"
	CLEANUP="Y"
	if [ "$CLEANUP" != "Y" ]; then

		if [ -z "$DISCOVERY_LAMBDA_NAME"  ]; then
			CLEANUP="Y"
		else
			while [ "$LAST_UPDATE_STATUS" != "InProgress" ]; do
				LAST_UPDATE_STATUS=$(aws lambda get-function-configuration --function-name "$DISCOVERY_LAMBDA_NAME" --region "${AWS_REGION}" | jq -r '.LastUpdateStatus')
				echo "INFO ::: LAST_UPDATE_STATUS ::: $LAST_UPDATE_STATUS"
				if [ "$LAST_UPDATE_STATUS" == "Successful" ]; then
					echo "INFO ::: Lambda execution COMPLETED. Preparing for cleanup of NAC Stack and dependent resources . . . . . . . . . . "
					CLEANUP="Y"
					break
				elif [ "$LAST_UPDATE_STATUS" == "Failed" ]; then
					echo "INFO ::: Lambda execution FAILED. Preparing for cleanup of NAC Stack and dependent resources . . . . . . . . . .  "
					CLEANUP="Y"
					break
				elif [[ "$LAST_UPDATE_STATUS" == "" || "$LAST_UPDATE_STATUS" == null ]]; then
					echo "INFO ::: Lambda Function Not found."
					CLEANUP="Y"
					break
			fi
			((i_cnt++)) || true

			if [ $((i_cnt)) -eq 5 ]; then
				if [[ -z "${LAST_UPDATE_STATUS}" ]]; then
					echo "WARN ::: System TimeOut"
					CLEANUP="Y"
					break
			fi

			fi
		done
		fi
	fi
	echo "INFO ::: CleanUp Flag: $CLEANUP"
	###################################################
	#if [ "$CLEANUP" == "Y" ]; then
	echo "INFO ::: Lambda execution COMPLETED."
	echo "INFO ::: STARTED ::: CLEANUP NAC STACK and dependent resources . . . . . . . . . . . . . . . . . . . . ."

	pwd
	echo "INFO ::: pwd" pwd
	UNIQUE_ID=$(cat nac_uniqui_id.txt | cut -d - -f4)
	echo "INFO ::: UNIQUE_ID ::: $UNIQUE_ID "

	aws s3 rm --recursive s3://nasuni-share-data-bucket-storage/nmc_api_data_$UNIQUE_ID/ --profile ${AWS_PROFILE}
	if [ $? -eq 0 ]; then
			echo "INFO ::: deleted files from nasuni-share-data-bucket-storage bucket and folder nmc_api_data_$UNIQUE_ID"      
	else
			echo "INFO ::: Error in deleted files from nasuni-share-data-bucket-storage bucket and folder nmc_api_data_$UNIQUE_ID"
	fi
fi

# ##### RUN terraform destroy to CLEANUP NAC STACK and dependent resources

COMMAND="terraform destroy -var-file=${TFVARS_FILE} -auto-approve"
$COMMAND
echo "INFO ::: COMPLETED ::: CLEANUP NAC STACK and dependent resources ! ! ! ! "

END=$(date +%s)
secs=$((END - START))
DIFF=$(printf '%02dh:%02dm:%02ds\n' $((secs/3600)) $((secs%3600/60)) $((secs%60)))
echo "INFO ::: Total execution Time ::: $DIFF"
#exit 0

} || {
	END=$(date +%s)
	secs=$((END - START))
	DIFF=$(printf '%02dh:%02dm:%02ds\n' $((secs/3600)) $((secs%3600/60)) $((secs%60)))
	echo "INFO ::: Total execution Time ::: $DIFF"
	exit 0
	echo "INFO ::: Failed NAC Povisioning"

}
)2>&1 | tee $LOG_FILE
