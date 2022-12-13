#!/usr/bin/env bash
#
# pCloud uploader 
#
# Copyright (C) 2022 Hani Hammadeh @hanihammadeh
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.


CURL_BIN=$(which curl) 
CURL_OPT=' -s'
JQ_BIN=$(which jq)
END_POINT="https://u.pcloud.com"
API_LOGIN="https://api.pcloud.com/login"
API_AUTH_URL="${END_POINT}/oauth2"
API_AUTH_TOKEN_URL="https://api.pcloud.com/oauth2_token"
API_LIST_FOLDER_URL="https://api.pcloud.com/listfolder"
API_UPLOAD_FILE="https://api.pcloud.com/uploadfile"
API_FILE_PUBLIC_LINK="https://api.pcloud.com/getfilepublink"
API_LIST_PUBLIC_LINKS="https://api.pcloud.com/listpublinks"
CONFIG_FILE="./.pcloud_config"
VERSION="1.0"

source "${CONFIG_FILE}"
#CONFIG_FILE has the following parameters:
##EMAIL_ADDRESS=" Your pCloud Email Address"
##PASSWORD="Your pCloud Login password"
##CLIENT_ID=" Your APP pCloud Client ID"
##CLIENT_SECRET="Your APP pCloud Client Secret"

function usage
{
    echo -e "pCloud Uploader v$VERSION"
    echo -e "Hani Hammadeh - @hanihammadeh\n"
    echo -e "Usage: $0 [PARAMETERS] COMMAND..."
    echo -e "\nCommands:"
    echo -e "\t --list   <REMOTE_DIR_ID> "
    echo -e "\t --list-remote-dir "
    echo -e "\t --help   show this help message"
    echo -en "\nFor more info and examples, please see the README file.\n\n"
    exit 1
}


function login() {
$CURL_BIN  $CURL_OPT "${API_LOGIN}" \
  -H 'Accept: application/json, text/javascript, */*; q=0.01' \
  -H 'Accept-Language: en-US,en;q=0.9' \
  -H 'Connection: keep-alive' \
  -H 'Content-Type: application/x-www-form-urlencoded; charset=UTF-8' \
  --data-urlencode username="${EMAIL_ADDRESS}" \
  --data-urlencode password="${PASSWORD}" \
  --compressed
}

#login

function get_code_token() {
$CURL_BIN $CURL_OPT "${END_POINT}/oauth2/authorize?client_id=$CLIENT_ID&response_type=code&auth=$AUTH_ID" \
  -H 'Accept: text/html,application/xhtml+xml,application/xml' \
  -H 'Accept-Language: en-US,en;q=0.9' \
  -H 'Connection: keep-alive' \
  --compressed
}

function get_access_token(){
$CURL_BIN $CURL_OPT --location --request POST "${API_AUTH_TOKEN_URL}" \
--header 'Content-Type: application/x-www-form-urlencoded' \
--header 'Accept: application/json' \
--data-urlencode client_id=$CLIENT_ID \
--data-urlencode client_secret=$CLIENT_SECRET \
--data-urlencode code=$1

}

function list_root_folder(){

$CURL_BIN $CURL_OPT --location --request POST "${API_LIST_FOLDER_URL}" \
--header "Authorization: Bearer $1" \
--header "Content-Type: application/x-www-form-urlencoded" \
--data-urlencode folderid=0

}

function pretty_list_root_folder(){
  list_root_folder $access_token|jq -r '(["PATH","NAME","FOLDERID"]),(.metadata.contents[]|[.path, .name, .folderid])|@tsv'
}


function list_dir(){

curl -s --location --request POST "${API_LIST_FOLDER_URL}" \
--header "Authorization: Bearer $1" \
--header "Content-Type: application/x-www-form-urlencoded" \
--data-urlencode folderid=$2


}
function pretty_list_dir(){
	list_dir  $access_token $1|jq -r '(["NAME", "FILEID"]),(.metadata.contents[]|[.name, .fileid])|@tsv'
}

