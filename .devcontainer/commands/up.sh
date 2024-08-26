WORKSPACE_NAME=$(basename "$(pwd)")
WORKSPACE_FOLDER=/workspaces/$WORKSPACE_NAME 
CONTAINER_ID=$(devcontainer --workspace-folder . up  | tail -n 1 | jq -r '.containerId[0:-1]')
docker exec -itw $WORKSPACE_FOLDER $CONTAINER_ID bash
