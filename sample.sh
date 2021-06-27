#!/usr/bin/env bash
set -x


printf "installing aws --endpoint-url=http://localhost:4566..."
pip3 install awscli-local

printf "installing jq..."
apk add jq

aws configure set region eu-west-1
aws configure set access_key local
aws configure set secret_key local
aws configure set output json

echo "Configuring localstack components..."


NAME="test2"
export LAMBDA_ROLE_NAME="$NAME-lambda-role"
export LAMBDA_EXEC_ROLE_POLICY_NAME="$NAME-lambda-exec-policy"
export LAMBDA_FUNCTION_NAME="$NAME-lambda-function"


echo "Creating Bucket..."
aws --endpoint-url=http://localhost:4566 s3api  create-bucket    --bucket     mediaLibrary

echo "Creating Role..."
LAMBDA_ROLE="$(aws --endpoint-url=http://localhost:4566 iam create-role --role-name $LAMBDA_ROLE_NAME --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}')"

LAMBDA_FUNCTION_ROLE_ARN="$(echo "$LAMBDA_ROLE" | jq -r '.Role.Arn')"
#LAMBDA_ROLE EXAMPLE
#{
#    "Role": {
#        "Path": "/",
#        "RoleName": "test-lambda-role",
#        "RoleId": "tvhkdi6g8n4nq0j5cfrm",
#        "Arn": "arn:aws:iam::000000000000:role/test-lambda-role",
#        "CreateDate": "2021-01-30T16:56:39.942Z",
#        "AssumeRolePolicyDocument": {
#            "Version": "2012-10-17",
#            "Statement": [
#                {
#                    "Effect": "Allow",
#                    "Principal": {
#                        "Service": "lambda.amazonaws.com"
#                    },
#                    "Action": "sts:AssumeRole"
#                }
#            ]
#        },
#        "MaxSessionDuration": 3600
#    }
#}

EXEC_ROLE_POLICY=$(cat <<'END_HEREDOC'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "arn:aws:s3:::mediaLibrary/*"
            ]
        }
    ]
}
END_HEREDOC
)

aws --endpoint-url=http://localhost:4566 iam create-policy --policy-name $LAMBDA_EXEC_ROLE_POLICY_NAME --policy-document "$EXEC_ROLE_POLICY"
#{
#    "Policy": {
#        "PolicyName": "gppge",
#        "PolicyId": "A2MBMR5DBZE6XQ9V7F3FD",
#        "Arn": "arn:aws:iam::000000000000:policy/gppge",
#        "Path": "/",
#        "DefaultVersionId": "v1",
#        "AttachmentCount": 0,
#        "CreateDate": "2021-02-01T09:42:42.826000+00:00",
#        "UpdateDate": "2021-02-01T09:42:42.826000+00:00"
#    }
#}


echo "Attaching AWSLambdaBasicExecutionRole policy to Role..."
aws --endpoint-url=http://localhost:4566 iam attach-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
aws --endpoint-url=http://localhost:4566 iam attach-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-arn arn:aws:iam::000000000000:policy/$LAMBDA_EXEC_ROLE_POLICY_NAME

echo "Creating it's zip version..."
cd app/lambda/
echo index.js

zip -r function.zip .

cd ../../

echo "Creating lambda function..."
FUNCTION_CREATION=$( \
aws --endpoint-url=http://localhost:4566 lambda create-function \
--function-name "$LAMBDA_FUNCTION_NAME" \
--zip-file fileb://app/lambda/function.zip \
--handler index.handler \
--runtime nodejs12.x \
--environment '{"Variables": {"SOURCE_BUCKET": "mediaLibrary", "ENV": "local"}}' \
--role "$LAMBDA_FUNCTION_ROLE_ARN")


LAMBDA_FUNCTION_ARN=$(echo "$FUNCTION_CREATION" | jq -r ".FunctionArn")

#{
#    "FunctionName": "test-lambda-function",
#    "FunctionArn": "arn:aws:lambda:eu-west-1:000000000000:function:test-lambda-function",
#    "Runtime": "nodejs12.x",
#    "Role": "arn:aws:iam::000000000000:role/test-lambda-role",
#    "Handler": "index.handler",
#    "CodeSize": 409,
#    "Description": "",
#    "Timeout": 3,
#    "LastModified": "2021-01-30T17:06:43.825+0000",
#    "CodeSha256": "mh4C/VDrChFKnIii9RCj09Avllu5n12xShVEFM1+rlM=",
#    "Version": "$LATEST",
#    "VpcConfig": {},
#    "TracingConfig": {
#        "Mode": "PassThrough"
#    },
#    "RevisionId": "7f0244e4-ce20-499a-8868-f7395e015b01",
#    "State": "Active",
#    "LastUpdateStatus": "Successful",
#    "PackageType": "Zip"
#}

