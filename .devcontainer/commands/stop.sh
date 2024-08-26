CONTAINER_ID=$(devcontainer --workspace-folder . up  | tail -n 1 | jq -r '.containerId[0:-1]')
docker stop $CONTAINER_ID
