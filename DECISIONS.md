# Infrastructure Decisions

## Audit Findings
<!-- For each issue you find, document:
     - What the issue is
     - Why it's a problem (impact/risk)
     - How you fixed it
     - What you'd do differently in a production environment with more time -->

### GitHub Actions

- **Security Issue**: AWS access credentials are in plain text in the `deploy.yml` file.

  - **Severity**: Critical
  - **Impact**: It gives any external actor the ability to access internal resources and since it is meant for deployment (ie. not just read access) it has a high potential for abuse.
  - **Fix**: The `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` values should be rotated _immediately_ and should be stored in a secure manner. Simplest fix is to use repository secrets.
  - **Production Recommendation**: I would implement OIDC authentication in the GitHub Actions workflow. This would remove the need to store any credentials as it relies on established trust between GitHub and AWS.

- **Security Issue**: The actions used from external sources are not pinned to specific SHAs.

  - **Severity**: High
  - **Impact**: This makes the actions vulnerable to supply chain attacks. If one of the actions are compromised and a malicious version is released with the same tag name, it will be used instead of the intended version.
  - **Fix**: The actions should be pinned to a specific SHA.
  - **Production Recommendation**: Implement renovate to automate action version updates.

- **Operational Issue**: A Docker image is never built.

  - **Severity**: High
  - **Impact**: Any app changes will not be reflected in the deployed ECS task.
  - **Fix**: The deploy workflow should build the Docker image before applying the Terraform changes.
  - **Production Recommendation**: Design an image promotion process that limits the amount of rebuilds and redeploys.

- **Operational Issue**: Terraform is applied using the `-auto-approve` flag. This means that any changes to the infrastructure will be applied without any confirmation.

  - **Severity**: Medium
  - **Impact**: It makes it easy to apply unexpected changes to the infrastructure.
  - **Fix**: I would implement a PR based process that first runs a plan when the PR is created or updated. The plan is then communicated via a comment, ensuring the user has a chance to review the changes before they are applied.
  - **Production Recommendation**: n/a

- **Reliability Issue**: There is no concurrency control for the deploy workflow.

  - **Severity**: Medium
  - **Impact**: When combined with the lack of locking in the Terraform state, this allows multiple users to apply changes to the infrastructure at the same time, which can lead to conflicts and data loss.
  - **Fix**: The deploy workflow should be configured with concurrency control.
  - **Production Recommendation**: n/a

### Terraform

- **Security Issue**: The ECS task effectively has full access to the AWS account.

  - **Severity**: Critical
  - **Impact**: The running application has full access to the AWS account.
  - **Fix**: The ECS task role should be limited to the minimum necessary permissions: S3, RDS, ECR, and CloudWatch.
  - **Production Recommendation**: n/a

- **Security Issue**: The database credentials are exposed in plain text in Terraform variables.

  - **Severity**: Critical
  - **Impact**: Anyone with access to the repository can access the database credentials and thus the database itself.
  - **Fix**: The database credentials should be stored in a secure manner. Simplest fix is to use repository secrets.
  - **Production Recommendation**: I would implement Secrets Manager to store the database credentials.

- **Security Issue**: The RDS instance is not encrypted at rest.

  - **Severity**: High
  - **Impact**: It makes the data in the RDS instance vulnerable to unauthorized access.
  - **Fix**: The RDS instance should be encrypted at rest.
  - **Production Recommendation**: I would use a customer managed KMS key instead of the default AWS key.

- **Reliability Issue**: The ECS service does not configure CloudWatch logging or metrics.

  - **Severity**: High
  - **Impact**: Without logging and metrics, it is almost impossible to troubleshoot issues with the ECS service.
  - **Fix**: Create a CloudWatch log group and stream the ECS task logs to it. Enable Container Insights on the ECS cluster to ensure metrics are collected.
  - **Production Recommendation**: I would also enable enhanced observability at the account level to collect the full breadth of metrics available.

- **Reliability Issue**: The Terraform state is not configured with locking.

  - **Severity**: Medium
  - **Impact**: Prevents multiple users from testing or applying changes to the infrastructure at the same time.
  - **Fix**: The Terraform state should be configured with S3 native locking.
  - **Production Recommendation**: I would also ensure the bucket is encrypted at rest.

