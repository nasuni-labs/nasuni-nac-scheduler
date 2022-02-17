#!/bin/bash

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
    esac
  done < "$file"
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



read_TFVARS "$TFVARS_FILE"

AWS_PROFILE=$(echo "$AWS_PROFILE" | tr -d '"')
AWS_REGION=$(echo "$AWS_REGION" | tr -d '"')
NMC_VOLUME_NAME=$(echo "$NMC_VOLUME_NAME" | tr -d '"')
GITHUB_ORGANIZATION=$(echo "$GITHUB_ORGANIZATION" | tr -d '"')

######################## Determine what service is employed ###############################################
SERVICE = ${PWD##*_}

######################## Check If Kendra Endpoint is Available ###############################################
check_for_kendra(){
    REPO_FOLDER=$1
    KENDRA_INDEX_ID=$(aws secretsmanager get-secret-value --secret-id nac/kendra --region "${AWS_REGION}" | jq -r '.SecretString' | jq --arg VOL $NMC_VOLUME_NAME -r '.[$VOL]')
    echo "INFO ::: KENDRA_INDEX_ID : $KENDRA_INDEX_ID"
    # exit 1
    IS_KE="N"
    if [ "$KENDRA_INDEX_ID" == "" ] || [ "$KENDRA_INDEX_ID" == null ] || [ "$KENDRA_INDEX_ID" == false ]; then
        echo "ERROR ::: A Kendra index does not exist for $NMC_VOLUME_NAME "
        IS_KE="N"
    else
        KE_INDEX_STATUS = $(aws kendra describe-index --id $KENDRA_ENDPOINT | jq -r '.Status')
        if [ "$KE_INDEX_STATUS" == "ACTIVE" ]; then
            echo "INFO ::: The Kendra index for $NMC_VOLUME_NAME is Active"
            KE_EXPERIENCE_CREATING=$(aws kendra list-experiences --index-id $KENDRA_INDEX_ID | jq -r '.SummaryItems[]| select(.Status=="CREATING")')
            KE_EXPERIENCE_CREATED=$(aws kendra list-experiences --index-id $KENDRA_INDEX_ID | jq -r '.SummaryItems[]| select(.Status=="ACTIVE").Endpoints[].Endpoint')
            #If Experience is being created, notify user and then exit
            if [ "$KE_EXPERIENCE_CREATING" == "" ] || [ "$KE_EXPERIENCE_CREATING" == null ] || [ "$KE_EXPERIENCE_CREATING" == false ]; then
                echo "ERROR ::: A Kendra experience for $NMC_VOLUME_NAME is being created. Exiting now to allow that process to complete"            	
                IS_KE="Y"
                exit 0
            fi
            if [ "$KE_EXPERIENCE_CREATED" == "" ] || [ "$KE_EXPERIENCE_CREATED" == null ] || [ "$KE_EXPERIENCE_CREATED" == false ]; then
                echo "INFO ::: No Kendra experience for $NMC_VOLUME_NAME has been created. Creating one now"   
            else   
                echo "INFO ::: A Kendra experience has already been created for $NMC_VOLUME_NAME. The endpoints are $KE_EXPERIENCE_CREATED"   	
                IS_KE="Y"        
            fi

        else
            KE_ERROR_MSG = $(aws kendra describe-index --id $KENDRA_ENDPOINT | jq -r '.ErrorMessage')
            echo "INFO ::: The Kendra index for $NMC_VOLUME_NAME is not Active. The Error Message is $KE_ERROR_MSG"
            exit 0
    fi
    if [ "$IS_KE" == "N" ]; then
        echo "ERROR ::: A Kendra Index and/or Experience has not been Configured. Need to Provision ElasticSearch Domain Before, NAC Provisioning."
        echo "INFO ::: Start Kendra Index and Experience Provisioning."
        ########################### Git Clone  ###############################################################
        echo "INFO ::: Start - Git Clone !!!"
        ### Download Provisioning Code from GitHub
        GIT_REPO="https://github.com/$GITHUB_ORGANIZATION/$REPO_FOLDER.git"
        GIT_REPO_NAME=$(echo ${GIT_REPO} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
        echo "$GIT_REPO"
        echo "INFO ::: GIT_REPO_NAME $GIT_REPO_NAME"
        pwd
        ls
        echo "INFO ::: Removing ${GIT_REPO_NAME}"
        rm -rf "${GIT_REPO_NAME}"
        pwd
        COMMAND="git clone -b main ${GIT_REPO}"
        $COMMAND
        RESULT=$?
        echo $RESULT
        if [ $RESULT -eq 0 ]; then
            echo "INFO ::: GIT clone SUCCESS for repo ::: $GIT_REPO_NAME"
        else
            echo "INFO ::: GIT Clone  FAILED for repo ::: $GIT_REPO_NAME"
            exit 1
        fi
        #### Copy tfvars file into repo
        cp "${TFVARS_FILE}" "${GIT_REPO_NAME}"/kendra.tfvars
        cd "${GIT_REPO_NAME}"
        ##### RUN terraform init
        echo "INFO ::: Kendra PROVISIONING ::: STARTED ::: Executing the Terraform scripts . . . . . . . . . . . ."
        COMMAND="terraform init"
        $COMMAND
        chmod 755 $(pwd)/*
        # exit 1
        echo "INFO ::: Kendra PROVISIONING ::: Initialized Terraform Libraries/Dependencies"
        ##### RUN terraform Apply
        echo "INFO ::: Kendra PROVISIONING ::: STARTED ::: Terraform apply . . . . . . . . . . . . . . . . . . ."
        COMMAND="terraform apply -auto-approve"
        # COMMAND="terraform validate"
        $COMMAND
        if [ $? -eq 0 ]; then
            echo "INFO ::: Kendra PROVISIONING ::: Terraform apply ::: COMPLETED . . . . . . . . . . . . . . . . . . ."
        else
            echo "ERROR ::: Kendra PROVISIONING ::: Terraform apply ::: FAILED."
            exit 1
        fi
        cd ..
    else
        echo "INFO ::: Kendra Enpoint is Active. The endpoints can be accessed at $KE_EXPERIENCE_CREATED"
        echo "INFO ::: START ::: NAC Provisioning . . . . . . . . . . . ."
    fi

}



######################## Check If ES Domain Available ###############################################
ES_DOMAIN_NAME=$(aws secretsmanager get-secret-value --secret-id nasuni-labs-os-admin --region "${AWS_REGION}" | jq -r '.SecretString' | jq -r '.es_domain_name')
echo "INFO ::: ES_DOMAIN NAME : $ES_DOMAIN_NAME"
# exit 1
IS_ES="N"
if [ "$ES_DOMAIN_NAME" == "" ] || [ "$ES_DOMAIN_NAME" == null ]; then
    echo "ERROR ::: ElasticSearch Domain is Not provided in admin secret"
    IS_ES="N"
else
    ES_CREATED=$(aws es describe-elasticsearch-domain --domain-name "${ES_DOMAIN_NAME}" --region "${AWS_REGION}" | jq -r '.DomainStatus.Created')
    if [ $? -eq 0 ]; then
        echo "INFO ::: ES_CREATED : $ES_CREATED"
        ES_PROCESSING=$(aws es describe-elasticsearch-domain --domain-name "${ES_DOMAIN_NAME}" --region "${AWS_REGION}" | jq -r '.DomainStatus.Processing')
        echo "INFO ::: ES_PROCESSING : $ES_PROCESSING"
        ES_UPGRADE_PROCESSING=$(aws es describe-elasticsearch-domain --domain-name "${ES_DOMAIN_NAME}" --region "${AWS_REGION}" | jq -r '.DomainStatus.UpgradeProcessing')
        echo "INFO ::: ES_UPGRADE_PROCESSING : $ES_UPGRADE_PROCESSING"
    
        if [ "$ES_PROCESSING" == "false" ] &&  [ "$ES_UPGRADE_PROCESSING" == "false" ]; then
            echo "INFO ::: ElasticSearch Domain ::: $ES_DOMAIN_NAME is Active"
            IS_ES="Y"
        else
            echo "ERROR ::: ElasticSearch Domain ::: $ES_DOMAIN_NAME is either unavailable Or Not Active"
            IS_ES="N"
        fi
    else
        echo "ERROR ::: ElasticSearch Domain ::: $ES_DOMAIN_NAME not found"
        IS_ES="N"
    fi
fi
if [ "$IS_ES" == "N" ]; then
    echo "ERROR ::: ElasticSearch Domain is Not Configured. Need to Provision ElasticSearch Domain Before, NAC Provisioning."
    echo "INFO ::: Begin ElasticSearch Domain Provisioning."
   ########## Download ElasticSearch Provisioning Code from GitHub ##########
	### GITHUB_ORGANIZATION defaults to nasuni-labs
	REPO_FOLDER="nasuni-awsopensearch"
	validate_github $GITHUB_ORGANIZATION $REPO_FOLDER 
    ########################### Git Clone  ###############################################################
    echo "INFO ::: BEGIN - Git Clone !!!"
    ### Download Provisioning Code from GitHub
    GIT_REPO_NAME=$(echo ${GIT_REPO} | sed 's/.*\/\([^ ]*\/[^.]*\).*/nasuni-\1/' | cut -d "/" -f 2)
    echo "INFO ::: $GIT_REPO"
    echo "INFO ::: GIT_REPO_NAME $GIT_REPO_NAME"
    pwd
    ls
    echo "INFO ::: Removing ${GIT_REPO_NAME}"
    rm -rf "${GIT_REPO_NAME}"
    pwd
    COMMAND="git clone -b main ${GIT_REPO}"
    $COMMAND
    RESULT=$?
    if [ $RESULT -eq 0 ]; then
        echo "INFO ::: FINISH ::: GIT clone SUCCESS for repo ::: $GIT_REPO_NAME"
    else
        echo "INFO ::: FINISH ::: GIT Clone FAILED for repo ::: $GIT_REPO_NAME"
        exit 1
    fi
    cd "${GIT_REPO_NAME}"
    ##### RUN terraform init
    echo "INFO ::: ElasticSearch provisioning ::: BEGIN ::: Executing ::: Terraform init . . . . . . . . "
    COMMAND="terraform init"
    $COMMAND
    chmod 755 $(pwd)/*
    # exit 1
    echo "INFO ::: ElasticSearch provisioning ::: FINISH - Executing ::: Terraform init."
    ##### RUN terraform Apply
    echo "INFO ::: ElasticSearch provisioning ::: BEGIN ::: Executing ::: Terraform apply . . . . . . . . . . . . . . . . . . ."
    COMMAND="terraform apply -auto-approve"
    # COMMAND="terraform validate"
    $COMMAND
    if [ $? -eq 0 ]; then
        echo "INFO ::: ElasticSearch provisioning ::: FINISH ::: Executing ::: Terraform apply ::: SUCCESS"
    else
        echo "ERROR ::: ElasticSearch provisioning ::: FINISH ::: Executing ::: Terraform apply ::: FAILED "
        exit 1
    fi
    cd ..
else
    echo "INFO ::: ElasticSearch Domain is Active . . . . . . . . . ."
    echo "INFO ::: BEGIN ::: NAC Provisioning . . . . . . . . . . . ."
fi

##################################### END ES Domain ###################################################################
# exit 0

if [ "$SERVICE" == "es" ]; then
    REPO_FOLDER = 'nasuni-analyticsconnector-opensearch'
    check_for_es $REPO_FOLDER

fi

if [ "$SERVICE" == "kendra" ]; then
    REPO_FOLDER = 'nasuni-analyticsconnector-kendra'
    check_for_kendra $REPO_FOLDER

fi
    GIT_REPO="https://github.com/$GITHUB_ORGANIZATION/$REPO_FOLDER.git"

NMC_VOLUME_NAME=$(echo "${TFVARS_FILE}" | rev | cut -d'/' -f 1 | rev |cut -d'.' -f 1)
cd "$NMC_VOLUME_NAME"
pwd
echo "INFO ::: current user :-"`whoami`
########## Download NAC Provisioning Code from GitHub ##########
### GITHUB_ORGANIZATION defaults to NasuniLabs
validate_github $GITHUB_ORGANIZATION $REPO_FOLDER 
########################### Git Clone : NAC Provisioning Repo ###############################################################
echo "INFO ::: BEGIN - Git Clone !!!"
### Download Provisioning Code from GitHub
GIT_REPO_NAME=$(echo ${GIT_REPO} | sed 's/.*\/\([^ ]*\/[^.]*\).*/\1/' | cut -d "/" -f 2)
echo "INFO ::: GIT_REPO : $GIT_REPO"
echo "INFO ::: GIT_REPO_NAME : $GIT_REPO_NAME"
pwd
ls
echo "INFO ::: Deleting the Directory: ${GIT_REPO_NAME}"
rm -rf "${GIT_REPO_NAME}"
pwd
COMMAND="git clone -b main ${GIT_REPO}"
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
ls -l
########################### Completed - Git Clone  ###############################################################
echo "INFO ::: Copy TFVARS file to $(pwd)/${GIT_REPO_NAME}/${TFVARS_FILE}"
# cp "$NMC_VOLUME_NAME/${TFVARS_FILE}" $(pwd)/"${GIT_REPO_NAME}"/
cp "${TFVARS_FILE}" "${GIT_REPO_NAME}"/
cd "${GIT_REPO_NAME}"
pwd
ls
##### RUN terraform init
echo "INFO ::: NAC provisioning ::: BEGIN - Executing ::: Terraform init."
COMMAND="terraform init"
$COMMAND
chmod 755 $(pwd)/*
# exit 1
echo "INFO ::: NAC provisioning ::: FINISH - Executing ::: Terraform init."
echo "INFO ::: NAC provisioning ::: BEGIN - Executing ::: Terraform Apply . . . . . . . . . . . "
COMMAND="terraform apply -var-file=${TFVARS_FILE} -auto-approve"
# COMMAND="terraform validate"
$COMMAND
if [ $? -eq 0 ]; then
        echo "INFO ::: NAC provisioning ::: FINISH ::: Terraform apply ::: SUCCESS"
    else
        echo "INFO ::: NAC provisioning ::: FINISH ::: Terraform apply ::: FAILED"
        exit 1
    fi
###### WAITING For Lambda to IndexData - 30Sec   (Only for Testing) "
# echo "WAITING For Lambda to IndexData - 30Sec   (Only for Testing) "
sleep 30
#exit 0

INTERNAL_SECRET=$(head -n 1 nac_uniqui_id.txt  | tr -d "'")
echo "INFO ::: Internal secret for NAC Discovery is : $INTERNAL_SECRET"
### Get the NAC discovery lambda function name
DISCOVERY_LAMBDA_NAME=$(aws secretsmanager get-secret-value --secret-id "$INTERNAL_SECRET" --region "${AWS_REGION}"  --profile "${AWS_PROFILE}" | jq -r '.SecretString' | jq -r '.discovery_lambda_name')

if [ -n "$DISCOVERY_LAMBDA_NAME" ]; then
    echo "INFO ::: Discovery lambda name :::not empty"
else
    echo "INFO ::: Discovery lambda name :::empty"
fi

echo "INFO ::: Discovery lambda name ::: ${DISCOVERY_LAMBDA_NAME}"
# echo "INFO ::: Region ::: ${AWS_REGION}"
# echo "INFO ::: Profile Name ::: ${AWS_PROFILE}"
#exit 1
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
            echo "LAST_UPDATE_STATUS ::: $LAST_UPDATE_STATUS"
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

            echo " %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%% $((i_cnt))"
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
    # ##### RUN terraform destroy to CLEANUP NAC STACK and dependent resources
#  exit 1

    COMMAND="terraform destroy -var-file=${TFVARS_FILE} -auto-approve"
    # COMMAND="terraform validate"
    $COMMAND
    echo "INFO ::: COMPLETED ::: CLEANUP NAC STACK and dependent resources ! ! ! ! "
#    exit 0
#fi
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
