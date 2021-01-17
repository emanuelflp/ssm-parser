#!/usr/local/bin/bash
set -e

function main() {
  sanitize "${INPUT_ACCESS_KEY_ID}" "access_key_id"
  sanitize "${INPUT_SECRET_ACCESS_KEY}" "secret_access_key"
  sanitize "${INPUT_REGION}" "region"
  sanitize "${INPUT_ACCOUNT_ID}" "account_id"
  sanitize "${INPUT_TASK_DEFINITION}" "task_definition"

  TMP_SSM_FILE=$(mktemp)
  TMP_SSM_PARSED_FILE=$(mktemp)
  TMP_TD_CONTAINER_PARSED_FILE=$(mktemp)
  CONTAINER_EXISTS=0
  aws_configure
  assume_role
  get_ssm_parameters
  parse_ssm_file
  change_task_definition_file
  rm -f $TMP_SSM_FILE
  rm -f $TMP_SSM_PARSED_FILE
  rm -f $TMP_TD_CONTAINER_PARSED_FILE
  unset TMP_SSM_FILE
  unset TMP_SSM_PARSED_FILE
  unset TMP_TD_CONTAINER_PARSED_FILE


}

function sanitize() {
  if [ -z "${1}" ]; then
    >&2 echo "Unable to find the ${2}. Did you set with.${2}?"
    exit 1
  fi
}

function aws_configure() {
  export AWS_ACCESS_KEY_ID=$INPUT_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY=$INPUT_SECRET_ACCESS_KEY
  export AWS_DEFAULT_REGION=$INPUT_REGION
}

function assume_role() {
  if [ "${INPUT_ASSUME_ROLE}" != "" ]; then
    sanitize "${INPUT_ASSUME_ROLE}" "assume_role"
    echo "== START ASSUME ROLE"
    ROLE="arn:aws:iam::${INPUT_ACCOUNT_ID}:role/${INPUT_ASSUME_ROLE}"
    CREDENTIALS=$(aws sts assume-role --role-arn ${ROLE} --role-session-name ecrpush --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text)
    read id key token <<< ${CREDENTIALS}
    export AWS_ACCESS_KEY_ID="${id}"
    export AWS_SECRET_ACCESS_KEY="${key}"
    export AWS_SESSION_TOKEN="${token}"
    echo "== FINISHED ASSUME ROLE"
  fi
}

function parse_ssm_file() {
    jq --arg replace "$INPUT_SSM_PATH" 'walk(if type == "object" and has("name") then .name |= gsub($replace;"") else . end)' -c "$TMP_SSM_FILE" > "$TMP_SSM_PARSED_FILE"
}

function change_task_definition_file() {
    local td_empty_container=$(jq "del(.containerDefinitions[])" "$INPUT_TASK_DEFINITION")
    for row in $(jq -r '.containerDefinitions[] | @base64' "${INPUT_TASK_DEFINITION}" ); do
      local app_name
      app_name=$(echo "${row}" | base64 --decode | jq -r '.name')
      if [ "$app_name" == "$INPUT_CONTAINER_NAME" ]; then
          echo "$row" | jq ".secrets = $(cat $TMP_SSM_PARSED_FILE)" > "$TMP_TD_CONTAINER_PARSED_FILE"
          CONTAINER_EXISTS=1
      fi
      td_empty_container=$(echo $td_empty_container | jq ".containerDefinitions += $(cat $TMP_TD_CONTAINER_PARSED_FILE)")
    done
    if [ ! $CONTAINER_EXISTS ]; then
        echo "Container not exists in Task definition file."
        exit 1
    else
      echo "$td_empty_container" > task-definition-rendered.json
    fi
    echo ::set-output name=task-definition::task-definition-rendered.json
}

function get_ssm_parameters() {
    aws ssm --region "$INPUT_REGION" get-parameters-by-path --path "$INPUT_SSM_PATH" --query "Parameters[*].{name:Name,valueFrom:ARN}" > "$TMP_SSM_FILE"
}

main

