# Multi-Region-Disaster-Recovery

Terraform-codified multi-region AWS infrastructure designed to survive a regional failure — automated traffic routing, replicated data, continuous health checks, and a tested failover process.

## Overview

This project provisions identical infrastructure across two AWS regions and wires them together so that a full regional outage doesn't take the application down. Traffic is routed globally via Route53 and CloudFront, data is replicated cross-region via RDS and S3, and failover is automated and health-check-driven rather than manual.

**Regions:** `ap-south-1` (primary) · `us-east-1` (secondary)

**Topology:** Active-passive — secondary stays warm, promoted on failover

**Tech stack:** AWS, Terraform, Route53, CloudFront, S3, RDS, ALB, Auto Scaling, IAM

## Status

Complete — Day 14 of 14 done (region selection, topology decision, shared Terraform module for VPC/subnets/security groups, ALB + Auto Scaling Group verified in both regions, remote state on S3/DynamoDB, IAM instance roles attached, RDS cross-region read replica live, S3 Cross-Region Replication verified, CloudFront with origin failover live, automated RDS replica promotion verified end to end, secondary's Auto Scaling tuned with a warm pool + target-tracking scaling for fast failover absorption; a simulated regional-outage failover test passed end to end with failback to steady state; a controlled promotion then verified zero data loss post-failover with the promoted database writable and the DR posture restored; and the build was finalized with a failover/failback operator runbook, a maintained Mermaid architecture diagram, a defined periodic DR-testing cadence, and the RDS master password migrated to AWS Secrets Manager so it no longer lives in Terraform state). See [PLAN.md](./docs/PLAN.md) for the day-by-day build plan, current progress, and architecture decisions.

## Architecture

Design, topology diagram, and decision rationale in [docs/architecture/architecture.md](./docs/architecture/architecture.md).

## Key Deliverable

A Terraform-codified, multi-region AWS architecture with replicated data, health-check-driven Route53/CloudFront failover, and a tested regional-outage runbook.
