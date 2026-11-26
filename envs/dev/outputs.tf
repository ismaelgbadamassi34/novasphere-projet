output "alb_dns_name" {
  description = "Adresse du site"
  value       = module.web.alb_dns_name
}

output "vpc_id" {
  description = "Identifiant du reseau"
  value       = module.vpc.vpc_id
}
