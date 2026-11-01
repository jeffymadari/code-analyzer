#!/usr/bin/env bash
# One-time setup that lets the GitHub Actions workflows deploy to GCP.
# Safe to run again: anything that already exists is left in place.
#
# Usage: ./scripts/setup-gcp-github.sh <gcp-project-id> [github-owner/repo]

set -euo pipefail

PROJECT_ID="${1:?Usage: $0 <gcp-project-id> [github-owner/repo]}"
REPO="${2:-jeffymadari/code-analyzer}"
REGION="us-central1"

BUCKET="${PROJECT_ID}-tfstate"
POOL="github"
PROVIDER="github"
SERVICE_ACCOUNT="github-deploy@${PROJECT_ID}.iam.gserviceaccount.com"

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
RUNTIME_SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
POOL_PATH="projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${POOL}"

# A new service account can take a minute to be recognised, so retry anything that uses it
retry() {
  local attempt
  for attempt in 1 2 3 4 5 6 7 8; do
    if "$@" >/dev/null; then
      return 0
    fi
    echo "Not ready yet, retrying in 15 seconds (attempt ${attempt} of 8)..."
    sleep 15
  done
  "$@" >/dev/null
}

echo "Enabling APIs..."
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  cloudresourcemanager.googleapis.com \
  compute.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  run.googleapis.com \
  serviceusage.googleapis.com \
  sts.googleapis.com \
  --project "$PROJECT_ID"

echo "Creating the Terraform state bucket..."
if ! gcloud storage buckets describe "gs://${BUCKET}" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud storage buckets create "gs://${BUCKET}" \
    --project "$PROJECT_ID" \
    --location "$REGION" \
    --uniform-bucket-level-access \
    --public-access-prevention
fi
# Versioning keeps earlier copies of the state if one gets damaged
gcloud storage buckets update "gs://${BUCKET}" --versioning

echo "Creating the deploy service account..."
if ! gcloud iam service-accounts describe "$SERVICE_ACCOUNT" --project "$PROJECT_ID" >/dev/null 2>&1; then
  gcloud iam service-accounts create github-deploy \
    --project "$PROJECT_ID" \
    --display-name "GitHub Actions deploy"
fi

echo "Granting the service account what Terraform needs..."
for ROLE in roles/run.admin roles/artifactregistry.admin roles/serviceusage.serviceUsageAdmin; do
  retry gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:${SERVICE_ACCOUNT}" \
    --role "$ROLE" \
    --condition None \
    --quiet
done

# Cloud Run services run as this account, and deploying one requires permission to use it
retry gcloud iam service-accounts add-iam-policy-binding "$RUNTIME_SERVICE_ACCOUNT" \
  --project "$PROJECT_ID" \
  --member "serviceAccount:${SERVICE_ACCOUNT}" \
  --role roles/iam.serviceAccountUser \
  --quiet

retry gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
  --member "serviceAccount:${SERVICE_ACCOUNT}" \
  --role roles/storage.objectAdmin \
  --quiet

echo "Trusting GitHub Actions from ${REPO}..."
if ! gcloud iam workload-identity-pools describe "$POOL" \
  --project "$PROJECT_ID" --location global >/dev/null 2>&1; then
  gcloud iam workload-identity-pools create "$POOL" \
    --project "$PROJECT_ID" \
    --location global \
    --display-name "GitHub Actions"
fi

if ! gcloud iam workload-identity-pools providers describe "$PROVIDER" \
  --project "$PROJECT_ID" --location global --workload-identity-pool "$POOL" >/dev/null 2>&1; then
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
    --project "$PROJECT_ID" \
    --location global \
    --workload-identity-pool "$POOL" \
    --display-name "GitHub" \
    --issuer-uri "https://token.actions.githubusercontent.com" \
    --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --attribute-condition "assertion.repository == '${REPO}'"
fi

retry gcloud iam service-accounts add-iam-policy-binding "$SERVICE_ACCOUNT" \
  --project "$PROJECT_ID" \
  --member "principalSet://iam.googleapis.com/${POOL_PATH}/attribute.repository/${REPO}" \
  --role roles/iam.workloadIdentityUser \
  --quiet

cat <<EOF

Done. Now add these in GitHub under Settings > Secrets and variables > Actions.

Variables:
  GCP_PROJECT_ID                  ${PROJECT_ID}
  GCP_WORKLOAD_IDENTITY_PROVIDER  ${POOL_PATH}/providers/${PROVIDER}

Secrets:
  OPENAI_API_KEY                  your OpenAI key
  SEMGREP_APP_TOKEN               your Semgrep token
EOF
