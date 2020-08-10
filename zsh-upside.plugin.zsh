#!/usr/bin/env sh
# shellcheck disable=SC1090

######################################################
# Kubernetes cluster connection functions
######################################################

# accept tier and color and return properly formatted cluster name
kcluster() {
  local tier="${1}"
  local color="${2}"
  local kubeCluster=""

  case "$tier" in
  'alpha') kubeCluster="little-dipper-${color}";;
  'dev') kubeCluster="${color}";;
  'prod') kubeCluster="big-dipper-${color}";;
  esac

  if [ -z "$kubeCluster" ]
  then
      echo -n "Name of cluster:"
      read kubeCluster
  fi

  echo "$kubeCluster"
}

# accept tier and color fetch kubeconfig for cluster
kfetch() {
  local kubeCluster="$(kcluster "$@")"
  aws eks update-kubeconfig --name $kubeCluster  # To update your ~/.kube/config
}

# accept tier and color and initiate authenitcated session
klogin() {
  local kubeCluster="$(kcluster "$@")"

  echo "You are logging into $kubeCluster..."
  response=$(aws sts assume-role --role-arn arn:aws:iam::337068080576:role/UpsideEKSAdministratorRole --role-session-name rsherman)
  export AWS_ACCESS_KEY_ID=$(echo $response | jq -r .Credentials.AccessKeyId)
  export AWS_SECRET_ACCESS_KEY=$(echo $response | jq -r .Credentials.SecretAccessKey)
  export AWS_SESSION_TOKEN=$(echo $response | jq -r .Credentials.SessionToken)
  aws sts get-caller-identity
  kfetch "$@"
}

# terminate authenticated session
klogout() {
  unset AWS_ACCESS_KEY_ID
  unset AWS_SECRET_ACCESS_KEY
  unset AWS_SESSION_TOKEN
  aws sts get-caller-identity
}

# accept tier and color open cluster dashboard
kdashlogin() {
  klogin "$@"
  kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep eks-admin | awk '{print $1}') | grep "^token" | awk '{print $2}' | pbcopy
  kubectl proxy &
  open 'http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/.'
}

# terminate dashboard connection
kdashlogout() {
  kill $(lsof -t -i:8001)
}
