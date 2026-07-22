# 05 — Cleanup

```bash
terraform destroy
```

Most resources delete cleanly. A few things to know:

## Client VPN takes the longest

`aws_ec2_client_vpn_network_association` deletions can take several minutes each
(AWS drains the associated ENIs). If `destroy` seems to hang on the VPN, that's
usually why — let it run. The ACM certs (`aws_acm_certificate`) can only delete
after the Client VPN endpoint that references them is gone; Terraform orders
this correctly, but a stuck endpoint deletion will block them.

## ECR images / S3 source bucket

The ECR repos are created with `force_delete = true` and the CodeBuild source
bucket with `force_destroy = true`, so `destroy` removes them even though they
contain objects. If you disabled those for production, empty them first.

## Aurora

`skip_final_snapshot = true` and `deletion_protection = false` in this sample,
so the cluster deletes without a snapshot. If you flipped those for production,
`destroy` will refuse until you either take/allow a final snapshot or disable
deletion protection.

## What Terraform does NOT delete

- **CloudWatch log groups** created implicitly by ECS/CodeBuild outside the
  `aws_cloudwatch_log_group` resources this repo manages (there generally are
  none — the repo creates the gateway/console/VPN groups explicitly — but check
  for any `/aws/codebuild/...` group if you changed the build config).
- **Secrets** are deleted, but Secrets Manager enforces a recovery window by
  default. To purge immediately:
  ```bash
  aws secretsmanager delete-secret --secret-id <arn> --force-delete-without-recovery
  ```
- The local `claude-gateway-vpn.ovpn` file (git-ignored) — remove it yourself;
  it contains a private key.

## Verify nothing lingers

```bash
aws ec2 describe-client-vpn-endpoints --query 'ClientVpnEndpoints[].ClientVpnEndpointId'
aws rds describe-db-clusters --query 'DBClusters[?starts_with(DBClusterIdentifier, `claude-gateway`)].DBClusterIdentifier'
aws ecr describe-repositories --query 'repositories[?starts_with(repositoryName, `claude-gateway`)].repositoryName'
```
