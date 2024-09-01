"""A generated module for CloudInfrastructure functions

This module has been generated via dagger init and serves as a reference to
basic module structure as you get started with Dagger.

Two functions have been pre-created. You can modify, delete, or add to them,
as needed. They demonstrate usage of arguments and return types using simple
echo and grep commands. The functions can be called from the dagger CLI or
from one of the SDKs.

The first line in this comment block is a short description line and the
rest is a long description with more detail on the module's purpose or usage,
if appropriate. All modules should have a short description.
"""
import json
import dagger
from dagger import dag, function, object_type, Doc
from typing import Annotated, TypedDict
# NOTE: it's recommended to move your code into other files in this package
# and keep __init__.py for imports only, according to Python's convention.
# The only requirement is that Dagger needs to be able to import a package
# called "main", so as long as the files are imported here, they should be
# available to Dagger.


# {
#   "ami": {
#     "sensitive": false,
#     "type": "string",
#     "value": "ami-08ecf9619db5cca63"
#   },
#   "db_instance_endpoint": {
#     "sensitive": false,
#     "type": "string",
#     "value": "cloud-infra-db-3.cvyy642s26z4.eu-south-1.rds.amazonaws.com:5432"
#   },
#   "db_instance_master_username": {
#     "sensitive": false,
#     "type": "string",
#     "value": "postgresqlcloudinfra"
#   },
#   "security_group_id": {
#     "sensitive": false,
#     "type": "string",
#     "value": "sg-055738e3ba043a8ad"
#   },
#   "subnet_ids": {
#     "sensitive": false,
#     "type": [
#       "object",
#       {
#         "filter": [
#           "set",
#           [
#             "object",
#             {
#               "name": "string",
#               "values": [
#                 "set",
#                 "string"
#               ]
#             }
#           ]
#         ],
#         "id": "string",
#         "ids": [
#           "list",
#           "string"
#         ],
#         "tags": [
#           "map",
#           "string"
#         ],
#         "timeouts": [
#           "object",
#           {
#             "read": "string"
#           }
#         ]
#       }
#     ],
#     "value": {
#       "filter": null,
#       "id": "eu-south-1",
#       "ids": [
#         "subnet-0272c23b5517b276f",
#         "subnet-0114c45013a2514a6",
#         "subnet-067307c45c192c875"
#       ],
#       "tags": {
#         "kubernetes.io/role/internal-elb": "1"
#       },
#       "timeouts": null
#     }
#   }
# }


# export AWS_ACCESS_KEY_ID="op://$PROJECT_ENV/aws_credentials/AWS_ACCESS_KEY_ID"
# export AWS_SECRET_ACCESS_KEY="op://$PROJECT_ENV/aws_credentials/AWS_SECRET_ACCESS_KEY"
# export TF_TOKEN_app_terraform_io="op://$PROJECT_ENV/terraform_credentials/TF_TOKEN_app_terraform_io"
# export GH_TOKEN="op://digital-defiance-personal/github/GH_TOKEN"


class TerraformOutput(TypedDict):
    ami: dict
    security_group_id: dict
    db_instance_master_username: dict
    db_instance_endpoint: dict
    ami: dict

@object_type
class CloudInfrastructure:

    @function
    async def run_instance(self,
        op_token: Annotated[dagger.Secret, Doc("1password service token")],
    ) -> str:

        raw_terraform_output: str = await (
            dag.container()
            .from_("ghcr.io/digital-defiance/cloud-infrastructure")
            .with_env_variable("PROJECT_ENV", "digital-defiance-cloud-infrastructure-prod")
            .with_secret_variable("OP_SERVICE_ACCOUNT_TOKEN", op_token)
            .with_env_variable("TF_TOKEN_app_terraform_io", "op://digital-defiance-cloud-infrastructure-prod/terraform_credentials/TF_TOKEN_app_terraform_io")
            .with_exec(["git", "clone", "https://github.com/Digital-Defiance/cloud-infrastructure.git"])
            .with_workdir("cloud-infrastructure/.github/aws")
            .with_exec(["op", "run", "--", "terraform", "init"])
            .with_exec(["op", "run", "--", "terraform", "apply", "-auto-approve"])
            .with_exec(["op", "run", "--", "terraform", "output", "-json" ])
            .stdout()
        )
        terraform_output: TerraformOutput = json.loads(raw_terraform_output)
        cmd = ""
        for name, value in terraform_output.items():
            if name == "subnet_ids":
                value = value["value"]["ids"][0]
                name = "subnet_id"
            else:
                value = value["value"]

            cmd += f"echo '{name}={value}' >> $GITHUB_OUTPUT && "

        return cmd[:-3]




