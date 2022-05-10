#### ./creater_layer.sh <package_name> <layer_name>
#### ./creater_layer.sh elasticsearch my-layer
#### ./creater_layer.sh my-layer nasuni
path="app"
LAYER_NAME="$1"
AWS_PROFILE="$2"
NAC_IP="$3"
AWS_CURRENT_USER="$4"
echo "INFO ::: LAYER_NAME ::: $LAYER_NAME"
echo "INFO ::: AWS_PROFILE ::: $AWS_PROFILE"
echo "INFO ::: NAC_IP ::: $NAC_IP"
echo "INFO ::: AWS_CURRENT_USER ::: $AWS_CURRENT_USER"
NEW_NAC_IP=$(echo $NAC_IP | tr '.' '-')
LAMBDA_LAYER_NAME=$(echo $LAYER_NAME-$NEW_NAC_IP-$AWS_CURRENT_USER)
EXISTING_LAMBDA_LAYER=$(aws lambda list-layers --compatible-runtime python3.8 --profile $AWS_PROFILE)
echo "INFO ::: EXISTING_LAMBDA_LAYER ::: $EXISTING_LAMBDA_LAYER"
EXT_LAMBDA_LAYER=$(echo $EXISTING_LAMBDA_LAYER | jq -r '.Layers[] | select(.LayerName == '\"$LAMBDA_LAYER_NAME\"') | {LayerName}')
echo "ext_lambda_layer $EXT_LAMBDA_LAYER"

if [ "$EXT_LAMBDA_LAYER" = "" ] ; then
   mkdir -p $path
   for i in opensearch-py requests requests_aws4auth python-pptx PyMuPDF python-docx pandas chardet openpyxl xlrd
   do
     pip3 install "$i" --target "${path}/python/lib/python3.8/site-packages/"
   done
   cd $path && zip -r ../lambdalayer.zip .
   aws s3 mb s3://"$LAMBDA_LAYER_NAME" --profile $AWS_PROFILE
    if [ $? -eq 0 ]; then
        echo OK
    else
        echo bucket is already exist
    fi
    ### going to add /home/ubuntu directory
    cd

    aws s3 cp lambdalayer.zip s3://"${LAMBDA_LAYER_NAME}" --profile $AWS_PROFILE

    aws lambda publish-layer-version --layer-name "${LAMBDA_LAYER_NAME}" --description "Lambda layer for including all pkgs for NAC_Discovery"     --license-info "MIT" --content S3Bucket="${LAMBDA_LAYER_NAME}",S3Key=lambdalayer.zip  --compatible-runtimes python3.8 python3.9 --profile $AWS_PROFILE
else
          echo "The layer "${LAMBDA_LAYER_NAME}" is already present"
fi