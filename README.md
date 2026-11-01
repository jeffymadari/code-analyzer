# Cyber-Security Agent

## A Code Analyzer via Semgrep MCP server for GCP

![Course Image](assets/cyber.png)

_If you're looking at this in Cursor, please right click on the filename in the Explorer on the left, and select "Open preview", to view it in formatted glory._

#### Keep in mind

- Please submit your community_contributions, including links to your repos, in the production repo community_contributions folder
- Regularly do a git pull to get the latest code

#### Deploying to GCP with GitHub Actions

1. Run the one-time setup, then add the variables and secrets it prints to your GitHub repo. On Windows, use Git Bash:

   ```bash
   gcloud auth login
   ./scripts/setup-gcp-github.sh <gcp-project-id> <github-owner/repo>
   ```

2. To deploy, open the Actions tab, choose **Deploy to GCP**, then click **Run workflow**. The live URL appears in the run summary.
3. To remove everything, run **Destroy GCP deployment** and type `destroy` to confirm. This deletes the Cloud Run service, the registry and its images. The state bucket stays, so you can deploy again later.

To run Terraform for GCP by hand, initialize it with the same state bucket:

```bash
terraform init -backend-config="bucket=<gcp-project-id>-tfstate"
```