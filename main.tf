locals {
  exposed_tasks = [for task in var.tasks: task if task.port != null]
}

resource "aws_iam_role" "svc" {
  name = "${var.name}-ecs-role"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
	{
	  "Sid": "",
	  "Effect": "Allow",
	  "Principal": {
		"Service": "ecs.amazonaws.com"
	  },
	  "Action": "sts:AssumeRole"
	}
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "svc" {
  role       = aws_iam_role.svc.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

resource "aws_cloudwatch_log_group" "svc" {
  count = length(var.log_groups)
  name  = var.log_groups[count.index]
  tags  = merge(var.tags, map("Name", format("%s", var.name)))
}

resource "aws_ecs_service" "svc" {
  name            = var.name
  cluster         = var.cluster
  task_definition = aws_ecs_task_definition.service.id
  desired_count   = var.desired_count
  iam_role        = aws_iam_role.svc.arn

  deployment_maximum_percent         = var.deployment_maximum_percent
  deployment_minimum_healthy_percent = var.deployment_minimum_healthy_percent

  dynamic "load_balancer" {
    for_each = local.exposed_tasks
    iterator = task
    content {
      target_group_arn = var.alb_target_group_arn
      container_name   = task.name
      container_port   = task.port
    }
  }
}

data "template_file" "env_vars" {
  count    = length(var.tasks)
  template = "[${join(",", formatlist("\"%s\": \"%s\"", keys(var.tasks[count.index].envVars), values(var.tasks[count.index].envVars)))}]"

}

data "template_file" "task_defs" {
  count    = length(var.tasks)
  template = file("${path.module}/task-definition.json")
  vars = {
    NAME      = var.tasks[count.index].name
    IMAGE     = var.tasks[count.index].image
    CPU       = var.tasks[count.index].cpu
    MEMORY    = var.tasks[count.index].memory
    ESSENTIAL = var.tasks[count.index].essential
    PORT      = var.tasks[count.index].port,
    ENV_VARS  = data.template_file.env_vars[count.index].rendered
  }
}

resource "aws_ecs_task_definition" "service" {
  family                = var.name
  container_definitions = "[${join(",", data.template_file.task_defs.*.rendered)}]"
}
