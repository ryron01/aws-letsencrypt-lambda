provider "aws" {
  region = "us-west-2"
  profile = "infra-prod-role/Admin"
}

module "notify_slack" {
  source = "terraform-aws-modules/notify-slack/aws"

  sns_topic_name        = "certbot-slack"
  lambda_function_name  = "certbot-notifier"
  slack_webhook_url     = "${var.slack_webhook_url}"
  slack_channel         = "${var.slack_channel}"
  slack_username        = "certbot"
}

resource "aws_cloudwatch_event_rule" "check-cert-event" {
    name = "check-cert-event"
    description = "Triggers a lambda to update the letsencrypt certificate if needed"
    schedule_expression = "cron(0 1 1 * ? *)"
}

resource "aws_cloudwatch_event_target" "check-cert-lambda-target" {
    target_id = "check-cert"
    rule = "${aws_cloudwatch_event_rule.check-cert-event.name}"
    arn = "${aws_lambda_function.check-cert-lambda.arn}"
  }

resource "aws_iam_policy" "check-cert-lambda-policy" {
  name        = "check-cert-lambda"
  policy = "${file("lambdaexecutionpolicy.json")}"
}

data "aws_iam_policy_document" "lambda-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "check-cert-lambda-role" {
  name               = "check-cert-lambda"
  assume_role_policy = "${data.aws_iam_policy_document.lambda-assume-role-policy.json}"
}

resource "aws_iam_role_policy_attachment" "check-cert-lambda-role" {
    role       = "${aws_iam_role.check-cert-lambda-role.name}"
    policy_arn = "${aws_iam_policy.check-cert-lambda-policy.arn}"
}

resource "aws_iam_role_policy_attachment" "basic-exec-role" {
    role       = "${aws_iam_role.check-cert-lambda-role.name}"
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "vpc-exec-role" {
    role       = "${aws_iam_role.check-cert-lambda-role.name}"
    policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_permission" "allow_cloudwatch_to_call_lambda" {
    statement_id = "AllowExecutionFromCloudWatch"
    action = "lambda:InvokeFunction"
    function_name = "${aws_lambda_function.check-cert-lambda.function_name}"
    principal = "events.amazonaws.com"
    source_arn = "${aws_cloudwatch_event_rule.check-cert-event.arn}"
}

resource "aws_lambda_function" "check-cert-lambda" {
    filename = "fetch_cert.zip"
    function_name = "check-cert-lambda"
    role = "${aws_iam_role.check-cert-lambda-role.arn}"
    handler = "fetch_cert.handler"
    runtime = "python2.7"
    timeout = 30
    source_code_hash = "${base64sha256(file("fetch_cert.zip"))}"
    environment {
      variables = {
        DOMAIN = "${var.domain}"
        DOMAIN_EMAIL = "${var.email}"
        NOTIFICATION_SNS_ARN = "${module.notify_slack.this_slack_topic_arn}"
        BUCKET = "${var.s3_bucket}"
      }
    }
    vpc_config {
      subnet_ids = ["${var.subnets}"]
      security_group_ids = ["${aws_security_group.check-cert-lambda-sg.id}"]
    }
}

data "aws_subnet" "private_subnet" {
  id = "${var.subnets[0]}"
}

resource "aws_security_group" "check-cert-lambda-sg" {
  name        = "allow_outbound"
  description = "Allow all outbound traffic"
  vpc_id = "${data.aws_subnet.private_subnet.vpc_id}"

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }
  tags = {
    Name = "check-cert-lambda-sg"
  }
}
