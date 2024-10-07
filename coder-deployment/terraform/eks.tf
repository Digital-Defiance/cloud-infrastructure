
# ------------------------------------------------------------------
# DATA
# ------------------------------------------------------------------

# https://aws.amazon.com/blogs/containers/amazon-ebs-csi-driver-is-now-generally-available-in-amazon-eks-add-ons/ 
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}


# ------------------------------------------------------------------
# RESOURCES
# ------------------------------------------------------------------

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.44.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}


module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.24.3"

  cluster_name    = "cloud-dev-infra"
  cluster_version = "1.29"

  cluster_endpoint_private_access = true

  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  create_iam_role = true

  cluster_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
    }
  }

  cluster_additional_security_group_ids = [
    module.https_443_security_group.security_group_id
  ]

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"
  }

  # https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest/submodules/eks-managed-node-group
  eks_managed_node_groups = {
    one = {
      name = "node-group-1"

      instance_types = ["t3.small"]
      capacity_type  = "SPOT"

      min_size     = 0
      max_size     = 3
      desired_size = 1
    }
  }
}

resource "aws_iam_policy" "coder_policy" {
  name        = "cloud-infra-coder-policy"
  path        = "/"
  description = "Permissions required by coder to manage aws instances"

  # https://github.com/coder/coder/tree/main/examples/templates/aws-linux#required-permissions--policy
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "VisualEditor0",
        "Effect" : "Allow",
        "Action" : [
          "ec2:GetDefaultCreditSpecification",
          "ec2:DescribeIamInstanceProfileAssociations",
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeInstanceTypes",
          "ec2:CreateTags",
          "ec2:RunInstances",
          "ec2:DescribeInstanceCreditSpecifications",
          "ec2:DescribeImages",
          "ec2:ModifyDefaultCreditSpecification",
          "ec2:DescribeVolumes"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "CoderResources",
        "Effect" : "Allow",
        "Action" : [
          "ec2:DescribeInstanceAttribute",
          "ec2:UnmonitorInstances",
          "ec2:TerminateInstances",
          "ec2:StartInstances",
          "ec2:StopInstances",
          "ec2:DeleteTags",
          "ec2:MonitorInstances",
          "ec2:CreateTags",
          "ec2:RunInstances",
          "ec2:ModifyInstanceAttribute",
          "ec2:ModifyInstanceCreditSpecification"
        ],
        "Resource" : "arn:aws:ec2:*:*:instance/*",
        "Condition" : {
          "StringEquals" : {
            "aws:ResourceTag/Coder_Provisioned" : "true"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach-to-one" {
  role       = module.eks.eks_managed_node_groups.one.iam_role_name
  policy_arn = aws_iam_policy.coder_policy.arn
}

# ------------------------------------------------------------------
# OUTPUT
# ------------------------------------------------------------------

output "aws_configuration_command" {
  value = "aws eks update-kubeconfig --region eu-south-1 --name ${module.eks.cluster_name}"
}

