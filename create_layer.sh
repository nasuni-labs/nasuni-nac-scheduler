#./creater_layer.sh <package_name> <layer_name>
#./creater_layer.sh elasticsearch my-layer
#./creater_layer.sh my-layer nasuni
path="app"
LAYER_NAME="$1"
AWS_PROFILE="$2"
echo "INFO ::: LAYER_NAME ::: $LAYER_NAME"
echo "INFO ::: AWS_PROFILE ::: $AWS_PROFILE"
EXISTING_LAMBDA_LAYER=$(aws lambda list-layers --compatible-runtime python3.8 --profile $AWS_PROFILE)
echo "INFO ::: EXISTING_LAMBDA_LAYER ::: $EXISTING_LAMBDA_LAYER"
EXT_LAMBDA_LAYER=$(echo $EXISTING_LAMBDA_LAYER | jq -r '.Layers[] | select(.LayerName == '\"$LAYER_NAME\"') | {LayerName}')
echo "ext_lambda_layer $EXT_LAMBDA_LAYER"

if [ "$EXT_LAMBDA_LAYER" = "" ] ; then
   mkdir -p $path
   for i in opensearch-py requests requests_aws4auth python-pptx PyMuPDF python-docx pandas chardet openpyxl xlrd
   do
     # pip3 install "${package}" --target "${path}/python/lib/python3.9/site-packages/"
     pip3 install "$i" --target "${path}/python/lib/python3.8/site-packages/"
     #echo "$i"
   done
   cd $path && zip -r ../lambdalayer.zip .
   aws s3 mb s3://nac-discovery-lambda-layer --profile $AWS_PROFILE
    if [ $? -eq 0 ]; then
	echo OK
    else
        echo bucket is already exist
    fi

    aws s3 cp lambdalayer.zip s3://nac-discovery-lambda-layer --profile $AWS_PROFILE

    aws lambda publish-layer-version --layer-name "${LAYER_NAME}" --description "Lambda layer for including all pkgs for NAC_Discovery"     --license-info "MIT" --content S3Bucket=nac-discovery-lambda-layer,S3Key=lambdalayer.zip  --compatible-runtimes python3.8 python3.9 --profile $AWS_PROFILE
else
	  echo "The layer ${LAYER_NAME} is already present"
fi
