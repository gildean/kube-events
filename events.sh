#! /bin/bash
set -euo pipefail
# setting LANG gives correct timestamps
LANG=fi_FI.UTF-8
# set defaults
: "${API_SERVER_ADDRESS:=https://minikube:8443/api/v1/watch/events}"
: "${TOKEN:=}"
: "${openshift:=}"

usage() {
    echo "
$0 [ options ]
  -o|--openshift
    use openshift (requires oc login)
  -t|--token <TOKEN>
    use the provided TOKEN as Bearer token
  -c|--cacert <CA_CERT>
    use the provided CA_CERT file
  -h|--help
    print this help
"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help )
            usage
            exit 0
            ;;
        -o|--openshift )
            openshift="true"
            ;;
        -t|--token )
            TOKEN="$1"
            shift
            ;;
        -c|--cacert )
            CA_CERT="$1"
            shift
            ;;
        * )
           echo "unknown argument"
           exit 2
           ;;
    esac
    shift
done

if [[ -n $openshift ]]; then
    if ! oc whoami &> /dev/null; then echo "login to oc first" && exit 1; fi
    TOKEN=$(oc whoami -t)
elif [[ -z $TOKEN ]]; then
    secret=$(kubectl get serviceaccount default -o json | jq -r '.secrets[].name')
    TOKEN=$(kubectl get secret $secret -o yaml | grep "token:" | awk {'print $2'} |  base64 -d)
    : "${CA_CERT:=~/.minikube/ca.pem}"
fi
# print timestamp in the middle of the row every 60s
while sleep 60; do
    columns=$(tput cols)
    timestamp="---> $(date +'%x %X') <---"
    printf "%*s\n" $(((${#timestamp}+$columns)/2)) "$timestamp"
done &

# kill children at exit
trap 'kill $(jobs -p) &> /dev/null' EXIT

select_kindcolor() {
    case $1 in
        "Pod" )
            printf "\e[38;5;152m"
            ;;
        "DeploymentConfig" )
            printf "\e[38;5;92m"
            ;;
        "Node" )
            printf "\e[38;5;171m"
            ;;
        * )
            printf "\e[38;5;222m"
            ;;
    esac
}

select_eventcolor() {
    if [[ $1 == "Normal" ]]; then
        printf "\e[38;5;154m"
    else
        printf "\e[38;5;198m"
    fi
}

select_reasoncolor() {
    if [[ $1 == "Unhealthy" ]]; then
        printf "\e[5m\e[38;5;172m"
    else
        printf "\e[38;5;121m"
    fi
}

# colors to vars
dim="\e[90m"
mid="\e[38;5;245m"
bright="\e[97m"
green="\e[38;5;121m"
pink="\e[38;5;201m"
rst="\e[0m"

# commands as arrays
curl_cmd=(curl -s -k -H "Accept: application/json")
if [[ -n $TOKEN ]]; then
    curl_cmd+=(-H "Authorization: Bearer $TOKEN")
fi
if [[ -n $CA_CERT ]]; then
    curl_cmd+=(--cacert "$CA_CERT")
fi
curl_cmd+=("$API_SERVER_ADDRESS")
jq_cmd=(jq --unbuffered -r)
jq_cmd+=('[.object.type, .object.involvedObject.namespace // " ", .object.involvedObject.name, .object.involvedObject.kind, .object.reason, .object.metadata.creationTimestamp, (.object.message // "" | gsub("\\n"; " "))] | @tsv')

while IFS=$'\t' read -r eventtype namespace service kind reason eventtime message; do

    nscolor="$green"
    namespace="${namespace%"${namespace##*[![:space:]]}"}"
    [[ -z $namespace ]] && namespace=infra && nscolor="$pink"
    eventtime=$(date -d $eventtime +'%x %X')
    kindcolor=$(select_kindcolor "$kind")
    eventcolor=$(select_eventcolor "$eventtype")
    reasoncolor=$(select_reasoncolor "$reason")

    printf "${dim}%-19s${rst} - ${eventcolor}%-7s${rst} | ${nscolor}%-15s${rst} ${bright}%-37s${rst} ${kindcolor}%-21s${rst} ${reasoncolor}%-28s${rst} ${mid}%s${rst}\n" "${eventtime}" "${eventtype}" "${namespace}" "${service}" "${kind}" "${reason}" "${message}"

done < <("${curl_cmd[@]}" | "${jq_cmd[@]}")
