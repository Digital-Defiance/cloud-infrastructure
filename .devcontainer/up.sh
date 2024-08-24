WORKSPACE_NAME=$(basename "$(pwd)")
docker exec -itw /workspaces/$WORKSPACE_NAME $(devcontainer up | tail -n 1 | jq -r '.containerId[0:-1]') bash
