#!/bin/sh

TERRAFORM_IN_ACTION="/run/cube_terraform_in_action.lock"
flock -w 120 $TERRAFORM_IN_ACTION /usr/local/bin/terraform-action.sh "$@"