function download_file(){
  ### $1 refers to the file id
  ### $2 refers to the AUTH_ID, authinication id
  tmpfile=$(mktemp)
  $CURL_BIN $CURL_OPT --location -XPOST "https://api.pcloud.com/getfilelink?fileid=$1&auth=$2" \
  -H "Accept: application/json, text/javascript, */*; q=0.01" \
  -H "Accept-Language: en-US,en;q=0.9,ar;q=0.8" \
  -H "Connection: keep-alive" \
  --compressed > "${tmpfile}"

  filepath=$(jq -r '.path' "${tmpfile}")
  filehost=$(jq -r '.hosts[0]' "${tmpfile}")
  filename="${filepath##*/}"
  $CURL_BIN $CURL_OPT -o "${filename}" https://"${filehost}""${filepath}"
  rm -rf "${tmpfile}"
}

function upload_file(){
#### $1 filename
#### $2 folder id
#### The function will return the file id
echo $1, $2
$CURL_BIN  -XPOST "${API_UPLOAD_FILE}?folderid=$2&auth=${AUTH_ID}" \
  -H "Accept: application/json, text/javascript, */*; q=0.01" \
  -H "Accept-Language: en-US,en;q=0.9,ar;q=0.8" \
  -H "Connection: keep-alive" \
  -H "Content-Type: multipart/form-data" \
  -F "filename=@$1" \
  --compressed
}
function get_file_public_link(){
### $1 is the file id to share
$CURL_BIN $CURL_OPT "${API_FILE_PUBLIC_LINK}?fileid=$1&auth=${AUTH_ID}" \
  -H "Accept: application/json, text/javascript, */*; q=0.01" \
  -H "Accept-Language: en-US,en;q=0.9,ar;q=0.8" \
  -H "Connection: keep-alive" \
  --compressed| $JQ_BIN -r '.link'
}
function list_public_links(){
  $CURL_BIN $CURL_OPT "${API_LIST_PUBLIC_LINKS}?auth=${AUTH_ID}" \
  -H "Accept: application/json, text/javascript, */*; q=0.01" \
  -H "Accept-Language: en-US,en;q=0.9,ar;q=0.8" \
  -H "Connection: keep-alive" \
  --compressed|$JQ_BIN -r '.publinks[].link'
}
##############################################
###########START##############################
##############################################

# get the authntication ID
AUTH_ID=$(login|jq -r '.auth')
#echo auth_id is $AUTH_ID
# get the assoociated code
code=$(echo "$(get_code_token)"|grep 'class="code"'| sed 's/<[^>]*>//g'|head -1)
#echo code is $code
# get the access token
access_token=$(get_access_token $code |jq -r '.access_token')
#echo access_token is $access_token
# read cli options
! getopt --test > /dev/null 
if [[ ${PIPESTATUS[0]} -ne 4 ]]; then
    echo 'I’m sorry, `getopt --test` failed in this environment.'
    exit 1
fi

LONGOPTS=list-root-dir,list-dir:,download-file:,upload-file:,folder-id:,share-file:,list-public-links,help
OPTIONS=lr:d:u:i:s:Lh
! PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    exit 2
fi
eval set -- "$PARSED"
while true; do
    case "$1" in
        -l|--list-root-dir)
            pretty_list_root_folder
            shift
            ;;
        -L|--list-public-links)
            list_public_links
            shift
            ;;
        -r|--list-dir)
            pretty_list_dir $2
	    #list_dir $access_token $2
            shift 2
            ;;
        -d| --download-file)
            download_file $2 $AUTH_ID
            shift 2
            ;;
        -u| --upload-file)
            upload_file $2 $4
            shift 4
            ;;
        -s| --share-file)
            get_file_public_link $2 
            shift 2
            ;;
        -h|--help)
            usage
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Error"
            exit 3
            ;;
    esac
done
