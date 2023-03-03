locals {
  eks_oidc_issuer_url = replace(var.eks_oidc_provider_arn, "/^(.*provider/)/", "")
  //eks_oidc_issuer_url = replace(var.eks_oidc_provider_arn, "https://", "")
}

resource "kubernetes_namespace_v1" "irsa" {
  count = var.create_kubernetes_namespace && var.kubernetes_namespace != "kube-system" ? 1 : 0
  metadata {
    name = var.kubernetes_namespace
  }

  timeouts {
    delete = "15m"
  }
}

resource "kubernetes_secret_v1" "irsa" {
  count = var.create_kubernetes_service_account && var.create_service_account_secret_token ? 1 : 0
  metadata {
    name        = format("%s-token-secret", try(kubernetes_service_account_v1.irsa[0].metadata[0].name, var.kubernetes_service_account))
    namespace   = try(kubernetes_namespace_v1.irsa[0].metadata[0].name, var.kubernetes_namespace)
    annotations = {
      "kubernetes.io/service-account.name"      = try(kubernetes_service_account_v1.irsa[0].metadata[0].name, var.kubernetes_service_account)
      "kubernetes.io/service-account.namespace" = try(kubernetes_namespace_v1.irsa[0].metadata[0].name, var.kubernetes_namespace)
    }
  }

  type = "kubernetes.io/service-account-token"
}

resource "kubernetes_service_account_v1" "irsa" {
  count = var.create_kubernetes_service_account ? 1 : 0
  metadata {
    name        = var.kubernetes_service_account
    namespace   = try(kubernetes_namespace_v1.irsa[0].metadata[0].name, var.kubernetes_namespace)
    annotations = var.irsa_iam_policies != null ? { "eks.amazonaws.com/role-arn" : alks_iamrole.irsa[0].arn } : null
  }

  dynamic "image_pull_secret" {
    for_each = var.kubernetes_svc_image_pull_secrets != null ? var.kubernetes_svc_image_pull_secrets : []
    content {
      name = image_pull_secret.value
    }
  }

  automount_service_account_token = true
}

# NOTE: Don't change the condition from StringLike to StringEquals. We are using wild characters for service account hence StringLike is required.
resource "alks_iamrole" "irsa" {
  count = var.irsa_iam_policies != null ? 1 : 0

  name = try(coalesce(var.irsa_iam_role_name, format("%s-%s-%s", var.eks_cluster_id, trim(var.kubernetes_service_account, "-*"), "irsa")), null)
  assume_role_policy = data.aws_iam_policy_document.aws_assume_role_policy.json

  tags = var.tags
}

data "aws_iam_policy_document" "aws_assume_role_policy" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [
        var.eks_oidc_provider_arn
      ]
    }
    condition {
      test     = "StringLike"
      variable = "${local.eks_oidc_issuer_url}:sub"
      values   = [
        "system:serviceaccount:${var.kubernetes_namespace}:${var.kubernetes_service_account}"
      ]
    }
    condition {
      test     = "StringLike"
      variable = "${local.eks_oidc_issuer_url}:aud"
      values   = [
        "sts.amazonaws.com"
      ]
    }
  }
}
