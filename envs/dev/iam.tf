data "aws_caller_identity" "current" {}

resource "aws_iam_role" "web" {
  name = "novasphere-${var.environment}-web"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lire_secret" {
  name = "lire-secret-${var.environment}"
  role = aws_iam_role.web.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ssm:GetParameter"
      Resource = "arn:aws:ssm:eu-west-3:${data.aws_caller_identity.current.account_id}:parameter/novasphere/${var.environment}/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "session_manager" {
  role       = aws_iam_role.web.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "web" {
  name = "novasphere-${var.environment}-web"
  role = aws_iam_role.web.name
}
