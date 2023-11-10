#!/bin/bash 

ANALYTICS_SERVICE="$1"
AWS_REGION="$2"
AWS_PROFILE="$3"
GITHUB_ORGANIZATION="$4"
GIT_BRANCH="$5"

echo "INFO ::: $ANALYTICS_SERVICE"
echo "INFO ::: $AWS_REGION"
echo "INFO ::: $AWS_PROFILE"
echo "INFO ::: $GITHUB_ORGANIZATION"
echo "INFO ::: $GIT_BRANCH"
validate_aws_profile() {
	echo "INFO ::: Validating AWS profile ${AWS_PROFILE} for NAC  . . . . . . . . . . . . . . . . !!!"

	if [[ "$(grep '^[[]profile' <~/.aws/config | awk '{print $2}' | sed 's/]$//' | grep "${AWS_PROFILE}")" == "" ]]; then
		echo "ERROR ::: AWS profile ${AWS_PROFILE} does not exists. To Create AWS PROFILE, Run cli command - aws configure "
		exit 1
	else # AWS Profile nasuni available in JumpBox machine
		echo "INFO ::: AWS profile $AWS_PROFILE exists in JumpBox Computer !!!"
		AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id --profile ${AWS_PROFILE})
		AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key --profile ${AWS_PROFILE})
		AWS_REGION=`aws configure get region --profile ${AWS_PROFILE}`
		echo "INFO ::: AWS profile Validation SUCCESS !!!"
	fi
}
validate_github() {
	GITHUB_ORGANIZATION=$1
	REPO_FOLDER=$2
	if [ "$GITHUB_ORGANIZATION" != "" ]; then
		echo "INFO ::: Value of github_organization is $GITHUB_ORGANIZATION"	
	else 
		GITHUB_ORGANIZATION="nasuni-labs"
		echo "INFO ::: Value of github_organization is set to default as $GITHUB_ORGANIZATION"	
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
current_folder()
{
	CURRENT_FOLDER=`pwd`
	echo "INFO ::: Current Folder: $CURRENT_FOLDER"
}
######Start Exec
TFVARS_NAC_SCHEDULER="NACScheduler.tfvars"

source /home/ubuntu/UI_deploy_kendra_es/${REPO_FOLDER}NACScheduler.tfvars
echo "INFO ::: nac-scheduler-name $nac_scheduler_name"
echo "INFO ::: user_private_ip $use_private_ip"
USE_PRIVATE_IP=$(echo $use_private_ip| tr -d '"')
USER_VPC_ID=$(echo $user_vpc_id| tr -d '"')
echo "INFO ::: user_private_ip $use_private_ip"
echo "INFO ::: USER_VPC_ID $USER_VPC_ID"
echo "INFO ::: AWS_REGION $AWS_REGION"
echo "INFO ::: AWS_PROFILE $AWS_PROFILE"

if [[ "$USE_PRIVATE_IP" == "N" ]]; then
	REPO_FOLDER="nasuni-opensearch-userinterface-public"
else
	REPO_FOLDER="nasuni-opensearch-userinterface"
	sed -i '/^$/d' $TFVARS_NAC_SCHEDULER
	sed -i '/vpc_endpoint_id/d'  $TFVARS_NAC_SCHEDULER
	SERVICE_NAME="com.amazonaws.$AWS_REGION.execute-api"
	echo "INFO ::: SERVICE_NAME $SERVICE_NAME"

	VPC_ENDPOINT_ID=`aws ec2 describe-vpc-endpoints --profile $AWS_PROFILE --region $AWS_REGION | jq -r '.VpcEndpoints[]|select(.VpcId == '\"$USER_VPC_ID\"' and .ServiceName=='\"$SERVICE_NAME\"') | {VpcEndpointId}' | jq -r '.VpcEndpointId'`
	echo "INFO ::: VPC_ENDPOINT_ID $VPC_ENDPOINT_ID"

	echo "vpc_endpoint_id="\"$VPC_ENDPOINT_ID\" >> $TFVARS_NAC_SCHEDULER
	echo "" >> $TFVARS_NAC_SCHEDULER
fi
echo "INFO ::: REPO_FOLDER $REPO_FOLDER"
#exit 11
#cp $TFVARS_NAC_SCHEDULER $REPO_FOLDER/
echo "INFO ::: Check if Deployment is already done"
FLAG="N"
echo "INFO ::: GIT BRANCH : $GIT_BRANCH"
if [ -d "$REPO_FOLDER" ]; then
    echo "INFO ::: $REPO_FOLDER does exist. UI installation is already there"
    FLAG="Y"
    cd "${REPO_FOLDER}"
    echo "$REPO_FOLDER"
    COMMAND="git pull origin $GIT_BRANCH"
    $COMMAND
    current_folder
    cd ../

fi
if [[ "$FLAG" == "N" ]]; then
    	echo "INFO ::: FLAG $FLAG Download code from git"

	validate_github $GITHUB_ORGANIZATION $REPO_FOLDER 
	GIT_REPO_NAME=$(echo ${GIT_REPO} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
	echo "INFO ::: Begin - Git Clone to ${GIT_REPO} -b $GIT_BRANCH"
	echo "INFO ::: $GIT_REPO"
	echo "INFO ::: GIT_REPO_NAME - $GIT_REPO_NAME"
	#current_folder
	rm -rf "${GIT_REPO_NAME}"
	COMMAND="git clone -b $GIT_BRANCH ${GIT_REPO}"
	$COMMAND
	RESULT=$?
	if [ $RESULT -eq 0 ]; then
	    echo "INFO ::: git clone SUCCESS for repo ::: $GIT_REPO_NAME"
	    cd "${GIT_REPO_NAME}"
	elif [ $RESULT -eq 128 ]; then
	    cd "${GIT_REPO_NAME}"
	    echo "$GIT_REPO_NAME"
	    COMMAND="git pull origin $GIT_BRANCH"
	    $COMMAND
	fi
	echo "INFO ::: $REPO_FOLDER"
	pwd
	cp ../$TFVARS_NAC_SCHEDULER ./
	current_folder
        sudo chmod 755 DeployNasuniWeb.sh
        sudo ./DeployNasuniWeb.sh
	#cd "${REPO_FOLDER}"
	
fi
current_folder
FILE=$(ls $REPO_FOLDER/search-api* 2>/dev/null)
FILE_FLAG="N"
#[ -f "nasuni-opensearch-userinterface-public/search-api*" ] && FILE_FLAG="Y"
SEARCH_API=""
if [ -f "$FILE" ]; then

	echo "$FILE exists."
	U_ID=$(cat $FILE)
	SEARCH_API=$(aws secretsmanager get-secret-value --secret-id nasuni-labs-search-api-$U_ID --region $AWS_REGION --profile $AWS_PROFILE | jq -r '.SecretString' | jq -r '.search_api_endpoint')
	echo "INFO ::: SEARCH_API $SEARCH_API"
	
else 
        echo "$FILE does not exist."
fi

if [ "${ANALYTICS_SERVICE^^}" = "ES" ] || [ "${ANALYTICS_SERVICE^^}" = "OS" ]; then

	if [ "$SEARCH_API" == "" ] || [ "$SEARCH_API" == "null" ] ; then
	    echo "INFO ::: API Gateway Deployemtn for ES"
	    cd $REPO_FOLDER
	    COMMAND="terraform init"
	    $COMMAND
	    COMMAND="terraform apply -var-file=$TFVARS_NAC_SCHEDULER -auto-approve"
	    $COMMAND
	    if [ $? -eq 0 ]; then
		echo "INFO ::: NAC Scheduler EC2 provisioning ::: FINISH - Executing ::: Terraform apply ::: SUCCESS."
		VAR_TRACKER_PATH="/var/www/Tracker_UI"
		VAR_SEARCHUI_PATH="/var/www/SearchUI_Web"
		#if [ ! -d "$VAR_TRACKER_PATH" ] || [ ! -d "$VAR_SEARCHUI_PATH" ]; then
	      	echo "INFO ::: SearchUIWeb and TrackerUI copying to /var/www"
		      sudo chmod -R 755 /var/www
		      #sudo rm -rf  /var/www/SearchUI_Web
		      #sudo rm -rf /var/www/Tracker_UI
		      
		      sudo cp -rf SearchUI_Web /var/www/.
		      sudo cp -rf Tracker_UI /var/www/.
		      sudo rm -rf /var/www/html/index.html
		      sudo service apache2 restart
		      echo Nasuni ElasticSearch Web portal: http://$(curl checkip.amazonaws.com)/search/index.html
		      echo Nasuni ElasticSearch Tracker Web portal: http://$(curl checkip.amazonaws.com)/tracker/index.html
		#else
		      echo "INFO ::: SearchUIWeb and TrackerUI  already copied to /var/www"
		#fi

	    else
		echo "ERROR ::: NAC Scheduler EC2 provisioning ::: FINISH - Executing ::: Terraform apply ::: FAILED."
		exit 1
	    fi
       else
	    echo "INFO ::: API GATEWAY is already present"
       fi
#SchName="abc"
elif [[ "${ANALYTICS_SERVICE^^}" == "KENDRA" ]]; then
	current_folder
sed -i 's#var schedulerName.*$#var schedulerName = \"'${nac_scheduler_name}'\"; #g' ~/UI_deploy_kendra_es/${REPO_FOLDER}/Tracker_UI/docs/fetch.js
	#sudo rm -rf /var/www/Tracker_UI
	sudo cp -rf ~/UI_deploy_kendra_es/${REPO_FOLDER}/Tracker_UI /var/www/.
	sudo cp -rf ~/UI_deploy_kendra_es/${REPO_FOLDER}/SearchUI_Web /var/www/.

	sudo service apache2 restart

	
	
	
fi
