.ONESHELL:
SHELL := /bin/bash

stop:
	CONTAINER_ID=$$( @devcontainer --workspace-folder . up  | tail -n 1 | jq -r '.containerId[0:-1]')
	@docker stop $$CONTAINER_ID

update:
	@devcontainer --workspace-folder . up --remove-existing-container

build:
	@devcontainer --workspace-folder . build

up:
	WORKSPACE_NAME=$$(basename "$$(pwd)")
	WORKSPACE_FOLDER=/workspaces/$$WORKSPACE_NAME 
	CONTAINER_ID=$$(devcontainer --workspace-folder . up  | tail -n 1 | jq -r '.containerId[0:-1]')
	@docker exec -itw $$WORKSPACE_FOLDER $$CONTAINER_ID bash

act_kubectl:
	@act --job kubectl -P ghcr.io/catthehacker/ubuntu:act-22.04 --secret OP_SERVICE_ACCOUNT_TOKEN=$$( op read op://$$PROJECT_ENV/actions-kubectl/OP_SERVICE_ACCOUNT_TOKEN) 

kubectl_updatesecret:
	B64_DB_URL=$$(echo -n $$DB_URL | base64 -w 0)
	SECRET_JSON=$$(op run -- kubectl get secret coder-db-url -o json -n coder)
	NEW_SECRET_JSON=$$(echo $$SECRET_JSON | jq ".data.url=\"$$B64_DB_URL\"")
	echo $$NEW_SECRET_JSON | op run -- kubectl apply -f -

kubectl_restartdeployment:
	op run -- kubectl rollout restart deployment coder -n coder

kubectl_getsecret:
	op run -- kubectl get secret coder-db-url -o json -n coder

kubectl_setup:
	op run -- aws eks update-kubeconfig --region eu-south-1 --name cloud-dev-infra

kubectl_apply:
	op run -- kubectl apply -f ./k8s/manifest.yml

helm:
	op run -- helm repo add coder-v2 https://helm.coder.com/v2
	op run -- helm upgrade --install coder coder-v2/coder \
		--namespace coder \
		--values ./k8s/values.yml \
		--version 2.13.5
kubectl_getpods:
	op run -- kubectl get pods -n coder

kubectl_deploy:
	make kubectl_setup
	make kubectl_apply
	make helm
	make kubectl_updatesecret
	make kubectl_restartdeployment

