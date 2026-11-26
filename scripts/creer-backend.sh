#!/usr/bin/env bash
# Cree le bucket de state Terraform de l'equipe : versionne, chiffre, sans acces public.
# A lancer une seule fois par le referent AWS, avant le premier terraform init.
set -euo pipefail

REGION="${REGION:-eu-west-3}"
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET="novasphere-tfstate-${ACCOUNT}"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
  echo "Le bucket $BUCKET existe deja."
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
fi

aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "Bucket de state pret : $BUCKET (region $REGION)"
