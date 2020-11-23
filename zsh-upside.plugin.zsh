#!/usr/bin/env bash
# shellcheck disable=SC1090

__aws_is_authenticated() {
  if [[ -z "${AWS_ACCESS_KEY_ID}" ]]
  then
    return 1
  fi
  if [[ -z "${AWS_SECRET_ACCESS_KEY}" ]]
  then
    return 1
  fi
  if [[ -z "${AWS_SESSION_TOKEN}" ]]
  then
    return 1
  fi

  return 0
}

__aws_eks_list_clusters() {
  aws eks list-clusters | jq -r '.clusters[]'
}

__aws_eks_update_kubeconfig() {
  local clustername="${1}"
  aws eks update-kubeconfig --name $clustername --alias $clustername
}

__aws_get_caller_identity() {
  if [[ $commands[aws] ]]
  then
    aws sts get-caller-identity
  else
    echo "this command requires aws cli to be installed"
  fi
}

awslogin_usage() {
  cat <<- EOF

  authenticate to aws using sso login profile

  usage: $0 <profile> 

    profile : aws named profile https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html

EOF
}

awslogin() {
  local profile="$1"
  if [[ ! "$profile" = "" ]]
  then
    if [[ $commands[aws2-wrap] ]]
    then
      aws sso login --profile="$profile"
      eval "$(aws2-wrap --profile "$profile" --export)"
      __aws_get_caller_identity
    else
      echo "this command requires aws2-wrap to be installed"
      exit 1
    fi
  else
    awslogin_usage
  fi
}

awslogout() {
  if [[ $commands[aws] ]] 
  then
    aws sso logout
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    __aws_get_caller_identity
  else
    echo "this command requires aws cli to be installed"
  fi
}

######################################################
# Kubernetes cluster connection functions
######################################################

# # accept tier and color and return properly formatted cluster name
# kcluster() {
#   local tier="${1}"
#   local color="${2}"
#   local kubeCluster=""

#   case "$tier" in
#   'alpha') kubeCluster="little-dipper-${color}";;
#   'dev') kubeCluster="${color}";;
#   'prod') kubeCluster="big-dipper-${color}";;
#   esac

#   if [ -z "$kubeCluster" ]
#   then
#       echo -n "Name of cluster:"
#       read kubeCluster
#   fi

#   echo "$kubeCluster"
# }

klogin() {
  if __aws_is_authenticated
  then
    echo "select eks cluster to fetch kubeconfig"
    select clustername in $(__aws_eks_list_clusters)
    do
      __aws_eks_update_kubeconfig "$clustername"
      [[ $commands[kubectx] ]] && kubectx
      [[ $commands[kubens] ]] && kubens
      [[ $commands[k9s] ]] && k9s
      break
    done
  else
    echo "aws session vars not found -- run awslogin first"
  fi
}

# # accept tier and color and initiate authenitcated session
# klogin() {
#   local kubeCluster="$(kcluster "$@")"

#   echo "You are logging into $kubeCluster..."
#   response=$(aws sts assume-role --role-arn arn:aws:iam::337068080576:role/UpsideEKSAdministratorRole --role-session-name rsherman)
#   export AWS_ACCESS_KEY_ID=$(echo $response | jq -r .Credentials.AccessKeyId)
#   export AWS_SECRET_ACCESS_KEY=$(echo $response | jq -r .Credentials.SecretAccessKey)
#   export AWS_SESSION_TOKEN=$(echo $response | jq -r .Credentials.SessionToken)
#   aws sts get-caller-identity
#   kfetch "$@"
# }

# terminate authenticated session
klogout() {
  awslogout
  # unset AWS_ACCESS_KEY_ID
  # unset AWS_SECRET_ACCESS_KEY
  # unset AWS_SESSION_TOKEN
  # aws sts get-caller-identity
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