- **Reliability Issue**: There is no health check configured for the ECS service.

  - **Severity**: Medium
  - **Impact**: Though the app is exposing a `/health` endpoint, the Dockerfile does not include any health check command. In addition, the ECS service does not have a health check configured. This means that the ECS orchestrator will not be able to determine if the task is healthy and will thus not be able to restart or replace it if it fails.
  - **Fix**: The ECS service should be configured with a health check.
  - **Production Recommendation**: n/a

- **Operational Issue**: No lockfile is committed to the repository.

  - **Severity**: Low
  - **Impact**: Allows inconsistent provider versions to be used across multiple users.
  - **Fix**: The lockfile should be committed to the repository.
  - **Production Recommendation**: I would implement a pre-commit hook that checks for the lockfile and fails the push if it is not present.

## Architecture Observations
<!-- What's your assessment of the overall infrastructure design?
     What patterns or anti-patterns do you see beyond the specific bugs? -->

The overall design has a few areas of concern. While functional, overall I'd rate the security and availability of the infrastructure as poor for a production environment.

- Only one subnet of each private and public zone is used for the VPC. There should be at least two--ideally three--availability zones, each with a subnet of each type (i.e. `private-a`, `private-b`, `private-c`, `public-a`, `public-b`, `public-c`, etc.).

  - Ideally a third subnet type that does not allow routing to the internet should be used for the RDS instance.

- The ALB is not configured to present the application over HTTPS. ACM should be used to issue a certificate and attach it to the ALB.

  - There should also be a custom domain name associated with the ALB as the default FQDN is not very memorable.

- The ECS service should ideally scale the task based on the CPU and/or memory usage.

- Encryption at rest is not enabled for RDS or S3. At a minimum AWS provided keys should be implemented, but ideally they should be customer managed KMS keys.

- There is only one RDS instance. At a minimum a read replica should be configured for high availability. There should be one in each availability zone if more than two are available.

- The RDS instance is not configured with a backup policy. At a minimum a daily backup should be configured.

I see a consistent pattern of exposing secrets in plaintext. The database credentials are committed as Terraform variables, and passed to the ECS task as environment variables. The former allows anyone with access to the repository to access the credentials, while the latter allows anyone with access to AWS console to view them.

The AWS credentials are committed as environment variables in the GitHub Actions workflow. While its not clear what IAM role these are associated with, given the extremely broad permissions granted to the ECS task role it is not big jump to say that this role is also overprivileged. This presents a very real threat of account compromise if the credentials are leaked.

## Improvement Implemented
<!-- Which improvement did you choose to implement and why?
     Why did you prioritize this one over others? -->

I primarily chose to address the plaintext credential issues, with a secondary focus on improving the deployment pipeline. I implemented the PR based process for the Terraform plan and apply workflows, pinned the actions to specific SHAs, and moved the AWS and database credentials to repository secrets with Secrets Manager on the AWS side. I prioritized this as it has the highest impact to the security posture of the repository and application.

## Improvements Proposed
<!-- Describe 2 additional improvements you would make.
     For each: what, why, estimated effort, and trade-offs. -->

1. Implement a Docker image build step in the GitHub Actions workflows. This would ensure that the ECS task is always running the latest version of the application. Would likely require a few hours of work to test and validate. Trade-off is that it adds complexity to the deployment pipeline, but without it any app changes would not be reflected in the deployed ECS task.

2. Address the IAM security issues by implementing OIDC authentication for GitHub Actions and create dedicated roles for Terraform plan/apply, ECR push, and ECS task execution. Each would be created with least privilege principles in mind, which would further reduce the attack surface and plug the remaining gaping holes in security posture. Would also likely require a few hours of work to test and validate.

## AI Usage
<!-- If you used AI tools, describe:
     - Which tools and how you used them
     - What you validated or changed from AI suggestions
     - What you chose NOT to use AI for and why
     If you did not use AI tools, simply state that. -->

I used Cursor only as auto-completion and formatting assistance. I did not use it for any other purpose. I regularly adjusted suggestions it made to ensure they were correct and aligned with my intentions.

I intentionally did not prompt it to assess the codebase or propose improvements. I wanted to ensure those were entirely my own ideas.
