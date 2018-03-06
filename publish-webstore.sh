#!/usr/bin/env bash

###################################################################
#                                                                 #
# Name:  publish-webstore.sh                                      #
#                                                                 #
# Descr: Upload a new version of an existing                      #
#        Chrome Web Store item and publish it                     #
#                                                                 #
# Ref:   https://developer.chrome.com/webstore/using_webstore_api #
#        https://developer.chrome.com/webstore/api_index          #
#                                                                 #
###################################################################

echo -e '\n\e[33mRunning publish-webstore.sh with arguments:\e[0m'
echo -e "$@"

###################
# Parse arguments #
###################

while [ $# -gt 0 ]; do
    case $1 in
        -f|--file)
        FILE_NAME=$2
        shift
        ;;
        -id|--extension-id)
        EXTENSION_ID=$2
        shift
        ;;
        -t|--target) #default|trustedTesters|unlisted
        PUBLISH_TARGET=$2
        shift
        ;;
        -ci|--client-id)
        CLIENT_ID=$2
        shift
        ;;
        -cs|--client-secret)
        CLIENT_SECRET=$2
        shift
        ;;
        -rt|--refresh-token)
        REFRESH_TOKEN=$2
        shift
        ;;
        *)
        ;;
    esac
	shift
done

######################################################################
# Declare a common function to manage Chrome Web Store API responses #
######################################################################

manage_api_response() {

    local CALL_TYPE=$1
    local EXPECTED_KEY=$2
    local EXPECTED_VALUE=$3

    #2xx OK Status Code
    if [[ ${HTTP_CODE} =~ ^2[0-9]{2}$ ]]; then

        STATUS=$(grep -Po '"'${EXPECTED_KEY}'":\[?"(\K[^"]*)' api-response.json)

        #The JSON response contains the EXPECTED_KEY and EXPECTED_VALUE
        if [[ ${STATUS} == ${EXPECTED_VALUE} ]]; then
            echo -e '\n\e[32m'${CALL_TYPE}' SUCCEDEED!'
            EXIT_CODE=0

        #The JSON response contains an error
        else
            echo -e '\n\e[31m'${CALL_TYPE}' FAILED!'
            EXIT_CODE=-2
        fi

    #NOT OK Status Code
    else
        echo -e '\n\e[31m'${CALL_TYPE}' FAILED!'
        EXIT_CODE=-1
    fi

    #Show Webstore API response
    cat api-response.json
    echo -en "\n\n\e[0m"

    #Exit if error
    if [[ ${EXIT_CODE} != 0 ]]; then
        exit ${EXIT_CODE}
    fi

}

###################################
# Get a valid Oauth2 access token #
###################################

echo -e '\n\e[33mGetting OAuth2 access token using existing refresh token...\n\e[0m'

TOKEN_INFO=$(curl "https://www.googleapis.com/oauth2/v4/token" \
    -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&refresh_token=$REFRESH_TOKEN&grant_type=refresh_token")

#Log & exit in case of auth error
if [[ ${TOKEN_INFO} =~ error ]]; then
    echo -e '\n\e[31mGetting OAuth2 access token FAILED!'
    echo -e '\n\e[31m'${TOKEN_INFO}'\n\e[0m'
    exit -1
fi

ACCESS_TOKEN=$(expr "$TOKEN_INFO" : '.*"access_token": "\([^"]*\)"')

##################################################################
# Upload the extension package to update the existing store item #
##################################################################

echo -e '\n\e[33mUploading "'${FILE_NAME}'" to the Chrome Web Store item with id "'${EXTENSION_ID}'"...\n\e[0m'

HTTP_CODE=$(curl \
-w %{http_code} \
-o api-response.json \
-H "Authorization: Bearer $ACCESS_TOKEN" \
-H "x-goog-api-version: 2" \
-X PUT \
-T ${FILE_NAME} \
-v https://www.googleapis.com/upload/chromewebstore/v1.1/items/${EXTENSION_ID})

manage_api_response Upload uploadState SUCCESS

############################################################
# Publish the existing store item if PUBLISH_TARGET is set #
############################################################

if [ -n "$PUBLISH_TARGET" ]; then

    echo -e '\e[33mPublishing Chrome Web Store item with id "'${EXTENSION_ID}'"...\n\e[0m'

    # In case of 'unlisted' target, only passing 'publishTarget' as a request header works
    if [[ ${PUBLISH_TARGET} == 'unlisted' ]]; then
        HTTP_CODE=$(curl \
        -w %{http_code} \
        -o api-response.json \
        -H "Authorization: Bearer $ACCESS_TOKEN"  \
        -H "x-goog-api-version: 2" \
        -H "Content-Length: 0" \
        -H "publishTarget: $PUBLISH_TARGET" \
        -X POST \
        -v https://www.googleapis.com/chromewebstore/v1.1/items/${EXTENSION_ID}/publish)
    # For other targets ('default' or 'trustedTesters') we must pass 'target' as request body in json format
    else
        HTTP_CODE=$(curl \
        -w %{http_code} \
        -o api-response.json \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "x-goog-api-version: 2" \
        -H "Content-Type: application/json" \
        -d "{\"target\":\"$PUBLISH_TARGET\"}" \
        -X POST \
        -v https://www.googleapis.com/chromewebstore/v1.1/items/${EXTENSION_ID}/publish)
    fi

    manage_api_response Publish status OK

else
    echo -e '\e[33mPublication SKIPPED as PUBLISH_TARGET (-t|--target) was'\
        'not specified.\nItem has only been uploaded to the store (draft)\n\n\e[0m'
fi