echo "Testing lambda function..."
INVOKATION="$(aws --endpoint-url=http://localhost:4566 lambda invoke --function-name "$LAMBDA_FUNCTION_NAME" --log-type Tail out)"
#INVOKATION=$(aws --endpoint-url=http://localhost:4566 lambda invoke --function-name "$LAMBDA_FUNCTION_NAME" --log-type Tail out --query 'LogResult' --output text |  base64 -d)

#INVOKATION
#{
#    "StatusCode": 200,
#    "FunctionError": "Unhandled",
#    "LogResult": "",
#    "ExecutedVersion": "$LATEST"
#}

API_GATEWAY_REST_API_NAME="$NAME-rest-api"

CREATE_REST_API="$(aws --endpoint-url=http://localhost:4566 apigateway create-rest-api --name "$API_GATEWAY_REST_API_NAME" --binary-media-types "*/*")"
REST_API_ID="$(echo "$CREATE_REST_API" | jq -r ".id")"

# CREATE_REST_API
#{
#    "id": "kfgi1srm3c",
#    "name": "test-rest-api",
#    "createdDate": 1612027138,
#    "apiKeySource": "HEADER",
#    "endpointConfiguration": {
#        "types": [
#            "EDGE"
#        ]
#    },
#    "tags": {}
#}



#API_GATEWAY_RESOURCES="$(aws --endpoint-url=http://localhost:4566  apigateway get-resources --rest-api-id "$REST_API_ID")"
API_GATEWAY_RESOURCE_ID=$(aws --endpoint-url=http://localhost:4566  apigateway get-resources --rest-api-id "$REST_API_ID" | jq -r '.items[0].id')
# API_GATEWAY_RESOURCES
#{
#    "items": [
#        {
#            "id": "e83csxk019",
#            "path": "/"
#        }
#    ]
#}

GATEWAY_RESOURCE=$(aws --endpoint-url=http://localhost:4566 apigateway create-resource \
--rest-api-id "$REST_API_ID" \
--parent-id "$API_GATEWAY_RESOURCE_ID" \
--path-part greeting\
)
GATEWAY_RESOURCE_ID="$(echo "$GATEWAY_RESOURCE" | jq -r ".id")"

# GATEWAY_RESOURCE
#{
#    "id": "vc0kxkfwmo",
#    "parentId": "e83csxk019",
#    "pathPart": "greeting",
#    "path": "/greeting"
#}


aws --endpoint-url=http://localhost:4566 apigateway put-method \
--rest-api-id "$REST_API_ID" \
--resource-id "$GATEWAY_RESOURCE_ID" \
--http-method GET \
--authorization-type "NONE" \
--request-parameters method.request.path.greeting=true


aws --endpoint-url=http://localhost:4566 apigateway put-integration \
--rest-api-id "$REST_API_ID" \
--resource-id "$GATEWAY_RESOURCE_ID" \
--http-method GET \
--type AWS_PROXY \
--integration-http-method POST \
--passthrough-behavior WHEN_NO_MATCH \
--content-handling CONVERT_TO_TEXT \
--uri arn:aws:apigateway:eu-west-1:lambda:path/2015-03-31/functions/"$LAMBDA_FUNCTION_ARN"


aws --endpoint-url=http://localhost:4566 apigateway create-deployment --rest-api-id "$REST_API_ID" --stage-name test


aws --endpoint-url=http://localhost:4566 apigateway put-integration-response \
--rest-api-id "$REST_API_ID" \
--resource-id "$GATEWAY_RESOURCE_ID" \
--http-method GET \
--status-code 200 \
--selection-pattern ".*" \
--content-handling CONVERT_TO_BINARY

#aws --endpoint-url=http://localhost:4566 apigateway put-integration-response \
#--rest-api-id "$REST_API_ID" \
#--resource-id "$GATEWAY_RESOURCE_ID" \
#--http-method GET \
#--status-code 200 \
#--patch-operations '[{"op" : "replace", "path" : "/contentHandling", "value" : "CONVERT_TO_BINARY"}]'


#aws --endpoint-url=http://localhost:4566 apigateway put-integration-response \
#--rest-api-id "$REST_API_ID" \
#--resource-id "$GATEWAY_RESOURCE_ID" \
#--http-method GET \
#--status-code 200 \
#--content-handling 'CONVERT_TO_BINARY'


aws --endpoint-url=http://localhost:4566 apigateway create-deployment --rest-api-id "$REST_API_ID" --stage-name test
#{
#    "id": "u71iexwcjc",
#    "description": "",
#    "createdDate": 1612050311
#}

curl http://localhost:4566/restapis/"$REST_API_ID"/test/_user_request_/greeting

set +x

