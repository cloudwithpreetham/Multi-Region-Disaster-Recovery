# Multi-Region-Disaster-Recovery

Terraform-codified multi-region AWS infrastructure designed to survive a regional failure — automated traffic routing, replicated data, continuous health checks, and a tested failover process.

## Overview

This project provisions identical infrastructure across two AWS regions and wires them together so that a full regional outage doesn't take the application down. Traffic is routed globally via Route53 and CloudFront, data is replicated cross-region via RDS and S3, and failover is automated and health-check-driven rather than manual.

**Regions:** `ap-south-1` (primary) · `us-east-1` (secondary)

**Topology:** Active-passive — secondary stays warm, promoted on failover

**Tech stack:** AWS, Terraform, Route53, CloudFront, S3, RDS, ALB, Auto Scaling, IAM

## Status

Complete — Day 14 of 14 done. The project includes the multi-region Terraform platform, replicated RDS and S3 data, CloudFront failover, automated promotion with split-brain protection, warm standby capacity, tested failover/failback, zero-loss controlled promotion validation, Secrets Manager-managed RDS credentials, and HTTPS-only regional ALB origins. Regional ACM certificates, DNS aliases, ALB 443 listeners, CloudFront HTTPS origins, and Route 53 HTTPS health checks are deployed and passing. See [PLAN.md](./docs/PLAN.md) for the day-by-day build plan, current progress, and architecture decisions.

## Architecture

Design, topology diagram, and decision rationale in [docs/architecture/architecture.md](./docs/architecture/architecture.md).

## Key Deliverable

A Terraform-codified, multi-region AWS architecture with replicated data, health-check-driven Route53/CloudFront failover, and a tested regional-outage runbook.
